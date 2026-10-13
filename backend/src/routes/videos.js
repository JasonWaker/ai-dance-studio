import { Router } from 'express'
import { v4 as uuid } from 'uuid'
import db from '../db.js'
import { checkCompliance } from '../compliance.js'

const router = Router()

// 成品列表
router.get('/', (req, res) => {
  const { status } = req.query
  let sql = 'SELECT * FROM video ORDER BY created_at DESC'
  const args = []
  if (status) { sql = 'SELECT * FROM video WHERE compliance = ? ORDER BY created_at DESC'; args.push(status) }
  res.json(db.prepare(sql).all(...args))
})

// 合规预检：对发布文案/标题跑检查器
router.post('/compliance-check', (req, res) => {
  const { title, caption, aiLabeled, aiTagChecked, hasRealFace } = req.body
  res.json(checkCompliance({ title, caption, aiLabeled, aiTagChecked, hasRealFace }))
})

// 导出（生成 export_record，MVP 返回下载链接）
router.post('/export', (req, res) => {
  const { video_ids, resolution = '720p' } = req.body
  if (!Array.isArray(video_ids) || !video_ids.length) return res.status(400).json({ error: 'video_ids 必填' })
  const id = uuid()
  db.prepare('INSERT INTO export_record (id, video_ids, resolution, status) VALUES (?,?,?,?)')
    .run(id, JSON.stringify(video_ids), resolution, 'ready')
  const files = db.prepare(`SELECT file_url FROM video WHERE id IN (${video_ids.map(() => '?').join(',')})`).all(...video_ids)
  res.json({ id, files: files.map((f) => f.file_url).filter(Boolean) })
})

// 导出记录列表
router.get('/exports', (req, res) => {
  res.json(db.prepare('SELECT * FROM export_record ORDER BY created_at DESC').all())
})

// 平台数据回填
router.put('/:id/stats', (req, res) => {
  const { play_count, like_count } = req.body
  db.prepare('UPDATE video SET play_count = ?, like_count = ? WHERE id = ?')
    .run(play_count || 0, like_count || 0, req.params.id)
  res.json({ ok: true })
})

export default router
