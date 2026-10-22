/**
 * Worker Tick —— Vercel Cron 定时触发入口
 * 每次调用执行一轮：claim → submit/poll → archive
 * 替代常驻 Worker 进程，适合 Vercel serverless 环境
 */
import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'
import { submitProviderJob, queryProviderJob } from './ai/providerV2.js'
import { uploadRemoteUrlToStorage } from './services/storageService.js'

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://uljvndjkdfbvazhrrxmd.supabase.co'
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY
const CONCURRENCY = Number(process.env.WORKER_CONCURRENCY || 3)

let supabase = null
if (SERVICE_ROLE) {
  supabase = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false }
  })
}

async function updateJob(id, patch) {
  if (!supabase) return
  await supabase.from('generation_jobs').update(patch).eq('id', id)
}

async function logEvent(jobId, kind, payload = {}) {
  if (!supabase) return
  try {
    await supabase.from('generation_events').insert({ job_id: jobId, kind, payload })
  } catch { /* ignore */ }
}

async function getLeasableJobs() {
  if (!supabase) return []
  const now = new Date().toISOString()

  // 1. 抢占 queued 新任务
  const { data: queued } = await supabase
    .from('generation_jobs')
    .select('*')
    .eq('status', 'queued')
    .order('created_at', { ascending: true })
    .limit(CONCURRENCY)

  // 2. 抢占到轮询时间的 running/submitted 任务
  const { data: polling } = await supabase
    .from('generation_jobs')
    .select('*')
    .in('status', ['submitted', 'running'])
    .or(`next_poll_at.lte.${now},lease_expires_at.lt.${now},lease_expires_at.is.null`)
    .order('next_poll_at', { ascending: true, nullsFirst: true })
    .limit(CONCURRENCY)

  const pool = [...(queued || []), ...(polling || [])]
  const results = []

  for (const job of pool) {
    const newStatus = job.status === 'queued' ? 'submitting' : 'running'
    const leaseExpires = new Date(Date.now() + 120000).toISOString()
    const { data } = await supabase
      .from('generation_jobs')
      .update({
        status: newStatus,
        lease_owner: 'vercel-cron',
        lease_expires_at: leaseExpires,
        attempt_count: job.status === 'queued' ? (job.attempt_count || 0) + 1 : job.attempt_count
      })
      .eq('id', job.id)
      .eq('status', job.status)
      .select('*')
      .single()
    if (data) results.push(data)
  }
  return results
}

async function processSubmitting(job) {
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
    const result = await submitProviderJob(request)
    await updateJob(job.id, {
      status: 'submitted',
      provider_job_id: result.remoteJobId,
      provider_raw_response: result.raw || {},
      next_poll_at: new Date(Date.now() + 10000).toISOString()
    })
    await logEvent(job.id, 'submitted', { remoteJobId: result.remoteJobId })
  } catch (err) {
    await handleFailure(job, 'SUBMIT_FAILED', err.message)
  }
}

async function processPolling(job) {
  await updateJob(job.id, {
    status: 'running',
    lease_expires_at: new Date(Date.now() + 120000).toISOString()
  })

  try {
    const remoteJobId = job.provider_job_id
    if (!remoteJobId) {
      await updateJob(job.id, { status: 'reconciling' })
      return
    }

    const result = await queryProviderJob({ provider: job.provider, remoteJobId })

    if (result.status === 'queued') {
      const nextPoll = Math.min(30000, 10000 * Math.pow(1.5, job.attempt_count || 0))
      await updateJob(job.id, {
        status: 'submitted',
        next_poll_at: new Date(Date.now() + nextPoll).toISOString()
      })
      return
    }

    if (result.status === 'running') {
      const nextPoll = Math.min(60000, 15000 * Math.pow(1.3, job.attempt_count || 0))
      await updateJob(job.id, {
        next_poll_at: new Date(Date.now() + nextPoll).toISOString()
      })
      return
    }

    if (result.status === 'succeeded') {
      await processArchive(job, result)
      return
    }

    if (result.status === 'failed') {
      await handleFailure(job, result.errorCode || 'PROVIDER_FAILED', result.errorMessage || 'Provider 失败')
      return
    }
  } catch (err) {
    const nextPoll = Math.min(30000, 10000 * Math.pow(2, job.attempt_count || 0))
    await updateJob(job.id, {
      next_poll_at: new Date(Date.now() + nextPoll).toISOString()
    })
  }
}

async function processArchive(job, queryResult) {
  // CAS 抢占 postprocessing
  const { data: claimed, error: claimErr } = await supabase
    .from('generation_jobs')
    .update({
      status: 'postprocessing',
      lease_expires_at: new Date(Date.now() + 120000).toISOString()
    })
    .eq('id', job.id)
    .in('status', ['submitted', 'running'])
    .select('id')
    .maybeSingle()

  if (claimErr || !claimed) return

  const outputUrls = queryResult.outputUrls || []
  let resultUrl = null

  if (outputUrls.length > 0) {
    try {
      const uploadResult = await uploadRemoteUrlToStorage(outputUrls[0], 'outputs')
      resultUrl = uploadResult.url
    } catch {
      resultUrl = outputUrls[0]
    }
  }

  await updateJob(job.id, {
    status: 'succeeded',
    result_url: resultUrl,
    actual_cost: queryResult.estimatedCost || null,
    cost_source: 'provider_bill',
    finished_at: new Date().toISOString()
  })

  try {
    const { v4: uuid } = await import('uuid')
    await supabase.from('videos').insert({
      id: uuid(),
      generation_job_id: job.id,
      file_url: resultUrl,
      resolution: job.resolution || '720p',
      compliance: 'pending'
    })
  } catch { /* ignore */ }

  await logEvent(job.id, 'succeeded', { resultUrl })
}

async function handleFailure(job, code, message) {
  const maxAttempts = job.max_attempts || 3
  const nextAttempt = (job.attempt_count || 0)

  if (nextAttempt < maxAttempts && ['SUBMIT_FAILED', 'NETWORK_TIMEOUT', 'RATE_LIMITED'].includes(code)) {
    await updateJob(job.id, {
      status: 'queued',
      provider_job_id: null,
      lease_owner: null,
      lease_expires_at: null,
      failure_code: code,
      failure_message: message,
      next_poll_at: new Date(Date.now() + 5000).toISOString()
    })
    await logEvent(job.id, 'retry', { code, attempt: nextAttempt })
  } else {
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

// ========== Vercel Serverless 入口 ==========
export default async function handler(req, res) {
  if (!supabase) {
    return res.status(500).json({ error: 'SUPABASE_SERVICE_ROLE_KEY 未配置' })
  }

  const jobs = await getLeasableJobs()
  if (jobs.length === 0) {
    return res.json({ ok: true, processed: 0, message: '无待处理任务' })
  }

  let processed = 0
  for (const job of jobs) {
    if (job.status === 'submitting' || (job.status === 'queued' && job.lease_owner === 'vercel-cron')) {
      await processSubmitting(job)
    } else if (['running', 'submitted'].includes(job.status)) {
      await processPolling(job)
    }
    processed++
  }

  res.json({ ok: true, processed, jobs: jobs.map(j => j.id.slice(0, 8)) })
}
