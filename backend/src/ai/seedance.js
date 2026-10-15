import 'dotenv/config'
import axios from 'axios'

/**
 * 火山方舟适配器（Seedance 视频 + Seedream 生图）。
 * - 视频：POST /contents/generations/tasks → 轮询 GET /contents/generations/tasks/{id} → content.video_url
 * - 生图：POST /images/generations（支持图生图保持一致性）
 * 官方模型 ID 映射（可在 .env 覆盖）：
 *   Seedance 2.5 = doubao-seedance-2-5-260628（音频条件驱动，4-30s）
 *   Seedance 2.0 = doubao-seedance-2-0-260128（视频参考，4-15s）
 *   Seedance 2.0 fast = doubao-seedance-2-0-fast-260128（低成本，4-15s）
 *   Seedance 2.0 mini = doubao-seedance-2-0-mini-260615（最省钱，4-15s）
 *   Seedream 4.0 = doubao-seedream-4-0-20260415（生图）
 */

const MODEL_MAP = {
  'seedance-2.5': 'doubao-seedance-2-5-260628',
  'seedance-2.0': 'doubao-seedance-2-0-260128',
  'seedance-2.0-fast': 'doubao-seedance-2-0-fast-260128',
  'seedance-2.0-mini': 'doubao-seedance-2-0-mini-260615',
  'seedream-4.0': 'doubao-seedream-4-0-20260415'
}

const BASE = () => process.env.ARK_BASE_URL || 'https://ark.cn-beijing.volces.com/api/v3'
const KEY = () => process.env.ARK_API_KEY || process.env.SEEDANCE_API_KEY
const auth = () => ({ Authorization: `Bearer ${KEY()}`, 'Content-Type': 'application/json' })

export function arkModel(version) {
  return MODEL_MAP[version] || version || process.env.SEEDANCE_MODEL || MODEL_MAP['seedance-2.5']
}

export async function callSeedance({ type, modelVersion, imageRef, videoRef, audioRef, prompt, duration, ratio, params = {} }) {
  if (!KEY()) throw new Error('未配置 ARK_API_KEY（火山方舟），无法真实生成。请在 backend/.env 配置。')
  if (type === 'image' || type === 'outfit' || params.onlyImage) return generateImage({ imageRef, prompt, ratio, params })
  return generateVideo({ modelVersion, imageRef, videoRef, audioRef, prompt, duration, ratio, params })
}

/** Seedream 生图：文生图 / 图生图（定妆图一致性） */
async function generateImage({ imageRef, prompt, ratio, params }) {
  const model = process.env.SEEDREAM_MODEL || MODEL_MAP['seedream-4.0']
  const body = {
    model,
    prompt,
    size: ratioToSize(ratio || '9:16'),
    response_format: 'url',
    watermark: false,
    ...params
  }
  if (imageRef) body.image = imageRef // 图生图：以参考图为基准，保持长相/服装/场景一致
  const resp = await axios.post(`${BASE()}/images/generations`, body, { headers: auth(), timeout: 120000 })
  const url = resp.data?.data?.[0]?.url
  if (!url) throw new Error(`生图失败（status=${resp.status}）: ${JSON.stringify(resp.data).slice(0, 300)}`)
  return { resultUrl: url, meta: { provider: 'volc-ark', model, mock: false } }
}

/** Seedance 视频生成：全模态参考（文本/图片/视频/音频）+ 异步轮询 */
async function generateVideo({ modelVersion, imageRef, videoRef, audioRef, prompt, duration, ratio, params }) {
  if (videoRef && String(modelVersion).includes('mini')) {
    throw new Error('Seedance 2.0 mini 不支持视频参考（动作迁移）。请改用 Seedance 2.5 / 2.0 或可灵 Kling 动作迁移。')
  }
  const model = arkModel(modelVersion)
  const content = [{ type: 'text', text: prompt }]
  if (imageRef) content.push({ type: 'image_url', image_url: { url: imageRef } })
  if (videoRef) content.push({ type: 'video_url', video_url: { url: videoRef } })
  if (audioRef) content.push({ type: 'audio_url', audio_url: { url: audioRef } })

  const body = {
    model,
    content,
    ratio: ratio || '9:16',
    duration: clampDuration(modelVersion, duration),
    generate_audio: true,
    watermark: false,
    ...params
  }
  let created
  try {
    created = await axios.post(`${BASE()}/contents/generations/tasks`, body, { headers: auth(), timeout: 60000 })
  } catch (e) {
    const detail = e.response?.data ? JSON.stringify(e.response.data).slice(0, 300) : e.message
    throw new Error(`任务创建失败（status=${e.response?.status || '网络错误'}）: ${detail}`)
  }
  const taskId = created.data?.id
  if (!taskId) throw new Error(`任务创建失败（status=${created.status}）: ${JSON.stringify(created.data).slice(0, 300)}`)

  // 轮询任务状态（最长 4 分钟）
  const deadline = Date.now() + 240000
  while (Date.now() < deadline) {
    await sleep(10000)
    const q = await axios.get(`${BASE()}/contents/generations/tasks/${taskId}`, { headers: auth(), timeout: 30000 })
    const status = q.data?.status
    if (status === 'succeeded') {
      const url = q.data?.content?.video_url
      if (!url) throw new Error(`任务成功但未取到视频地址: ${JSON.stringify(q.data).slice(0, 300)}`)
      return {
        resultUrl: url,
        meta: { provider: 'volc-ark', model, taskId, duration: q.data?.duration, resolution: q.data?.resolution, ratio: q.data?.ratio, mock: false }
      }
    }
    if (status === 'failed') {
      throw new Error(`生成失败: ${q.data?.error?.message || JSON.stringify(q.data?.error || q.data).slice(0, 300)}`)
    }
  }
  throw new Error('生成超时（240s），可稍后在生成记录中查询')
}

/** Seedance 2.0 系列最长 15s，2.5 最长 30s */
function clampDuration(modelVersion, duration) {
  const d = Math.max(4, Math.min(duration || 5, 30))
  const is20 = String(modelVersion || '').includes('2.0')
  return Math.min(d, is20 ? 15 : 30)
}

function ratioToSize(ratio) {
  return { '1:1': '1024x1024', '16:9': '1536x864', '9:16': '864x1536', '3:4': '1024x1365', '4:3': '1365x1024' }[ratio] || '864x1536'
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)) }
