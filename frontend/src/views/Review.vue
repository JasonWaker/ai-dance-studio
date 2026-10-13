<template>
  <div>
    <el-card shadow="never">
      <template #header>
        <div class="head">
          <span class="card-title">质检台</span>
          <el-button size="small" :icon="Refresh" circle @click="load" />
        </div>
      </template>

      <el-tabs v-model="tab" @tab-change="load">
        <el-tab-pane label="待质检" name="done" />
        <el-tab-pane label="全部" name="all" />
      </el-tabs>

      <el-table :data="list" size="small" empty-text="暂无任务">
        <el-table-column prop="type" label="类型" width="110">
          <template #default="{ row }"><el-tag size="small">{{ typeLabel(row.type) }}</el-tag></template>
        </el-table-column>
        <el-table-column label="状态" width="100">
          <template #default="{ row }"><el-tag :type="statusType(row.status)" size="small">{{ statusLabel(row.status) }}</el-tag></template>
        </el-table-column>
        <el-table-column label="预览" width="120">
          <template #default="{ row }">
            <el-image v-if="row.result_url" :src="row.result_url" style="width:70px;height:90px" fit="cover" :preview-src-list="[row.result_url]" preview-teleported />
            <span v-else>-</span>
          </template>
        </el-table-column>
        <el-table-column prop="model_version" label="模型" width="130" />
        <el-table-column label="提示词摘要" min-width="180">
          <template #default="{ row }"><span class="ellipsis">{{ promptOf(row) }}</span></template>
        </el-table-column>
        <el-table-column prop="created_at" label="创建时间" width="170" />
        <el-table-column label="操作" width="180" fixed="right">
          <template #default="{ row }">
            <el-button size="small" type="success" :disabled="row.status !== 'done'" @click="review(row, 'pass')">通过</el-button>
            <el-button size="small" type="danger" :disabled="row.status !== 'done'" @click="review(row, 'redo')">重做</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { Refresh } from '@element-plus/icons-vue'
import { ElMessage } from 'element-plus'
import { TasksApi } from '@/api'

const tab = ref('done')
const tasks = ref([])
let timer = null

const list = computed(() => (tab.value === 'all' ? tasks.value : tasks.value.filter((t) => t.status === 'done')))

function typeLabel(t) { return { motion: '动作迁移', music_drive: '音乐驱动', image: '生图', outfit: '换装' }[t] || t }
function statusLabel(s) { return { queued: '排队中', running: '生成中', done: '待质检', verified: '已通过', rejected: '已重做', failed: '失败' }[s] || s }
function statusType(s) { return { queued: 'info', running: 'warning', done: 'primary', verified: 'success', rejected: 'danger', failed: 'danger' }[s] || 'info' }
function promptOf(row) {
  try { return JSON.parse(row.params || '{}').prompt || '-' } catch { return '-' }
}

async function review(row, action) {
  try {
    await TasksApi.review(row.id, action)
    ElMessage.success(action === 'pass' ? '已通过 → 进入成品库' : '已标记重做')
    load()
  } catch (e) {
    ElMessage.error('操作失败：' + (e.message || ''))
  }
}

async function load() {
  try { tasks.value = await TasksApi.list() } catch (e) { tasks.value = [] }
}

onMounted(() => { load(); timer = setInterval(load, 4000) })
onUnmounted(() => clearInterval(timer))
</script>

<style scoped>
.head { display: flex; justify-content: space-between; align-items: center; }
.card-title { font-weight: 600; }
.ellipsis { display: inline-block; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
</style>
