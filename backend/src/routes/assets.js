import { Router } from 'express'
import multer from 'multer'
import path from 'node:path'
import fs from 'node:fs'
import { v4 as uuid } from 'uuid'
import db from '../db.js'

const router = Router()

// ---------- 上传 ----------
const UPLOAD_DIR = path.resolve(process.cwd(), process.env.UPLOAD_DIR || '../uploads')
fs.mkdirSync(UPLOAD_DIR, { recursive: true })
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, UPLOAD_DIR),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname || '')
    cb(null, `${Date.now()}-${uuid().slice(0, 8)}${ext}`)
  }
})
const upload = multer({ storage })

router.post('/upload', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: '未收到文件' })
  res.json({ url: `/uploads/${req.file.filename}`, originalName: req.file.originalname })
})

// ---------- 通用 CRUD 帮助函数 ----------
const tables = {
  models: { table: 'model', fields: ['name', 'face_seed', 'style_prompt', 'ref_image', 'remark', 'status'] },
  outfits: { table: 'outfit', fields: ['name', 'image', 'style_tag', 'remark', 'status'] },
  scenes: { table: 'scene', fields: ['name', 'type', 'ref_image', 'description', 'remark', 'status'] },
  danceSources: { table: 'dance_source', fields: ['name', 'video_url', 'duration_s', 'bpm', 'genre', 'source', 'hot_score', 'music_id', 'remark', 'status'] },
  music: { table: 'music', fields: ['name', 'audio_url', 'bpm', 'style', 'copyright', 'remark'] }
}

for (const [key, conf] of Object.entries(tables)) {
  // 列表
  router.get(`/${key}`, (req, res) => {
    const rows = db.prepare(`SELECT * FROM ${conf.table} ORDER BY created_at DESC`).all()
    res.json(rows)
  })
  // 新增
  router.post(`/${key}`, (req, res) => {
    if (!req.body.name || !String(req.body.name).trim()) {
      return res.status(400).json({ error: '名称不能为空' })
    }
    const id = uuid()
    const cols = ['id', ...conf.fields]
    const vals = [id, ...conf.fields.map((f) => req.body[f] ?? null)]
    try {
      db.prepare(`INSERT INTO ${conf.table} (${cols.join(',')}) VALUES (${cols.map(() => '?').join(',')})`).run(...vals)
    } catch (e) {
      return res.status(400).json({ error: '保存失败：' + (e.message || '数据错误') })
    }
    res.json(db.prepare(`SELECT * FROM ${conf.table} WHERE id = ?`).get(id))
  })
  // 更新
  router.put(`/${key}/:id`, (req, res) => {
    const sets = conf.fields.filter((f) => req.body[f] !== undefined).map((f) => `${f} = ?`)
    if (!sets.length) return res.status(400).json({ error: '无更新字段' })
    const vals = conf.fields.filter((f) => req.body[f] !== undefined).map((f) => req.body[f])
    db.prepare(`UPDATE ${conf.table} SET ${sets.join(',')} WHERE id = ?`).run(...vals, req.params.id)
    res.json(db.prepare(`SELECT * FROM ${conf.table} WHERE id = ?`).get(req.params.id))
  })
  // 删除
  router.delete(`/${key}/:id`, (req, res) => {
    db.prepare(`DELETE FROM ${conf.table} WHERE id = ?`).run(req.params.id)
    res.json({ ok: true })
  })
}

export default router
