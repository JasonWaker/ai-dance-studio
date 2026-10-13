import { Router } from 'express'
import { v4 as uuid } from 'uuid'
import db from '../db.js'

const router = Router()

// 提示词列表（可按分类/关键词筛选）
router.get('/', (req, res) => {
  const { category, keyword } = req.query
  let sql = 'SELECT * FROM prompt_library WHERE 1=1'
  const args = []
  if (category) { sql += ' AND category = ?'; args.push(category) }
  if (keyword) { sql += ' AND (title LIKE ? OR content LIKE ? OR tags LIKE ?)'; const k = `%${keyword}%`; args.push(k, k, k) }
  sql += ' ORDER BY hot_count DESC'
  res.json(db.prepare(sql).all(...args))
})

// 分类列表
router.get('/categories', (req, res) => {
  res.json(db.prepare('SELECT DISTINCT category FROM prompt_library').all().map((r) => r.category))
})

// 随机灵感：解决词穷——按分类随机取若干条
router.get('/random', (req, res) => {
  const { category, count = 3 } = req.query
  let rows
  if (category) {
    rows = db.prepare('SELECT * FROM prompt_library WHERE category = ? ORDER BY RANDOM() LIMIT ?').all(category, Number(count))
  } else {
    rows = db.prepare('SELECT * FROM prompt_library ORDER BY RANDOM() LIMIT ?').all(Number(count))
  }
  res.json(rows)
})

// 新增提示词
router.post('/', (req, res) => {
  const { category, title, content, tags } = req.body
  if (!category || !content) return res.status(400).json({ error: 'category 与 content 必填' })
  const id = uuid()
  db.prepare('INSERT INTO prompt_library (id, category, title, content, tags) VALUES (?,?,?,?,?)')
    .run(id, category, title || '', content, tags || '')
  res.json(db.prepare('SELECT * FROM prompt_library WHERE id = ?').get(id))
})

// 使用计数 +1（热门前置）
router.post('/:id/use', (req, res) => {
  db.prepare('UPDATE prompt_library SET hot_count = hot_count + 1 WHERE id = ?').run(req.params.id)
  res.json({ ok: true })
})

// 删除
router.delete('/:id', (req, res) => {
  db.prepare('DELETE FROM prompt_library WHERE id = ?').run(req.params.id)
  res.json({ ok: true })
})

export default router
