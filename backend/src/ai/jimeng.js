import 'dotenv/config'
import axios from 'axios'

/**
 * 即梦（字节）适配器：生图 / 动作迁移。
 * 任务类型：image（生图）、motion（动作迁移：上传参考视频+开始图 -> 动作模仿）
 * 接口形态：按即梦开放平台文档配置 BASE_URL 与端点；默认 {JIMENG_BASE_URL}/api/v1/... 需按文档填写。
 */
export async function callJimeng({ type, modelVersion, imageRef, videoRef, audioRef, prompt, duration, ratio, params = {} }) {
  const base = process.env.JIMENG_BASE_URL || ''
  if (!base) {
    throw new Error('未配置 JIMENG_BASE_URL，即梦渠道暂不可用')
  }

  const endpoint = type === 'motion' ? '/api/v1/motion-transfer' : '/api/v1/text-to-image'
  const payload = {
    prompt,
    aspect_ratio: ratio || '9:16',
    ...params
  }
  if (type === 'motion') {
    payload.start_image = imageRef
    payload.reference_video = videoRef
  }

  const resp = await axios.post(`${base}${endpoint}`, payload, {
    headers: {
      Authorization: `Bearer ${process.env.JIMENG_API_KEY}`,
      'Content-Type': 'application/json'
    },
    timeout: 120000
  })

  const data = resp.data
  const resultUrl = data?.data?.video_url || data?.video_url || data?.data?.url || data?.url
  if (!resultUrl) {
    throw new Error(`接口返回异常（status=${resp.status}）: ${JSON.stringify(data).slice(0, 300)}`)
  }
  return { resultUrl, meta: { raw: data } }
}
