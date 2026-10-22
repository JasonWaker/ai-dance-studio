import axios from 'axios'

const http = axios.create({ baseURL: '/api', timeout: 120000 })

// 通用封装
export const api = {
  get: (url, params) => http.get(url, { params }).then((r) => r.data),
  post: (url, data) => http.post(url, data).then((r) => r.data),
  put: (url, data) => http.put(url, data).then((r) => r.data),
  del: (url) => http.delete(url).then((r) => r.data),
  upload: (url, file, onProgress) => {
    const fd = new FormData()
    fd.append('file', file)
    return http.post(url, fd, { onUploadProgress: onProgress }).then((r) => r.data)
  },
  uploadWithBody: (url, file, extraBody, onProgress) => {
    const fd = new FormData()
    fd.append('file', file)
    if (extraBody) Object.entries(extraBody).forEach(([k, v]) => { if (v != null) fd.append(k, v) })
    return http.post(url, fd, { onUploadProgress: onProgress }).then((r) => r.data)
  }
}

// ========== 旧 API（保持兼容） ==========
export const AssetsApi = {
  list: (k) => api.get(`/assets/${k}`),
  create: (k, data) => api.post(`/assets/${k}`, data),
  update: (k, id, data) => api.put(`/assets/${k}/${id}`, data),
  remove: (k, id) => api.del(`/assets/${k}/${id}`),
  upload: (file) => api.upload('/assets/upload', file)
}
export const PromptsApi = {
  list: (params) => api.get('/prompts', params),
  categories: () => api.get('/prompts/categories'),
  random: (params) => api.get('/prompts/random', params),
  create: (data) => api.post('/prompts', data),
  use: (id) => api.post(`/prompts/${id}/use`),
  remove: (id) => api.del(`/prompts/${id}`)
}
export const TemplatesApi = {
  list: (type) => api.get('/templates', type ? { type } : undefined),
  types: () => api.get('/templates/types'),
  create: (data) => api.post('/templates', data),
  remove: (id) => api.del(`/templates/${id}`)
}
export const TopicsApi = { list: () => api.get('/topics') }
export const TasksApi = {
  list: () => api.get('/tasks'),
  create: (data) => api.post('/tasks', data),
  detail: (id) => api.get(`/tasks/${id}`),
  review: (id, action) => api.post(`/tasks/${id}/review`, { action })
}
export const VideosApi = {
  list: (status) => api.get('/videos', status ? { status } : undefined),
  complianceCheck: (data) => api.post('/videos/compliance-check', data),
  export: (videoIds, resolution) => api.post('/videos/export', { video_ids: videoIds, resolution }),
  exports: () => api.get('/videos/exports'),
  stats: (id, data) => api.put(`/videos/${id}/stats`, data)
}
export const BeatApi = { detect: (file) => api.upload('/beat', file) }
export const HealthApi = { get: () => api.get('/health') }

// ========== 新 API ==========
export const GenerationsApi = {
  create: (data) => api.post('/generations', data),
  list: (params) => api.get('/generations', params),
  detail: (id) => api.get(`/generations/${id}`),
  retry: (id) => api.post(`/generations/${id}/retry`),
  cancel: (id) => api.post(`/generations/${id}/cancel`),
  // 便捷：按状态轮询
  poll: async (id, onUpdate, intervalMs = 3000, timeoutMs = 120000) => {
    const start = Date.now()
    return new Promise((resolve, reject) => {
      const timer = setInterval(async () => {
        try {
          const job = await api.get(`/generations/${id}`)
          onUpdate?.(job)
          if (['succeeded', 'failed', 'cancelled'].includes(job.status)) {
            clearInterval(timer); resolve(job); return
          }
          if (Date.now() - start > timeoutMs) { clearInterval(timer); reject(new Error('超时')) }
        } catch (e) {
          console.warn('poll error', e.message)
        }
      }, intervalMs)
    })
  }
}

export const MediaApi = {
  upload: (file, kind, bucket) => api.uploadWithBody('/media/upload', file, {
    kind: kind || (file.type?.startsWith('image/') ? 'image' : file.type?.startsWith('video/') ? 'video' : file.type?.startsWith('audio/') ? 'audio' : null),
    bucket: bucket || undefined
  })
}

export const ModelsApi = {
  capabilities: (mode) => api.get('/models/capabilities', mode ? { mode } : undefined),
  detail: (provider, modelId) => api.get(`/models/capabilities/${provider}/${modelId}`)
}
