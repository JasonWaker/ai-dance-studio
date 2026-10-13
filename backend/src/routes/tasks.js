import { Router } from 'express'
import db from '../db.js'
import { createTask, listTasks, getTask, reviewTask } from '../engine/taskEngine.js'

const router = Router()

// 任务列表（含关联资产名称，便于工作台展示）
router.get('/', (req, res) => {
  const tasks = listTasks(Number(req.query.limit || 100))
  res.json(tasks)
})

// 创建任务：type=motion | music_drive | image | outfit
router.post('/', (req, res) => {
  const { type, model_id, outfit_id, scene_id, dance_source_id, music_id, model_version, params } = req.body
  if (!type) return res.status(400).json({ error: 'type 必填（motion / music_drive / image / outfit）' })
  const task = createTask({ type, model_id, outfit_id, scene_id, dance_source_id, music_id, model_version, params })
  res.status(201).json(task)
})

// 任务详情
router.get('/:id', (req, res) => {
  const t = getTask(req.params.id)
  if (!t) return res.status(404).json({ error: '任务不存在' })
  res.json(t)
})

// 质检动作：pass / redo
router.post('/:id/review', (req, res) => {
  const { action, note } = req.body
  if (!['pass', 'redo'].includes(action)) return res.status(400).json({ error: 'action 仅支持 pass / redo' })
  res.json(reviewTask(req.params.id, action, note))
})

export default router
