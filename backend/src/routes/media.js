/**
 * /api/media — 媒体文件上传（Supabase Storage 优先，本地降级）
 */
import { Router } from 'express'
import multer from 'multer'
import { uploadFile } from '../services/storageService.js'
import path from 'node:path'

const router = Router()
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 500 * 1024 * 1024 } })

/** 上传到指定 bucket */
router.post('/upload', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: '未收到文件' })
    const bucket = req.body.bucket || guessBucket(req.file.mimetype, req.body.kind)
    const result = await uploadFile(bucket, req.file.buffer, req.file.originalname, req.file.mimetype)
    res.json({
      ...result,
      originalName: req.file.originalname,
      size: req.file.size,
      mimeType: req.file.mimetype
    })
  } catch (err) {
    console.error('[media upload]', err)
    res.status(500).json({ error: '上传失败: ' + err.message })
  }
})

function guessBucket(mime, kind) {
  if (kind) {
    const map = { image: 'source-images', video: 'reference-videos', audio: 'music', output: 'outputs' }
    return map[kind] || 'source-images'
  }
  if (mime.startsWith('image/')) return 'source-images'
  if (mime.startsWith('video/')) return 'reference-videos'
  if (mime.startsWith('audio/')) return 'music'
  return 'source-images'
}

export default router
