import 'dotenv/config'
import { callSeedance } from './seedance.js'
import { callKling } from './kling.js'
import { callJimeng } from './jimeng.js'

/**
 * AI 生成适配层：统一入口。
 * - 已配置密钥的 provider 走真实 API（火山方舟 / 可灵 / 即梦）
 * - 无密钥或 MOCK_MODE=true 时自动模拟，便于无密钥联调 UI
 * 任务类型：motion（动作迁移）/ music_drive（音乐驱动）/ dance（舞蹈模板直出）/ image（生图）/ outfit（换装）
 * 模型路由：kling-* → 可灵；其余 → 火山方舟（Seedance 视频 / Seedream 生图）
 */

export function getProvider(modelVersion = '') {
  if (String(modelVersion).startsWith('kling')) {
    return { name: 'kling', hasKey: () => !!process.env.KLING_API_KEY, run: callKling }
  }
  return {
    name: 'seedance',
    hasKey: () => !!(process.env.ARK_API_KEY || process.env.SEEDANCE_API_KEY),
    run: callSeedance
  }
}

export async function generate({ type, modelVersion, imageRef, videoRef, audioRef, prompt, duration, ratio, params = {} }) {
  const provider = getProvider(modelVersion)
  const mock = process.env.MOCK_MODE === 'true'

  if (mock || !provider.hasKey()) {
    return mockGenerate({ type, modelVersion, imageRef, videoRef, audioRef, prompt, duration, ratio, providerName: provider.name })
  }
  try {
    const result = await provider.run({ type, modelVersion, imageRef, videoRef, audioRef, prompt, duration, ratio, params })
    return { ...result, provider: provider.name, mock: false }
  } catch (err) {
    throw new Error(`[${provider.name}] ${err.message}`)
  }
}

/** 模拟生成：无密钥/开启 MOCK 时返回占位结果，保证全流程可演示 */
async function mockGenerate({ type, modelVersion, imageRef, videoRef, audioRef, prompt, duration, ratio, providerName }) {
  await sleep(1200)
  return {
    provider: providerName,
    mock: true,
    resultUrl: imageRef || videoRef || audioRef || null,
    meta: {
      type, modelVersion, prompt: prompt?.slice(0, 80), duration, ratio,
      note: '模拟结果（未配置密钥或 MOCK_MODE=true）。配置 .env 密钥后自动切换真实生成。'
    }
  }
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)) }
