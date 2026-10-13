// Vercel Serverless 入口：把 Express 后端整体挂载到 /api/*
// Vercel 会把 /api/xxx 请求路由到这里，Express 路由前缀 /api 与之匹配
import app from '../../backend/src/index.js'

export default app
