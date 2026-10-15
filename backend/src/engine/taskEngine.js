import db from '../db.js'
import { v4 as uuid } from 'uuid'
import { generate } from '../ai/providers.js'

/**
 * 任务引擎：内存队列 + 状态机（queued -> running -> done | failed -> verified | rejected）
 * MVP 采用顺序队列；V1 可替换为并发/持久化队列。
 */
const queue = []
let processing = false

export function createTask(input) {
  const id = uuid()
  db.prepare(`INSERT INTO task (id, type, status, model_id, outfit_id, scene_id, dance_source_id, music_id, model_version, params)
    VALUES (?,?,?,?,?,?,?,?,?,?)`).run(
    id, input.type, 'queued',
    input.model_id || null, input.outfit_id || null, input.scene_id || null,
    input.dance_source_id || null, input.music_id || null,
    input.model_version || null, JSON.stringify(input.params || {})
  )
  queue.push(id)
  pump()
  return getTask(id)
}

export function getTask(id) {
  return db.prepare('SELECT * FROM task WHERE id = ?').get(id)
}

export function listTasks(limit = 100) {
  return db.prepare('SELECT * FROM task ORDER BY created_at DESC LIMIT ?').all(limit)
}

export function updateTaskStatus(id, patch) {
  const fields = Object.keys(patch).map((k) => `${k} = ?`).join(', ')
  const values = Object.values(patch)
  db.prepare(`UPDATE task SET ${fields}, updated_at = datetime('now') WHERE id = ?`).run(...values, id)
}

async function pump() {
  if (processing) return
  processing = true
  while (queue.length) {
    const id = queue.shift()
    const task = getTask(id)
    if (!task) continue
    try {
      await runTask(task)
    } catch (err) {
      updateTaskStatus(id, { status: 'failed', error: err.message })
    }
  }
  processing = false
}

async function runTask(task) {
  updateTaskStatus(task.id, { status: 'running' })

  const params = JSON.parse(task.params || '{}')
  const assets = resolveAssets(task)
  // 动作迁移前置校验：缺形象图/舞蹈视频时给出精准提示（替代可灵笼统报错）
  if (task.type === 'motion') {
    if (!assets.image) {
      throw new Error(`动作迁移需要模特形象图：模特「${assets.model?.name || '未选择'}」未上传形象图，请先在资产库为模特上传形象图`)
    }
    if (!assets.video) {
      throw new Error(`动作迁移需要舞蹈视频：舞源「${assets.dance?.name || '未选择'}」未上传舞蹈视频，请先在资产库为该舞源上传视频`)
    }
  }
  // 模板参数透传（如模板名/动作要点），避免默认 prompt 覆盖用户自定义
  const finalPrompt = params.prompt || buildDefaultPrompt(task, assets)
  const result = await generate({
    type: task.type,
    modelVersion: task.model_version,
    imageRef: assets.image,
    videoRef: assets.video,
    audioRef: assets.audio,
    prompt: finalPrompt,
    duration: params.duration,
    ratio: params.ratio || '9:16',
    params: { ...params, prompt: finalPrompt }
  })

  // 成功：写入 task 结果并生成 video 成品记录（等待质检）
  updateTaskStatus(task.id, {
    status: result.mock ? 'done' : 'done',
    result_url: result.resultUrl,
    credit_cost: params.creditCost || 0
  })
  const videoId = uuid()
  db.prepare(`INSERT INTO video (id, task_id, file_url, resolution, bpm, compliance)
    VALUES (?,?,?,?,?,?)`).run(
    videoId, task.id, result.resultUrl || null, params.resolution || '720p',
    params.bpm || null, 'pending'
  )
  return result
}

function resolveAssets(task) {
  const get = (table, id) => (id ? db.prepare(`SELECT * FROM ${table} WHERE id = ?`).get(id) : null)
  const model = get('model', task.model_id)
  const outfit = get('outfit', task.outfit_id)
  const scene = get('scene', task.scene_id)
  const dance = get('dance_source', task.dance_source_id)
  const music = get('music', task.music_id)
  return {
    image: model?.ref_image || outfit?.image || null,
    video: dance?.video_url || null,
    audio: music?.audio_url || null,
    model, outfit, scene, dance, music
  }
}

function buildDefaultPrompt(task, assets) {
  const base = `一位20岁左右的长发亚洲女孩，身穿${assets.outfit?.name || '默认造型'}，站在${assets.scene?.name || '室内'}场景中`
  if (task.type === 'motion') return `${base}，复刻参考视频的舞蹈动作，动作连贯、与音乐重音对齐，9:16竖构图`
  if (task.type === 'music_drive') return `${base}，跟随音乐节奏自动编排舞蹈，动作幅度大、K-pop 风格，重音处卡点，9:16竖构图`
  if (task.type === 'dance') {
    // 热门舞蹈模板直出（最省钱）：舞蹈名当 prompt，Seedance 训练数据里有全网爆火舞蹈
    const name = task.params?.template_name || '热门卡点舞'
    const desc = task.params?.template_desc || '动作幅度大、律动感强、每个重音一个爆点'
    return `${base}，跳【${name}】舞，动作要点：${desc}，动作与音乐重音精准对齐，动作连贯流畅，9:16竖构图`
  }
  if (task.type === 'image') return `${base}，全身，舞蹈准备姿势，真实摄影质感，自然光，高清8k，9:16竖构图。负面：畸形、崩坏、多余手指、低质量、模糊`
  return base
}

/** 质检：通过 / 重做 */
export function reviewTask(id, action, note = '') {
  updateTaskStatus(id, { status: action === 'pass' ? 'verified' : 'rejected' })
  const video = db.prepare('SELECT * FROM video WHERE task_id = ?').get(id)
  if (video) {
    db.prepare(`UPDATE video SET compliance = ? WHERE id = ?`).run(action === 'pass' ? 'passed' : 'rejected', video.id)
  }
  return getTask(id)
}
