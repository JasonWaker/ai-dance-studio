/**
 * /api/models — 模型能力查询
 */
import { Router } from 'express'
import { listAllCapabilities, listModelsForMode, getCapabilities } from '../services/capabilityService.js'

const router = Router()

// 查询全部可用模型能力
router.get('/capabilities', async (req, res) => {
  const { mode, provider } = req.query
  let caps
  if (mode) {
    caps = await listModelsForMode(mode)
  } else {
    caps = await listAllCapabilities()
  }
  if (provider) caps = caps.filter(c => c.provider === provider)
  res.json(caps)
})

// 查询单模型详情
router.get('/capabilities/:provider/:model_id', async (req, res) => {
  const { provider, model_id } = req.params
  const caps = await getCapabilities(provider, model_id)
  if (!caps) return res.status(404).json({ error: '模型能力配置不存在' })
  res.json(caps)
})

export default router
