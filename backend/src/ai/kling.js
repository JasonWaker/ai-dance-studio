import 'dotenv/config'
import axios from 'axios'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

/**
 * 可灵 Kling 适配器：动作控制（动作迁移）——参考图 + 参考视频 → 换人不换动作。
 * 接口（官方文档）：
 *   POST https://api-beijing.klingai.com/v1/videos/motion-control
 *   GET  /v1/videos/motion-control/{task_id} → data.task_result.videos[0].url
 * 模型：kling-v2-6 / kling-v3；mode：std（性价比）/ pro（高品质）
 * 注意：character_orientation=video 时参考视频最长 30s；=image 时最长 10s
 * 素材格式：可灵要求 image_url / video_url 为纯 base64 字符串（不支持 URL），本地 /uploads 自动转换
 */
const __dirname = path.dirname(fileURLToPath(import.meta.url))
const UPLOAD_DIR = () => path.resolve(__dirname, '../../', process.env.UPLOAD_DIR || '../uploads')
const BASE = () => process.env.KLING_BASE_URL || 'https://api-beijing.klingai.com'
const auth = () => ({ Authorization: `Bearer ${process.env.KLING_API_KEY}`, 'Content-Type': 'application/json' })

/** 形象图转可灵要求的 base64：本地 /uploads 读文件、公网 URL 下载、已是 base64 则原样 */
async function toBase64(ref) {
  if (!ref) return null
  const s = String(ref)
  if (s.startsWith('/uploads/')) {
    const buf = await readFile(path.join(UPLOAD_DIR(), s.replace('/uploads/', '')))
    return buf.toString('base64')
  }
  if (s.startsWith('http://') || s.startsWith('https://')) {
    if (s.includes('localhost') || s.includes('127.0.0.1')) {
      const p = s.split('/uploads/')[1]
      if (p) {
        const buf = await readFile(path.join(UPLOAD_DIR(), p))
        return buf.toString('base64')
      }
    }
    const resp = await axios.get(s, { responseType: 'arraybuffer', timeout: 30000 })
    return Buffer.from(resp.data).toString('base64')
  }
  return s // 已是 base64
}

/**
 * 参考视频转公网 URL：可灵 video_url 只支持公网链接（不支持 base64）。
 * 本地 /uploads 文件 → 经线上 Vercel 中转（/api/assets/upload）拿公网 URL；已是公网 URL 直接用。
 */
async function toPublicVideoUrl(ref) {
  if (!ref) return null
  const s = String(ref)
  if (s.startsWith('http://') || s.startsWith('https://')) {
    if (s.includes('localhost') || s.includes('127.0.0.1')) {
      const p = s.split('/uploads/')[1]
      if (p) ref = `/uploads/${p}`
      else return s
    } else {
      return s // 已是公网 URL
    }
  }
  if (s.startsWith('/uploads/')) {
    const relay = process.env.KLING_RELAY_URL || 'https://ai-dance-studio.vercel.app'
    const file = path.join(UPLOAD_DIR(), s.replace('/uploads/', ''))
    const buf = await readFile(file)
    const fd = new FormData()
    fd.append('file', new Blob([buf], { type: 'video/mp4' }), path.basename(file))
    const resp = await axios.post(`${relay}/api/assets/upload`, fd, {
      headers: { 'x-upload-token': process.env.UPLOAD_TOKEN || '' },
      timeout: 60000
    })
    const p = resp.data?.url
    if (!p) throw new Error(`视频中转上传失败: ${JSON.stringify(resp.data).slice(0, 200)}`)
    return relay + p
  }
  throw new Error('可灵动作迁移的参考视频需要公网 URL 或本地 /uploads 文件，当前值不受支持')
}

export async function callKling({ type, modelVersion, imageRef, videoRef, audioRef, prompt, duration, ratio, params = {} }) {
  if (!process.env.KLING_API_KEY) throw new Error('未配置 KLING_API_KEY，无法真实生成。请在 backend/.env 配置。')
  if (!imageRef || !videoRef) throw new Error('可灵动作迁移需要"参考形象图 + 参考舞蹈视频"，请在任务中选择模特/形象图和舞源')

  const model_name = String(modelVersion || 'kling-v2-6').startsWith('kling') ? modelVersion : 'kling-v2-6'
  const body = {
    model_name,
    image_url: await toBase64(imageRef),
    video_url: await toPublicVideoUrl(videoRef),
    prompt: prompt || '复刻参考视频的舞蹈动作，动作连贯自然，与音乐重音对齐',
    keep_original_sound: 'yes',
    character_orientation: 'video', // 与参考视频朝向一致（动作迁移更准，≤30s）
    mode: params.mode || 'std',
    ...params
  }

  let resp
  try {
    resp = await axios.post(`${BASE()}/v1/videos/motion-control`, body, { headers: auth(), timeout: 90000 })
  } catch (e) {
    const detail = e.response?.data ? JSON.stringify(e.response.data).slice(0, 300) : e.message
    throw new Error(`可灵请求失败（status=${e.response?.status || '网络错误'}）: ${detail}`)
  }
  const taskId = resp.data?.data?.task_id
  if (!taskId) throw new Error(`任务创建失败（status=${resp.status}）: ${JSON.stringify(resp.data).slice(0, 300)}`)

  // 轮询（最长 5 分钟）
  const deadline = Date.now() + 300000
  while (Date.now() < deadline) {
    await sleep(8000)
    const q = await axios.get(`${BASE()}/v1/videos/motion-control/${taskId}`, { headers: auth(), timeout: 30000 })
    const status = q.data?.data?.task_status
    if (status === 'succeed') {
      const url = q.data?.data?.task_result?.videos?.[0]?.url
      if (!url) throw new Error(`任务成功但未取到视频: ${JSON.stringify(q.data).slice(0, 300)}`)
      return {
        resultUrl: url,
        meta: { provider: 'kling', model: model_name, taskId, duration: q.data?.data?.task_result?.videos?.[0]?.duration, mock: false }
      }
    }
    if (status === 'failed') {
      throw new Error(`生成失败: ${q.data?.data?.task_status_msg || JSON.stringify(q.data?.data).slice(0, 300)}`)
    }
  }
  throw new Error('生成超时（300s），可稍后在可灵生成记录中查询')
}

export async function pollKlingTask(taskId) {
  const q = await axios.get(`${BASE()}/v1/videos/motion-control/${taskId}`, { headers: auth(), timeout: 30000 })
  return { status: q.data?.data?.task_status, resultUrl: q.data?.data?.task_result?.videos?.[0]?.url || null }
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)) }
