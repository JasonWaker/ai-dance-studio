import { createRouter, createWebHashHistory } from 'vue-router'

const routes = [
  { path: '/', redirect: '/dashboard' },
  { path: '/generate', name: 'generate', component: () => import('@/views/Generate.vue'), meta: { title: 'AI 视频生成' } },
  { path: '/jobs', name: 'jobs', component: () => import('@/views/Jobs.vue'), meta: { title: '任务中心' } },
  { path: '/models', name: 'models', component: () => import('@/views/Models.vue'), meta: { title: '模型中心' } },
  { path: '/dashboard', name: 'dashboard', component: () => import('@/views/Dashboard.vue'), meta: { title: '数据看板' } },
  { path: '/topics', name: 'topics', component: () => import('@/views/Topics.vue'), meta: { title: '选题中心' } },
  { path: '/assets', name: 'assets', component: () => import('@/views/Assets.vue'), meta: { title: '资产库' } },
  { path: '/tasks', name: 'tasks', component: () => import('@/views/Tasks.vue'), meta: { title: '旧任务台' } },
  { path: '/review', name: 'review', component: () => import('@/views/Review.vue'), meta: { title: '质检台' } },
  { path: '/prompts', name: 'prompts', component: () => import('@/views/Prompts.vue'), meta: { title: '提示词中心' } },
  { path: '/videos', name: 'videos', component: () => import('@/views/Videos.vue'), meta: { title: '成品库' } },
  { path: '/publish', name: 'publish', component: () => import('@/views/Publish.vue'), meta: { title: '发布助手' } }
]

export default createRouter({
  history: createWebHashHistory(),
  routes
})
