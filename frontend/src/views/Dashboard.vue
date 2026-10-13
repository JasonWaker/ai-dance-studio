<template>
  <div>
    <el-row :gutter="16">
      <el-col :span="6"><el-card shadow="never"><div class="stat"><div class="num">{{ stats.tasks }}</div><div class="label">任务总数</div></div></el-card></el-col>
      <el-col :span="6"><el-card shadow="never"><div class="stat"><div class="num">{{ stats.videos }}</div><div class="label">成片数</div></div></el-card></el-col>
      <el-col :span="6"><el-card shadow="never"><div class="stat"><div class="num">{{ stats.pending }}</div><div class="label">待质检</div></div></el-card></el-col>
      <el-col :span="6"><el-card shadow="never"><div class="stat"><div class="num">{{ stats.passRate }}%</div><div class="label">质检通过率</div></div></el-card></el-col>
    </el-row>

    <el-row :gutter="16" style="margin-top:16px">
      <el-col :span="14">
        <el-card shadow="never" header="最近任务">
          <el-table :data="recentTasks" size="small" empty-text="暂无任务">
            <el-table-column prop="type" label="类型" width="110">
              <template #default="{ row }"><el-tag size="small">{{ typeLabel(row.type) }}</el-tag></template>
            </el-table-column>
            <el-table-column prop="model_version" label="模型" width="130" />
            <el-table-column label="状态" width="100">
              <template #default="{ row }"><el-tag :type="statusType(row.status)" size="small">{{ statusLabel(row.status) }}</el-tag></template>
            </el-table-column>
            <el-table-column prop="created_at" label="创建时间" />
          </el-table>
        </el-card>
      </el-col>
      <el-col :span="10">
        <el-card shadow="never" header="系统状态">
          <el-descriptions :column="1" size="small">
            <el-descriptions-item label="Seedance 模型">{{ health.providers?.seedance?.model || 'seedance-2.5' }}</el-descriptions-item>
            <el-descriptions-item label="Seedance 密钥"><el-tag size="small" :type="health.providers?.seedance?.configured ? 'success' : 'info'">{{ health.providers?.seedance?.configured ? '已配置' : '未配置' }}</el-tag></el-descriptions-item>
            <el-descriptions-item label="可灵密钥"><el-tag size="small" :type="health.providers?.kling?.configured ? 'success' : 'info'">{{ health.providers?.kling?.configured ? '已配置' : '未配置' }}</el-tag></el-descriptions-item>
            <el-descriptions-item label="即梦密钥"><el-tag size="small" :type="health.providers?.jimeng?.configured ? 'success' : 'info'">{{ health.providers?.jimeng?.configured ? '已配置' : '未配置' }}</el-tag></el-descriptions-item>
            <el-descriptions-item label="运行模式">{{ health.mockMode ? '模拟（无密钥时自动模拟生成）' : '真实 API' }}</el-descriptions-item>
          </el-descriptions>
          <div style="margin-top:12px">
            <el-button size="small" @click="goto('/tasks')">去任务台</el-button>
            <el-button size="small" type="primary" @click="goto('/prompts')">找灵感</el-button>
          </div>
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { TasksApi, VideosApi, HealthApi } from '@/api'

const router = useRouter()
const tasks = ref([])
const videos = ref([])
const health = ref({ providers: {} })

const stats = computed(() => ({
  tasks: tasks.value.length,
  videos: videos.value.length,
  pending: tasks.value.filter((t) => t.status === 'done').length,
  passRate: tasks.value.length
    ? Math.round((tasks.value.filter((t) => t.status === 'verified').length / tasks.value.length) * 100)
    : 0
}))
const recentTasks = computed(() => tasks.value.slice(0, 8))

function typeLabel(t) {
  return { motion: '动作迁移', music_drive: '音乐驱动', image: '生图', outfit: '换装' }[t] || t
}
function statusLabel(s) {
  return { queued: '排队中', running: '生成中', done: '待质检', verified: '已通过', rejected: '已重做', failed: '失败' }[s] || s
}
function statusType(s) {
  return { queued: 'info', running: 'warning', done: 'primary', verified: 'success', rejected: 'danger', failed: 'danger' }[s] || 'info'
}
function goto(p) { router.push(p) }

onMounted(async () => {
  try {
    tasks.value = await TasksApi.list()
    videos.value = await VideosApi.list()
    health.value = await HealthApi.get()
  } catch (e) { /* ignore */ }
})
</script>

<style scoped>
.stat { text-align: center; padding: 8px 0; }
.stat .num { font-size: 28px; font-weight: 700; color: #1f2430; }
.stat .label { color: #6b7280; font-size: 13px; margin-top: 4px; }
</style>
