/**
 * 模型能力服务 —— 从 model_capabilities 表动态查询
 * 取代原有的硬编码 if/else 拦截
 */
import supabase, { isSupabaseAvailable } from './supabaseClient.js'
import db from '../db.js'

const CAP_CACHE = new Map()   // provider+model_id → capabilities
const CACHE_TTL = 5 * 60 * 1000  // 5 分钟

function cacheKey(provider, modelId) { return `${provider}:${modelId}` }

async function fetchFromSupabase(provider, modelId) {
  if (!isSupabaseAvailable()) return null
  const { data, error } = await supabase
    .from('model_capabilities')
    .select('*')
    .eq('provider', provider)
    .eq('model_id', modelId)
    .eq('enabled', true)
    .maybeSingle()
  if (error) { console.error('[capabilityService] Supabase 错误:', error.message); return null }
  return data
}

function fetchFromSQLite(provider, modelId) {
  // SQLite 兼容模式：用硬编码能力（仅用于本地演示）
  const MODEL_MAP = {
    'doubao-seedance-2-5-260628': {
      provider: 'volcengine', supported_modes: ['t2v','i2v','r2v_reference','music_drive','dance_template'],
      supported_inputs: { image: true, video: true, audio: true }, constraints: { min_duration_s: 4, max_duration_s: 30 }
    },
    'doubao-seedance-2-0-260128': {
      provider: 'volcengine', supported_modes: ['t2v','i2v','r2v_reference','dance_template'],
      supported_inputs: { image: true, video: true, audio: false }, constraints: { min_duration_s: 4, max_duration_s: 15 }
    },
    'doubao-seedance-2-0-fast-260128': {
      provider: 'volcengine', supported_modes: ['t2v','i2v','dance_template'],
      supported_inputs: { image: true, video: false, audio: false }, constraints: { min_duration_s: 4, max_duration_s: 15 }
    },
    'doubao-seedance-2-0-mini-260615': {
      provider: 'volcengine', supported_modes: ['t2v','i2v','dance_template'],
      supported_inputs: { image: true, video: false, audio: false }, constraints: { min_duration_s: 4, max_duration_s: 15 }
    },
    'doubao-seedream-4-0-20260415': {
      provider: 'volcengine', supported_modes: ['image_gen','image_edit'],
      supported_inputs: { image: true }, constraints: {}
    },
    'kling-v2-6': {
      provider: 'kling', supported_modes: ['r2v_motion'],
      supported_inputs: { image: true, video: true }, constraints: { max_duration_s: 30, max_ref_vid_s: 30 }
    }
  }
  return MODEL_MAP[modelId] || null
}

export async function getCapabilities(provider, modelId) {
  const ck = cacheKey(provider, modelId)
  const cached = CAP_CACHE.get(ck)
  if (cached && cached.expiresAt > Date.now()) return cached.data

  let caps = await fetchFromSupabase(provider, modelId)
  if (!caps) caps = fetchFromSQLite(provider, modelId)
  if (!caps) return null

  CAP_CACHE.set(ck, { data: caps, expiresAt: Date.now() + CACHE_TTL })
  return caps
}

export async function listAllCapabilities() {
  if (isSupabaseAvailable()) {
    const { data, error } = await supabase
      .from('model_capabilities')
      .select('*')
      .eq('enabled', true)
      .order('provider')
    if (!error && data) return data
  }
  // SQLite fallback
  return fetchAllFromSQLite()
}

function fetchAllFromSQLite() {
  const rows = []
  for (const [model_id, v] of Object.entries({
    'doubao-seedance-2-5-260628': { display_name: 'Seedance 2.5', provider: 'volcengine', supported_modes: ['t2v','i2v','r2v_reference','music_drive','dance_template'], constraints: { max_duration_s: 30 } },
    'doubao-seedance-2-0-260128': { display_name: 'Seedance 2.0', provider: 'volcengine', supported_modes: ['t2v','i2v','r2v_reference','dance_template'], constraints: { max_duration_s: 15 } },
    'doubao-seedance-2-0-mini-260615': { display_name: 'Seedance 2.0 Mini', provider: 'volcengine', supported_modes: ['t2v','i2v','dance_template'], constraints: { max_duration_s: 15 } },
    'kling-v2-6': { display_name: 'Kling v2-6', provider: 'kling', supported_modes: ['r2v_motion'], constraints: { max_duration_s: 30 } }
  })) {
    rows.push({ model_id, ...v, enabled: true })
  }
  return rows
}

export async function listModelsForMode(mode) {
  const all = await listAllCapabilities()
  return all.filter(m => m.supported_modes && m.supported_modes.includes(mode))
}

/** 校验请求参数是否符合模型能力 */
export function validateAgainstCapabilities(caps, { mode, hasImage, hasVideo, hasAudio, duration, aspectRatio }) {
  const issues = []
  if (!caps) {
    issues.push({ code: 'MODEL_NOT_FOUND', message: `未找到模型能力配置` })
    return issues
  }
  if (!caps.enabled) {
    issues.push({ code: 'MODEL_DISABLED', message: `模型 ${caps.model_id} 已被禁用` })
    return issues
  }
  if (!caps.supported_modes?.includes(mode)) {
    issues.push({ code: 'UNSUPPORTED_MODE', message: `模型 ${caps.display_name} 不支持模式 ${mode}，支持: ${caps.supported_modes?.join(', ') || '无'}` })
  }
  const inputs = caps.supported_inputs || {}
  if (hasImage && !inputs.image) issues.push({ code: 'UNSUPPORTED_CAPABILITY', message: `模型不支持图片输入` })
  if (hasVideo && !inputs.video) issues.push({ code: 'UNSUPPORTED_CAPABILITY', message: `模型不支持视频参考输入（Seedance 2.0 mini/fast 不支持 video_ref）` })
  if (hasAudio && !inputs.audio) issues.push({ code: 'UNSUPPORTED_CAPABILITY', message: `模型不支持音频条件` })
  if (duration) {
    const c = caps.constraints || {}
    if (c.min_duration_s && duration < c.min_duration_s) issues.push({ code: 'INVALID_DURATION', message: `时长不能小于 ${c.min_duration_s}s` })
    if (c.max_duration_s && duration > c.max_duration_s) issues.push({ code: 'INVALID_DURATION', message: `时长不能超过 ${c.max_duration_s}s` })
  }
  return issues
}
