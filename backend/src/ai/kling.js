import 'dotenv/config'
import axios from 'axios'

/**
 * 可灵 Kling 适配器：动作控制（动作迁移）——参考图 + 参考视频 → 换人不换动作。
 * 接口（官方文档）：
 *   POST https://api-beijing.klingai.com/v1/videos/motion-control
 *   GET  /v1/videos/motion-control/{task_id} → data.task_result.videos[0].url
 * 模型：kling-v2-6 / kling-v3；mode：std（性价比）/ pro（高品质）
 * 注意：character_orientation=video 时参考视频最长 30s；=image 时最长 10s
 */
const BASE = () => process.env.KLING_BASE_URL || 'https://api-beijing.klingai.com'
const auth = () => ({ Authorization: `Bearer ${process.env.KLING_API_KEY}`, 'Content-Type': 'application/json' })

export async function callKling({ type, modelVersion, imageRef, videoRef, audioRef, prompt, duration, ratio, params = {} }) {
  if (!process.env.KLING_API_KEY) throw new Error('未配置 KLING_API_KEY，无法真实生成。请在 backend/.env 配置。')
  if (!imageRef || !videoRef) throw new Error('可灵动作迁移需要"参考形象图 + 参考舞蹈视频"，请在任务中选择模特/形象图和舞源')

  const model_name = String(modelVersion || 'kling-v2-6').startsWith('kling') ? modelVersion : 'kling-v2-6'
  const body = {
    model_name,
    image_url: imageRef,
    video_url: videoRef,
    prompt: prompt || '复刻参考视频的舞蹈动作，动作连贯自然，与音乐重音对齐',
    keep_original_sound: 'yes',
    character_orientation: 'video', // 与参考视频朝向一致（动作迁移更准，≤30s）
    mode: params.mode || 'std',
    ...params
  }

  const resp = await axios.post(`${BASE()}/v1/videos/motion-control`, body, { headers: auth(), timeout: 60000 })
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
