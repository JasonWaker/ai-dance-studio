/**
 * 存储服务 —— Supabase Storage 持久化上传/下载
 * - 如果没有 Supabase 配置，降级到本地 /uploads（仅本地开发）
 * - 自动确保 bucket 存在
 */
import supabase, { isSupabaseAvailable } from './supabaseClient.js'
import path from 'node:path'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import { v4 as uuid } from 'uuid'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const LOCAL_UPLOAD_DIR = path.resolve(__dirname, '../../', process.env.UPLOAD_DIR || '../uploads')
fs.mkdirSync(LOCAL_UPLOAD_DIR, { recursive: true })

const BUCKETS = ['source-images', 'reference-videos', 'music', 'outputs']
let bucketsEnsured = false

async function ensureBuckets() {
  if (!isSupabaseAvailable() || bucketsEnsured) return
  try {
    const { data: existing } = await supabase.storage.listBuckets()
    const existingIds = new Set(existing?.map(b => b.id) || [])
    for (const bucket of BUCKETS) {
      if (!existingIds.has(bucket)) {
        await supabase.storage.createBucket(bucket, { public: true })
        console.log(`[storage] 📦 自动创建 bucket: ${bucket}`)
      }
    }
    bucketsEnsured = true
  } catch (err) {
    console.error('[storage] ensureBuckets 失败:', err.message)
  }
}

export async function uploadFile(bucket, fileBuffer, fileName, mimeType) {
  await ensureBuckets()
  if (!isSupabaseAvailable()) {
    return localUpload(fileBuffer, fileName)
  }

  // 生成本地化的唯一文件名
  const ext = path.extname(fileName || '') || ''
  const storagePath = `${uuid()}${ext}`

  const { data, error } = await supabase.storage
    .from(bucket)
    .upload(storagePath, fileBuffer, {
      contentType: mimeType || 'application/octet-stream',
      upsert: false
    })

  if (error) {
    console.error('[storage] upload 失败:', error.message)
    // 降级到本地
    return localUpload(fileBuffer, fileName)
  }

  // 生成公开 URL
  const { data: urlData } = supabase.storage.from(bucket).getPublicUrl(storagePath)
  return {
    bucket,
    path: storagePath,
    url: urlData?.publicUrl,
    storage_provider: 'supabase',
    local_fallback: false
  }
}

export async function downloadFile(bucket, storagePath) {
  if (!isSupabaseAvailable()) return null
  const { data, error } = await supabase.storage.from(bucket).download(storagePath)
  if (error) {
    console.error('[storage] download 失败:', error.message)
    return null
  }
  return Buffer.from(await data.arrayBuffer())
}

export function localUpload(buffer, fileName) {
  const ext = path.extname(fileName || '') || ''
  const localName = `${Date.now()}-${uuid().slice(0, 8)}${ext}`
  const localPath = path.join(LOCAL_UPLOAD_DIR, localName)
  fs.writeFileSync(localPath, buffer)
  return {
    bucket: 'local',
    path: localName,
    url: `/uploads/${localName}`,
    storage_provider: 'local',
    local_fallback: true
  }
}

/** 从本地文件路径读取并上传到 Supabase Storage */
export async function uploadLocalFileToStorage(localPath, bucket, mimeType) {
  if (!fs.existsSync(localPath)) {
    console.warn(`[storage] 本地文件不存在: ${localPath}`)
    return null
  }
  const buf = fs.readFileSync(localPath)
  return uploadFile(bucket, buf, path.basename(localPath), mimeType)
}

/** 从远程 URL 下载并上传到 Supabase Storage（用于可灵视频中转替代方案） */
export async function uploadRemoteUrlToStorage(remoteUrl, bucket) {
  if (!isSupabaseAvailable()) return { url: remoteUrl, storage_provider: 'remote_url' }
  try {
    const resp = await fetch(remoteUrl)
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
    const buf = Buffer.from(await resp.arrayBuffer())
    const contentType = resp.headers.get('content-type') || 'video/mp4'
    const ext = contentType.includes('video/mp4') ? '.mp4' : contentType.includes('image') ? '.jpg' : '.bin'
    return uploadFile(bucket, buf, `remote-${uuid()}${ext}`, contentType)
  } catch (err) {
    console.warn('[storage] uploadRemoteUrlToStorage 失败，返回原 URL:', err.message)
    return { url: remoteUrl, storage_provider: 'remote_url', bucket }
  }
}
