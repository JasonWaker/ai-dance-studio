/**
 * 生成服务 —— 统一生成任务核心服务
 * - 创建 generation_jobs 记录（Supabase 或 SQLite）
 * - 202 立即返回 job_id
 * - Worker 后续异步处理
 *
 * 支持模式：
 *   i2v         图生视频（首帧图 + prompt）
 *   r2v_motion  参考视频-动作迁移（图 + 舞蹈视频）
 *   r2v_reference 参考视频-多模态（参考视频 + 可选图 + prompt）
 *   t2v         文生视频（自由 prompt）
 *   music_drive 音乐驱动（音频 + 图）
 *   dance_template 舞蹈模板直出
 *   image_gen   生图
 *   image_edit  图生图（换装等）
 */
import supabase, { isSupabaseAvailable } from './supabaseClient.js'
import { v4 as uuid } from 'uuid'
import { getCapabilities, validateAgainstCapabilities, listModelsForMode } from './capabilityService.js'
import db from '../db.js'

/** 模式 → 默认 provider 映射 */
const DEFAULT_PROVIDER = {
  i2v: 'volcengine',
  r2v_motion: 'kling',        // 动作迁移默认可灵
  r2v_reference: 'volcengine',
  t2v: 'volcengine',
  music_drive: 'volcengine',
  dance_template: 'volcengine',
  image_gen: 'volcengine',
  image_edit: 'volcengine',
  legacy: 'volcengine'
}

/** 模式 → 默认 model 映射（最省钱优先） */
const DEFAULT_MODEL = {
  i2v: 'doubao-seedance-2-0-mini-260615',
  r2v_motion: 'kling-v2-6',
  r2v_reference: 'doubao-seedance-2-5-260628',
  t2v: 'doubao-seedance-2-0-mini-260615',
  music_drive: 'doubao-seedance-2-5-260628',
  dance_template: 'doubao-seedance-2-0-mini-260615',
  image_gen: 'doubao-seedream-4-0-20260415',
  image_edit: 'doubao-seedream-4-0-20260415',
  legacy: 'doubao-seedance-2-5-260628'
}

export function buildDefaultRequest(input) {
  const mode = input.mode
  const provider = input.provider || DEFAULT_PROVIDER[mode]
  const model_id = input.model_id || DEFAULT_MODEL[mode]
  return { ...input, provider, model_id }
}

/** 创建生成任务（202 立即返回） */
export async function createGeneration(input) {
  const req = buildDefaultRequest(input)

  // 前置校验
  const issues = []

  // 1. 必须字段
  if (!req.mode) issues.push({ code: 'MISSING_FIELD', message: 'mode 必填' })
  if (!req.prompt && !['r2v_motion','dance_template'].includes(req.mode)) {
    // r2v_motion 可以没 prompt（参考视频本身就是提示），dance_template 也可以没
  }

  // 2. 模式→素材映射校验
  const hasImage = req.input_asset_ids?.length > 0 || req.image_ref
  const hasVideo = req.reference_video || req.input_asset_ids?.some(a => a.kind === 'video')
  const hasAudio = req.audio_ref

  if (req.mode === 'r2v_motion') {
    if (!hasImage) issues.push({ code: 'MISSING_REQUIRED', message: '动作迁移需要参考图片（人物/角色图）' })
    if (!hasVideo && !req.reference_video) issues.push({ code: 'MISSING_REQUIRED', message: '动作迁移需要参考舞蹈视频' })
  }
  if (req.mode === 'music_drive' && !hasAudio) issues.push({ code: 'MISSING_REQUIRED', message: '音乐驱动需要上传音乐文件' })
  if (req.mode === 'i2v' && !hasImage && !req.start_image) issues.push({ code: 'MISSING_REQUIRED', message: '图生视频需要首帧图片' })

  // 3. 模型能力校验
  if (req.provider && req.model_id) {
    const caps = await getCapabilities(req.provider, req.model_id)
    const capIssues = validateAgainstCapabilities(caps, {
      mode: req.mode,
      hasImage, hasVideo, hasAudio,
      duration: req.duration_seconds,
      aspectRatio: req.aspect_ratio
    })
    issues.push(...capIssues)
  }

  if (issues.length > 0) {
    return { ok: false, status: 400, error: issues }
  }

  // 4. 创建 job 记录
  const id = req.idempotency_key || uuid()
  const snapshot = {
    prompt: req.prompt,
    negative_prompt: req.negative_prompt,
    input_asset_ids: req.input_asset_ids || [],
    reference_video: req.reference_video || null,
    audio_ref: req.audio_ref || null,
    image_ref: req.image_ref || null,
    start_image: req.start_image || null,
    end_image: req.end_image || null,
    template_name: req.template_name || null,
    template_desc: req.template_desc || null,
    ...req.params
  }

  if (isSupabaseAvailable()) {
    const { data, error } = await supabase
      .from('generation_jobs')
      .insert({
        id,
        mode: req.mode,
        provider: req.provider,
        model_id: req.model_id,
        prompt: req.prompt,
        negative_prompt: req.negative_prompt || null,
        aspect_ratio: req.aspect_ratio || '9:16',
        duration_seconds: req.duration_seconds || null,
        resolution: req.resolution || null,
        input_asset_ids: (req.input_asset_ids || []).map(id => typeof id === 'string' ? id : id.id),
        input_snapshot: snapshot,
        status: 'queued',
        idempotency_key: req.idempotency_key || null
      })
      .select('*')
      .single()

    if (error) {
      console.error('[generationService] Supabase insert 失败:', error.message)
      // 降级 SQLite
      return createInSQLite(req, id, snapshot)
    }
    return { ok: true, status: 202, job: data }
  } else {
    return createInSQLite(req, id, snapshot)
  }
}

function createInSQLite(req, id, snapshot) {
  db.prepare(`INSERT INTO legacy_tasks (id, type, status, model_version, params) VALUES (?,?,?,?,?)`).run(
    id, req.mode, 'queued', req.model_id, JSON.stringify(snapshot)
  )
  return { ok: true, status: 202, job: { id, mode: req.mode, status: 'queued', model_id: req.model_id, ...snapshot }, sqlite_fallback: true }
}

export async function listGenerations({ mode, status, provider, limit = 50 }) {
  if (isSupabaseAvailable()) {
    let q = supabase.from('generation_jobs').select('*').order('created_at', { ascending: false }).limit(limit)
    if (mode) q = q.eq('mode', mode)
    if (status) q = q.eq('status', status)
    if (provider) q = q.eq('provider', provider)
    const { data, error } = await q
    if (!error && data) return data
  }
  // SQLite fallback
  return db.prepare('SELECT * FROM legacy_tasks ORDER BY created_at DESC LIMIT ?').all(limit).map(r => ({ ...r, mode: r.type, model_id: r.model_version, input_snapshot: r.params ? JSON.parse(r.params) : {} }))
}

export async function getGeneration(id) {
  if (isSupabaseAvailable()) {
    const { data, error } = await supabase.from('generation_jobs').select('*').eq('id', id).maybeSingle()
    if (!error && data) return data
  }
  // SQLite fallback
  return db.prepare('SELECT * FROM legacy_tasks WHERE id = ?').get(id)
}

export async function updateGenerationStatus(id, patch) {
  if (isSupabaseAvailable()) {
    const { data, error } = await supabase.from('generation_jobs').update(patch).eq('id', id).select('*').single()
    if (!error && data) return data
  }
  // SQLite fallback: 使用 legacy_tasks 表
  const fields = Object.keys(patch).map(k => `${k} = ?`).join(', ')
  const values = Object.values(patch)
  db.prepare(`UPDATE legacy_tasks SET ${fields} WHERE id = ?`).run(...values, id)
  return db.prepare('SELECT * FROM legacy_tasks WHERE id = ?').get(id)
}

export async function retryGeneration(id) {
  const job = await getGeneration(id)
  if (!job) return { ok: false, error: '任务不存在' }
  const snapshot = job.input_snapshot || {}
  const retryInput = {
    mode: job.mode,
    provider: job.provider,
    model_id: job.model_id,
    prompt: job.prompt,
    negative_prompt: job.negative_prompt,
    aspect_ratio: job.aspect_ratio,
    duration_seconds: job.duration_seconds,
    resolution: job.resolution,
    input_asset_ids: snapshot.input_asset_ids || [],
    image_ref: snapshot.image_ref,
    reference_video: snapshot.reference_video,
    audio_ref: snapshot.audio_ref,
    params: { ...snapshot, _source_job_id: id }
  }
  return createGeneration(retryInput)
}

export async function cancelGeneration(id) {
  return updateGenerationStatus(id, { status: 'cancel_requested' })
}
