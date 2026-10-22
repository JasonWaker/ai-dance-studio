/**
 * AI Provider 统一适配层 —— 升级版
 *
 * 接口设计（支持 Worker 异步模式）：
 *   submit(request) → { remoteJobId, provider, providerStatus, raw }
 *   getStatus(remoteJobId) → { status, progress?, outputUrls?, errorCode?, actualCost? }
 *
 * 原有 generate() 函数保留（向后兼容旧的同步轮询模式，仅供本地演示/MOCK 使用）
 */
import 'dotenv/config'
import axios from 'axios'
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { arkModel } from './seedance.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

// ------------------------------------------------------
// Seedance / Seedream 适配器（volcengine）
// ------------------------------------------------------
const ARK_BASE = () => process.env.ARK_BASE_URL || 'https://ark.cn-beijing.volces.com/api/v3'
const ARK_KEY = () => process.env.ARK_API_KEY || process.env.SEEDANCE_API_KEY
const arkAuth = () => ({ Authorization: `Bearer ${ARK_KEY()}`, 'Content-Type': 'application/json' })

export function seedanceHasKey() {
  return !!(process.env.ARK_API_KEY || process.env.SEEDANCE_API_KEY)
}

/** 提交 Seedance 视频生成任务（立即返回 task_id，不等待结果） */
export async function submitSeedanceVideo({ model_id, prompt, image_ref, video_ref, audio_ref, aspect_ratio, duration_seconds, params = {} }) {
  if (!seedanceHasKey()) throw new Error('未配置 ARK_API_KEY')

  const model = arkModel(model_id)
  const content = [{ type: 'text', text: prompt || '' }]
  if (image_ref) content.push({ type: 'image_url', image_url: { url: image_ref } })
  if (video_ref) content.push({ type: 'video_url', video_url: { url: video_ref } })
  if (audio_ref) content.push({ type: 'audio_url', audio_url: { url: audio_ref } })

  // Seedance 2.0 mini/fast 不支持视频参考 → 提前拦截
  if (video_ref && String(model_id).includes('mini')) {
    throw new Error('Seedance 2.0 mini 不支持视频参考，请改用 Seedance 2.5/2.0 或 Kling 动作迁移')
  }

  const is20 = String(model_id || '').includes('2.0')
  const body = {
    model,
    content,
    ratio: aspect_ratio || '9:16',
    duration: clampDuration(model_id, duration_seconds),
    generate_audio: true,
    watermark: false,
    ...params
  }
  // 对 video_ref 再校验一次 fast 模型
  if (video_ref && String(model_id).includes('fast')) {
    throw new Error('Seedance 2.0 fast 不支持视频参考')
  }

  const resp = await axios.post(`${ARK_BASE()}/contents/generations/tasks`, body, { headers: arkAuth(), timeout: 60000 })
  const taskId = resp.data?.id
  if (!taskId) throw new Error(`Seedance 任务创建失败: ${JSON.stringify(resp.data).slice(0, 300)}`)

  return {
    remoteJobId: taskId,
    provider: 'volcengine',
    providerStatus: 'queued',
    raw: resp.data
  }
}

/** 查询 Seedance 任务状态 */
export async function querySeedanceVideo(remoteJobId) {
  const resp = await axios.get(`${ARK_BASE()}/contents/generations/tasks/${remoteJobId}`, { headers: arkAuth(), timeout: 30000 })
  const s = resp.data?.status
  const videoUrl = resp.data?.content?.video_url

  let status = 'running'
  if (s === 'succeeded') status = 'succeeded'
  else if (s === 'failed') status = 'failed'
  else if (s === 'queued') status = 'queued'

  return {
    status,
    providerStatus: s,
    outputUrls: videoUrl ? [videoUrl] : [],
    errorCode: s === 'failed' ? (resp.data?.error?.code || 'SEEDANCE_FAILED') : null,
    errorMessage: s === 'failed' ? (resp.data?.error?.message || JSON.stringify(resp.data?.error || {})) : null,
    metadata: {
      duration: resp.data?.duration,
      resolution: resp.data?.resolution,
      ratio: resp.data?.ratio,
      taskId: remoteJobId
    }
  }
}

// ------------------------------------------------------
// Kling 动作迁移适配器
// ------------------------------------------------------
const KLING_BASE = () => process.env.KLING_BASE_URL || 'https://api-beijing.klingai.com'
const klingAuth = () => ({ Authorization: `Bearer ${process.env.KLING_API_KEY}`, 'Content-Type': 'application/json' })

export function klingHasKey() { return !!process.env.KLING_API_KEY }

/** 提交 Kling 动作迁移任务（立即返回 task_id） */
export async function submitKlingMotion({ image_ref, video_ref, prompt, model_id, params = {} }) {
  if (!klingHasKey()) throw new Error('未配置 KLING_API_KEY')
  if (!image_ref || !video_ref) throw new Error('动作迁移需要参考图片 + 参考视频')

  // 图片 → base64（可灵要求）
  const imageBase64 = await toKlingImage(image_ref)
  // 视频 → 公网 URL（可灵不支持 base64）
  const videoUrl = await toKlingVideoUrl(video_ref)

  const model_name = String(model_id || 'kling-v2-6').startsWith('kling') ? model_id : 'kling-v2-6'
  const body = {
    model_name,
    image_url: imageBase64,
    video_url: videoUrl,
    prompt: prompt || '复刻参考视频的舞蹈动作，动作连贯自然，与音乐重音对齐',
    keep_original_sound: 'yes',
    character_orientation: 'video',
    mode: params.mode || 'std',
    ...params
  }

  const resp = await axios.post(`${KLING_BASE()}/v1/videos/motion-control`, body, { headers: klingAuth(), timeout: 90000 })
  const taskId = resp.data?.data?.task_id
  if (!taskId) throw new Error(`Kling 任务创建失败: ${JSON.stringify(resp.data).slice(0, 300)}`)

  return {
    remoteJobId: taskId,
    provider: 'kling',
    providerStatus: resp.data?.data?.task_status || 'queued',
    raw: resp.data
  }
}

/** 查询 Kling 动作迁移任务状态 */
export async function queryKlingMotion(remoteJobId) {
  const resp = await axios.get(`${KLING_BASE()}/v1/videos/motion-control/${remoteJobId}`, { headers: klingAuth(), timeout: 30000 })
  const data = resp.data?.data || {}
  const s = data.task_status
  const videos = data.task_result?.videos || []
  const urls = videos.map(v => v.url).filter(Boolean)

  let status = 'running'
  if (s === 'succeed') status = 'succeeded'
  else if (s === 'failed') status = 'failed'
  else if (s === 'queued') status = 'queued'

  return {
    status,
    providerStatus: s,
    outputUrls: urls,
    errorCode: s === 'failed' ? 'KLING_FAILED' : null,
    errorMessage: s === 'failed' ? (data.task_status_msg || JSON.stringify(data).slice(0, 300)) : null,
    metadata: {
      duration: videos[0]?.duration,
      taskId: remoteJobId
    }
  }
}

// ------------------------------------------------------
// 工具函数
// ------------------------------------------------------
async function toKlingImage(ref) {
  if (!ref) return null
  const s = String(ref)
  if (s.startsWith('/uploads/')) {
    const buf = await fs.readFile(path.join(__dirname, '../../', process.env.UPLOAD_DIR || '../uploads', s.replace('/uploads/', '')))
    return buf.toString('base64')
  }
  if (s.startsWith('http://') || s.startsWith('https://')) {
    const resp = await axios.get(s, { responseType: 'arraybuffer', timeout: 30000 })
    return Buffer.from(resp.data).toString('base64')
  }
  return s
}

async function toKlingVideoUrl(ref) {
  if (!ref) return null
  const s = String(ref)
  if (s.startsWith('http://') || s.startsWith('https://')) return s
  if (s.startsWith('/uploads/')) {
    // 本地文件 → 中转上传
    const relay = process.env.KLING_RELAY_URL || 'https://ai-dance-studio.vercel.app'
    const file = path.join(__dirname, '../../', process.env.UPLOAD_DIR || '../uploads', s.replace('/uploads/', ''))
    const buf = await fs.readFile(file)
    const fd = new FormData()
    fd.append('file', new Blob([buf], { type: 'video/mp4' }), path.basename(file))
    const resp = await axios.post(`${relay}/api/media/upload`, fd, {
      headers: { 'x-upload-token': process.env.UPLOAD_TOKEN || '' },
      timeout: 60000
    })
    return relay + resp.data.url
  }
  return s
}

function clampDuration(model_id, duration) {
  const d = Math.max(4, Math.min(duration || 5, 30))
  const is20 = String(model_id || '').includes('2.0')
  return Math.min(d, is20 ? 15 : 30)
}

// ------------------------------------------------------
// 统一分发（Worker 调用入口）
// ------------------------------------------------------
export async function submitProviderJob({ provider, ...params }) {
  const mock = process.env.MOCK_MODE === 'true'
  if (mock) {
    return { remoteJobId: `mock-${Date.now()}`, provider, providerStatus: 'queued', mock: true }
  }
  if (provider === 'kling') return submitKlingMotion(params)
  return submitSeedanceVideo(params)
}

export async function queryProviderJob({ provider, remoteJobId }) {
  if (remoteJobId?.startsWith('mock-')) {
    // mock 模式：简单返回 succeeded
    await new Promise(r => setTimeout(r, 1500))
    return {
      status: 'succeeded',
      providerStatus: 'succeeded',
      outputUrls: ['/uploads/mock-generated-video.mp4'],
      mock: true
    }
  }
  if (provider === 'kling') return queryKlingMotion(remoteJobId)
  return querySeedanceVideo(remoteJobId)
}
