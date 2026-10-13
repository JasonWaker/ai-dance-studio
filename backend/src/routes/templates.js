import { Router } from 'express'
import { v4 as uuid } from 'uuid'
import db from '../db.js'

const router = Router()

router.get('/', (req, res) => {
  const { type } = req.query
  if (type) return res.json(db.prepare('SELECT * FROM template WHERE type = ? AND enabled = 1').all(type))
  res.json(db.prepare('SELECT * FROM template WHERE enabled = 1 ORDER BY type').all())
})

router.get('/types', (req, res) => {
  res.json(db.prepare('SELECT DISTINCT type FROM template').all().map((r) => r.type))
})

// 新增模板（前端入库：舞蹈模板直出可随时新增，所有人共享）
router.post('/', (req, res) => {
  const { type, name, params, prompt } = req.body
  if (!type || !name) return res.status(400).json({ error: 'type 与 name 必填' })
  const id = uuid()
  db.prepare('INSERT INTO template (id, type, name, params, prompt) VALUES (?,?,?,?,?)')
    .run(id, type, name, params ? JSON.stringify(params) : null, prompt || '')
  res.json(db.prepare('SELECT * FROM template WHERE id = ?').get(id))
})

// 删除模板
router.delete('/:id', (req, res) => {
  db.prepare('DELETE FROM template WHERE id = ?').run(req.params.id)
  res.json({ ok: true })
})

export default router
