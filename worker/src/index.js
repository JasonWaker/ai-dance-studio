/**
 * AI Dance Studio · 持久化异步 Worker
 *
 * 功能：
 *   1. claim: 从 Supabase generation_jobs 表原子抢占 queued 任务（租约机制）
 *   2. submit: 调用 AI Provider 创建远端任务，记录 provider_job_id
 *   3. poll: 指数退避轮询远端任务状态
 *   4. archive: 下载成片 → Supabase Storage → 更新 generation_jobs + 创建成品记录
 *   5. reconcile: reconciling 状态处理（幂等核对）
 *   6. 失败分类 + 有限重试
 *
 * 运行：node src/index.js（本地开发 / 服务器）
 * 并发：通过 lease_owner + lease_expires_at 实现，多 Worker 互不抢占
 */
import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
import axios from 'axios'
import { submitProviderJob, queryProviderJob } from '../backend/src/ai/providerV2.js'
import { uploadRemoteUrlToStorage } from '../backend/src/services/storageService.js'

// ========== 配置 ==========
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://uljvndjkdfbvazhrrxmd.supabase.co'
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY
const WORKER_ID = process.env.WORKER_ID || `worker-${process.pid}`
const POLL_INTERVAL_MS = Number(process.env.WORKER_POLL_INTERVAL || 3000)  // 主循环间隔
const LEASE_TIMEOUT_MS = Number(process.env.WORKER_LEASE_TIMEOUT || 120000)  // 租约超时
const CONCURRENCY_MAX = Number(process.env.WORKER_CONCURRENCY || 3)  // 最大并发

// ========== 初始化 ==========
let supabase = null
if (SERVICE_ROLE) {
  supabase = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false, autoRefreshToken: false } })
  console.log(`[worker] ✅ Supabase 已连接 (role=service_role)`)
} else {
  console.error('[worker] ❌ 未配置 SUPABASE_SERVICE_ROLE_KEY，Worker 无法运行')
  process.exit(1)
}

// ========== 工具函数 ==========
async function updateJob(id, patch) {
  const { error } = await supabase.from('generation_jobs').update(patch).eq('id', id)
  if (error) console.error(`[worker] updateJob ${id} 失败:`, error.message)
}

async function logEvent(jobId, kind, payload = {}) {
  try {
    await supabase.from('generation_events').insert({ job_id: jobId, kind, payload })
  } catch (e) { /* 不阻塞主流程 */ }
}

async function getLeasableJobs() {
  // 抢占 queued 的新任务
  const { data: queued, error: e1 } = await supabase
    .from('generation_jobs')
    .select('*')
    .eq('status', 'queued')
    .order('created_at', { ascending: true })
    .limit(CONCURRENCY_MAX)
  if (e1) { console.error('[worker] fetch queued 失败:', e1.message); return [] }

  // 抢占已到轮询时间的 running/submitted 任务（租约过期）
  const now = new Date().toISOString()
  const { data: polling, error: e2 } = await supabase
    .from('generation_jobs')
    .select('*')
    .in('status', ['submitted', 'running'])
    .or(`lease_expires_at.is.null,lease_expires_at.lt.${now}`)
    .or(`next_poll_at.is.null,next_poll_at.lte.${now}`)
    .order('next_poll_at', { ascending: true, nullsFirst: true })
    .limit(CONCURRENCY_MAX)
  if (e2) console.error('[worker] fetch polling 失败:', e2.message)

  const pool = [...(queued || []), ...(polling || [])]

  // 用租约标记
  const results = []
  for (const job of pool) {
    const newStatus = job.status === 'queued' ? 'submitting' : 'running'
    const leaseExpires = new Date(Date.now() + LEASE_TIMEOUT_MS).toISOString()
    const { data, error } = await supabase
      .from('generation_jobs')
      .update({
        status: newStatus,
        lease_owner: WORKER_ID,
        lease_expires_at: leaseExpires,
        attempt_count: job.status === 'queued' ? (job.attempt_count || 0) + 1 : job.attempt_count
      })
      .eq('id', job.id)
      .eq('status', job.status)  // CAS 条件
      .select('*')
      .single()

    if (!error && data) results.push(data)
  }
  return results
}

// ========== 阶段 1: Submit ==========
async function processSubmitting(job) {
  console.log(`[worker] 📤 SUBMIT job=${job.id.slice(0,8)} mode=${job.mode} provider=${job.provider} model=${job.model_id}`)

  const snapshot = job.input_snapshot || {}
  const request = {
    provider: job.provider,
    model_id: job.model_id,
    prompt: job.prompt,
    image_ref: snapshot.image_ref || snapshot.start_image,
    video_ref: snapshot.reference_video,
    audio_ref: snapshot.audio_ref,
    aspect_ratio: job.aspect_ratio,
    duration_seconds: job.duration_seconds,
    params: {}
  }

  try {
    const submitResult = await submitProviderJob(request)
    console.log(`[worker] ✅ Submit 成功 remoteJobId=${submitResult.remoteJobId.slice(0,12)}...`)

    const isMock = submitResult.mock || process.env.MOCK_MODE === 'true'
    await updateJob(job.id, {
      status: 'submitted',
      provider_job_id: submitResult.remoteJobId,
      provider_raw_response: submitResult.raw || {},
      next_poll_at: new Date(Date.now() + 10000).toISOString(),  // 10s 后首次轮询
      mock_result: isMock ? true : undefined
    })
    await logEvent(job.id, 'submitted', { remoteJobId: submitResult.remoteJobId, mock: isMock })
  } catch (err) {
    console.error(`[worker] ❌ Submit 失败 job=${job.id}:`, err.message)
    await handleFailure(job, 'SUBMIT_FAILED', err.message)
  }
}

// ========== 阶段 2: Poll ==========
async function processPolling(job) {
  // 先延长租约
  await updateJob(job.id, {
    status: 'running',
    lease_expires_at: new Date(Date.now() + LEASE_TIMEOUT_MS).toISOString()
  })

  try {
    const remoteJobId = job.provider_job_id
    if (!remoteJobId) {
      // 没有 remote_job_id → reconciling
      await updateJob(job.id, { status: 'reconciling' })
      return
    }

    const queryResult = await queryProviderJob({ provider: job.provider, remoteJobId })
    console.log(`[worker] 📊 POLL job=${job.id.slice(0,8)} provider=${job.provider} status=${queryResult.status}`)

    if (queryResult.status === 'queued') {
      // 还在排队，稍后再查
      const nextPoll = Math.min(30000, 10000 * Math.pow(1.5, job.attempt_count || 0))
      await updateJob(job.id, {
        status: 'submitted',
        next_poll_at: new Date(Date.now() + nextPoll).toISOString()
      })
      return
    }

    if (queryResult.status === 'running') {
      // 进行中
      const nextPoll = Math.min(60000, 15000 * Math.pow(1.3, job.attempt_count || 0))
      await updateJob(job.id, {
        next_poll_at: new Date(Date.now() + nextPoll).toISOString()
      })
      return
    }

    if (queryResult.status === 'succeeded') {
      // 成功！进入归档
      await processArchive(job, queryResult)
      return
    }

    if (queryResult.status === 'failed') {
      await handleFailure(job, queryResult.errorCode || 'PROVIDER_FAILED', queryResult.errorMessage || 'Provider 返回失败')
      return
    }
  } catch (err) {
    console.error(`[worker] ⚠️ Poll 异常 job=${job.id}:`, err.message)
    // 网络临时错误 → 延长轮询
    const nextPoll = Math.min(30000, 10000 * Math.pow(2, job.attempt_count || 0))
    await updateJob(job.id, {
      next_poll_at: new Date(Date.now() + nextPoll).toISOString()
    })
  }
}

// ========== 阶段 3: Archive ==========
async function processArchive(job, queryResult) {
  console.log(`[worker] 📦 ARCHIVE job=${job.id.slice(0,8)} 输出数=${queryResult.outputUrls?.length || 0}`)

  const outputUrls = queryResult.outputUrls || []
  let resultUrl = null
  let assetId = null

  if (outputUrls.length > 0) {
    // 下载并上传到 Supabase Storage
    try {
      const uploadResult = await uploadRemoteUrlToStorage(outputUrls[0], 'outputs')
      resultUrl = uploadResult.url
    } catch (err) {
      console.warn(`[worker] Storage 归档失败，保留原始 URL:`, err.message)
      resultUrl = outputUrls[0]  // 保留原始 URL 不阻塞
    }
  }

  const finishedAt = new Date().toISOString()
  await updateJob(job.id, {
    status: 'succeeded',
    result_url: resultUrl,
    result_asset_id: assetId,
    actual_cost: queryResult.estimatedCost || null,
    cost_source: 'provider_bill',
    finished_at: finishedAt
  })

  // 创建成品 video 记录（兼容旧系统）
  try {
    const { v4: uuid } = await import('uuid')
    await supabase.from('videos').insert({
      id: uuid(),
      generation_job_id: job.id,
      file_url: resultUrl,
      resolution: job.resolution || '720p',
      bpm: null,
      compliance: 'pending'
    })
  } catch (err) {
    console.warn(`[worker] 创建 video 成品记录失败:`, err.message)
  }

  await logEvent(job.id, 'succeeded', { resultUrl, metadata: queryResult.metadata })
  console.log(`[worker] ✅ ARCHIVE 完成 job=${job.id.slice(0,8)} result=${resultUrl?.slice(0,60)}`)
}

// ========== 失败处理 ==========
async function handleFailure(job, code, message) {
  console.error(`[worker] ❌ FAIL job=${job.id.slice(0,8)} code=${code} msg=${message?.slice(0,100)}`)

  const maxAttempts = job.max_attempts || 3
  const nextAttemptCount = (job.attempt_count || 0)

  if (nextAttemptCount < maxAttempts && isRetryableError(code)) {
    // 重试
    console.log(`[worker] 🔄 重试 (${nextAttemptCount}/${maxAttempts})`)
    await updateJob(job.id, {
      status: 'queued',
      provider_job_id: null,
      lease_owner: null,
      lease_expires_at: null,
      failure_code: code,
      failure_message: message,
      next_poll_at: new Date(Date.now() + 5000).toISOString()
    })
    await logEvent(job.id, 'retry', { code, attempt: nextAttemptCount })
  } else {
    // 终态失败
    await updateJob(job.id, {
      status: 'failed',
      failure_code: code,
      failure_message: message,
      lease_owner: null,
      lease_expires_at: null,
      finished_at: new Date().toISOString()
    })
    await logEvent(job.id, 'failed', { code, message })
  }
}

function isRetryableError(code) {
  return ['SUBMIT_FAILED', 'NETWORK_TIMEOUT', 'RATE_LIMITED'].includes(code)
}

// ========== 主循环 ==========
async function mainLoop() {
  try {
    const jobs = await getLeasableJobs()
    if (jobs.length === 0) {
      // 空闲
      return
    }

    console.log(`\n[worker] ⚙️ 处理 ${jobs.length} 个任务`)

    for (const job of jobs) {
      if (job.status === 'submitting' || (job.status === 'queued' && job.lease_owner === WORKER_ID)) {
        await processSubmitting(job)
      } else if (['running', 'submitted'].includes(job.status)) {
        await processPolling(job)
      }
    }
  } catch (err) {
    console.error('[worker] mainLoop 异常:', err.message)
  }
}

// ========== 启动 ==========
console.log(`
╔══════════════════════════════════════════════════════╗
║  🎬 AI Dance Studio · Generation Worker             ║
║     worker_id: ${WORKER_ID.padEnd(42)} ║
║     supabase:  ${SUPABASE_URL.slice(0, 40).padEnd(42)} ║
║     concurrency: ${CONCURRENCY_MAX}   poll: ${POLL_INTERVAL_MS}ms               ║
╚══════════════════════════════════════════════════════╝
`)

// 定时循环（setInterval 简单可靠）
setInterval(mainLoop, POLL_INTERVAL_MS)
mainLoop()  // 立即跑一轮

// 优雅退出
process.on('SIGTERM', () => {
  console.log('\n[worker] 🛑 SIGTERM 收到，退出中...')
  process.exit(0)
})
process.on('SIGINT', () => {
  console.log('\n[worker] 🛑 SIGINT 收到，退出中...')
  process.exit(0)
})
