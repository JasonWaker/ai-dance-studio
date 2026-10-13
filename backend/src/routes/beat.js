import { Router } from 'express'
import multer from 'multer'
import path from 'node:path'
import fs from 'node:fs'
import { v4 as uuid } from 'uuid'
import { detectBpm } from '../beat/index.js'

const router = Router()
const UPLOAD_DIR = path.resolve(process.cwd(), process.env.UPLOAD_DIR || '../uploads')
fs.mkdirSync(UPLOAD_DIR, { recursive: true })
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, UPLOAD_DIR),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname || '')
    cb(null, `beat-${Date.now()}-${uuid().slice(0, 6)}${ext}`)
  }
})
const upload = multer({ storage })

// 上传媒体并检测 BPM / 重音时间戳
router.post('/', upload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: '未收到文件' })
  try {
    const result = await detectBpm(req.file.path)
    res.json({ url: `/uploads/${req.file.filename}`, ...result })
  } catch (err) {
    res.status(422).json({ error: err.message, url: `/uploads/${req.file.filename}` })
  }
})

export default router
