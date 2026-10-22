/**
 * /api/generations — 新生成任务路由
 * - POST 创建（202 立即返回 job_id）
 * - GET 列表/详情
 * - POST /retry /cancel /clone
 */
import { Router } from 'express'
import { createGeneration, listGenerations, getGeneration, retryGeneration, cancelGeneration } from '../services/generationService.js'

const router = Router()

// 创建生成任务
router.post('/', async (req, res) => {
  const result = await createGeneration(req.body)
  if (!result.ok) {
    return res.status(result.status || 400).json({ error: '参数校验失败', issues: result.error })
  }
  res.status(result.status || 202).json(result.job)
})

// 列表
router.get('/', async (req, res) => {
  const { mode, status, provider, limit } = req.query
  const list = await listGenerations({ mode, status, provider, limit: Number(limit || 50) })
  res.json(list)
})

// 详情
router.get('/:id', async (req, res) => {
  const job = await getGeneration(req.params.id)
  if (!job) return res.status(404).json({ error: '任务不存在' })
  res.json(job)
})

// 重试（基于原参数创建新任务）
router.post('/:id/retry', async (req, res) => {
  const r = await retryGeneration(req.params.id)
  if (!r.ok) return res.status(404).json({ error: r.error })
  res.status(202).json(r.job)
})

// 取消
router.post('/:id/cancel', async (req, res) => {
  const r = await cancelGeneration(req.params.id)
  res.json(r)
})

export default router
