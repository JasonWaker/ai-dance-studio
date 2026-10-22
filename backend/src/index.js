import express from 'express'
import cors from 'cors'
import path from 'node:path'
import fs from 'node:fs'
import 'dotenv/config'
import assetsRouter from './routes/assets.js'
import promptsRouter from './routes/prompts.js'
import templatesRouter from './routes/templates.js'
import topicsRouter from './routes/topics.js'
import tasksRouter from './routes/tasks.js'
import videosRouter from './routes/videos.js'
import beatRouter from './routes/beat.js'
import generationsRouter from './routes/generations.js'
import mediaRouter from './routes/media.js'
import modelsRouter from './routes/models.js'
import workerTick from './worker-tick.js'
import { COMPLIANCE_CHECKLIST } from './compliance.js'

const app = express()
const PORT = process.env.PORT || 8787

app.use(cors())
app.use(express.json({ limit: '10mb' }))

// 静态文件：上传资源
const UPLOAD_DIR = path.resolve(process.cwd(), process.env.UPLOAD_DIR || '../uploads')
fs.mkdirSync(UPLOAD_DIR, { recursive: true })
app.use('/uploads', express.static(UPLOAD_DIR))

// 健康检查 + 系统状态（含各 provider 密钥配置情况）
app.get('/api/health', (req, res) => {
  res.json({
    ok: true,
    time: new Date().toISOString(),
    providers: {
      seedance: { configured: !!(process.env.ARK_API_KEY || process.env.SEEDANCE_API_KEY), model: process.env.SEEDANCE_MODEL || 'doubao-seedance-2-5-260628' },
      kling: { configured: !!process.env.KLING_API_KEY },
      jimeng: { configured: !!process.env.JIMENG_API_KEY && !!process.env.JIMENG_BASE_URL }
    },
    mockMode: process.env.MOCK_MODE === 'true',
    checklist: COMPLIANCE_CHECKLIST
  })
})

app.use('/api/assets', assetsRouter)
app.use('/api/prompts', promptsRouter)
app.use('/api/templates', templatesRouter)
app.use('/api/topics', topicsRouter)
app.use('/api/tasks', tasksRouter)
app.use('/api/videos', videosRouter)
app.use('/api/beat', beatRouter)
app.use('/api/generations', generationsRouter)
app.use('/api/media', mediaRouter)
app.use('/api/models', modelsRouter)

// Worker tick（Vercel Cron 定时触发）
app.get('/api/worker-tick', workerTick)

// 404
app.use((req, res) => res.status(404).json({ error: 'Not Found' }))

// 错误处理
app.use((err, req, res, next) => {
  console.error('[error]', err)
  res.status(500).json({ error: err.message || '服务器错误' })
})

// 本地启动；Vercel serverless 环境由 vercel/api/index.js 引入 app（vercel 会注入 VERCEL=1）
if (process.env.VERCEL !== '1') {
  app.listen(PORT, () => {
    console.log(`\n🎬 AI 卡点舞工作台后端已启动: http://localhost:${PORT}`)
    console.log(`   健康检查: http://localhost:${PORT}/api/health`)
    const p = process.env.MOCK_MODE === 'true'
    console.log(`   Provider: seedance=${!!(process.env.ARK_API_KEY || process.env.SEEDANCE_API_KEY)} kling=${!!process.env.KLING_API_KEY} jimeng=${!!process.env.JIMENG_API_KEY} mock=${p || '未开启(无密钥时自动模拟)'}`)
  })
}

export default app
