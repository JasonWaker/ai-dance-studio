/**
 * Vercel Serverless 入口（import backend app）
 * 注意：此文件由 vercel.json 的 services 模式自动加载，作为 /api/* 的入口
 */
import app from '../backend/src/index.js'

export default app
