<template>
  <div>
    <div class="page-header">
      <h2>📋 任务中心</h2>
      <p class="hint">所有生成任务的实时状态、进度、结果。Worker 后台处理中 → 页面关闭不影响。</p>
    </div>

    <!-- 筛选 -->
    <el-card class="filter-card" shadow="never">
      <el-form :inline="true" :model="filter">
        <el-form-item label="模式">
          <el-select v-model="filter.mode" clearable placeholder="全部" style="width: 140px">
            <el-option v-for="m in modeOptions" :key="m.value" :label="m.label" :value="m.value" />
          </el-select>
        </el-form-item>
        <el-form-item label="状态">
          <el-select v-model="filter.status" clearable placeholder="全部" style="width: 140px">
            <el-option v-for="s in statusOptions" :key="s.value" :label="s.label" :value="s.value" />
          </el-select>
        </el-form-item>
        <el-form-item>
          <el-button :icon="Refresh" :loading="loading" @click="load">刷新</el-button>
        </el-form-item>
      </el-form>
    </el-card>

    <el-table :data="jobs" stripe style="width: 100%; margin-top: 12px" v-loading="loading">
      <el-table-column prop="mode" label="模式" width="130">
        <template #default="{ row }">
          <el-tag size="small">{{ modeLabel(row.mode) }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="模型" width="220">
        <template #default="{ row }">
          <el-tooltip :content="row.model_id" placement="top">
            <span class="model-cell">{{ shortModel(row.model_id) }}</span>
          </el-tooltip>
        </template>
      </el-table-column>
      <el-table-column label="状态" width="140">
        <template #default="{ row }">
          <el-tag :type="statusType(row.status)" size="small" effect="light">
            {{ statusLabel(row.status) }}
            <el-icon v-if="isRunning(row.status)" class="spin"><Loading /></el-icon>
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="prompt" label="Prompt" min-width="260" show-overflow-tooltip>
        <template #default="{ row }">
          <span class="muted">[{{ row.provider }}]</span>
          {{ row.prompt?.slice(0, 80) || '—' }}
        </template>
      </el-table-column>
      <el-table-column label="费用" width="110" align="right">
        <template #default="{ row }">
          <span v-if="row.actual_cost != null">¥{{ row.actual_cost }}</span>
          <span v-else-if="row.estimated_cost != null" class="muted">≈¥{{ row.estimated_cost }}</span>
          <span v-else class="muted">—</span>
        </template>
      </el-table-column>
      <el-table-column label="时间" width="180">
        <template #default="{ row }">
          <span class="muted">{{ formatTime(row.created_at) }}</span>
        </template>
      </el-table-column>
      <el-table-column label="结果" width="100">
        <template #default="{ row }">
          <template v-if="row.result_url">
            <el-link :href="row.result_url" target="_blank" type="primary" size="small">▶ 播放</el-link>
          </template>
          <span v-else class="muted">—</span>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="180" fixed="right">
        <template #default="{ row }">
          <el-button size="small" link @click="retry(row)" :disabled="row.status === 'succeeded'">
            🔄 重试
          </el-button>
          <el-button size="small" link type="danger" @click="cancel(row)" :disabled="!isCancelable(row.status)">
            ✋ 取消
          </el-button>
          <el-button size="small" link @click="showDetail(row)">📋</el-button>
        </template>
      </el-table-column>
    </el-table>

    <!-- 详情抽屉 -->
    <el-drawer v-model="detailVisible" title="任务详情" size="500px">
      <div v-if="selectedJob">
        <el-descriptions :column="1" border>
          <el-descriptions-item label="Job ID"><code>{{ selectedJob.id }}</code></el-descriptions-item>
          <el-descriptions-item label="模式">{{ modeLabel(selectedJob.mode) }}</el-descriptions-item>
          <el-descriptions-item label="Provider">{{ selectedJob.provider }}</el-descriptions-item>
          <el-descriptions-item label="Model">{{ selectedJob.model_id }}</el-descriptions-item>
          <el-descriptions-item label="状态">
            <el-tag :type="statusType(selectedJob.status)">{{ statusLabel(selectedJob.status) }}</el-tag>
          </el-descriptions-item>
          <el-descriptions-item label="Provider Job ID">
            <code>{{ selectedJob.provider_job_id || '—' }}</code>
          </el-descriptions-item>
          <el-descriptions-item label="Prompt">{{ selectedJob.prompt || '—' }}</el-descriptions-item>
          <el-descriptions-item label="负面词">{{ selectedJob.negative_prompt || '—' }}</el-descriptions-item>
          <el-descriptions-item label="画面比例">{{ selectedJob.aspect_ratio || '9:16' }}</el-descriptions-item>
          <el-descriptions-item label="时长">{{ selectedJob.duration_seconds ? selectedJob.duration_seconds + 's' : '—' }}</el-descriptions-item>
          <el-descriptions-item label="错误码">{{ selectedJob.failure_code || '—' }}</el-descriptions-item>
          <el-descriptions-item label="错误信息" v-if="selectedJob.failure_message">
            <span class="error-msg">{{ selectedJob.failure_message }}</span>
          </el-descriptions-item>
          <el-descriptions-item label="尝试次数">{{ selectedJob.attempt_count }} / {{ selectedJob.max_attempts || 3 }}</el-descriptions-item>
          <el-descriptions-item label="创建时间">{{ formatTime(selectedJob.created_at) }}</el-descriptions-item>
          <el-descriptions-item label="完成时间">{{ selectedJob.finished_at ? formatTime(selectedJob.finished_at) : '—' }}</el-descriptions-item>
        </el-descriptions>

        <div v-if="selectedJob.result_url" style="margin-top: 16px">
          <h4>成片预览</h4>
          <video :src="selectedJob.result_url" controls style="width: 100%; max-height: 300px; border-radius: 8px;" />
        </div>
      </div>
    </el-drawer>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { Refresh, Loading } from '@element-plus/icons-vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { GenerationsApi } from '@/api'

const jobs = ref([])
const loading = ref(false)
const filter = ref({ mode: '', status: '' })
const detailVisible = ref(false)
const selectedJob = ref(null)
let pollTimer = null

const modeOptions = [
  { value: 'i2v', label: '图生视频' },
  { value: 'r2v_motion', label: '动作迁移' },
  { value: 'r2v_reference', label: '视频参考' },
  { value: 't2v', label: '文生视频' },
  { value: 'music_drive', label: '音乐驱动' },
  { value: 'dance_template', label: '舞蹈模板' }
]
const statusOptions = [
  { value: 'queued', label: '排队中' },
  { value: 'submitting', label: '提交中' },
  { value: 'submitted', label: '已提交' },
  { value: 'running', label: '生成中' },
  { value: 'succeeded', label: '成功' },
  { value: 'failed', label: '失败' },
  { value: 'cancelled', label: '已取消' }
]

async function load() {
  loading.value = true
  try {
    jobs.value = await GenerationsApi.list({ ...filter.value, limit: 100 })
  } catch (e) {
    ElMessage.error('加载失败: ' + e.message)
  } finally {
    loading.value = false
  }
}

function startPolling() {
  pollTimer = setInterval(() => {
    // 只在有进行中任务时才刷新
    const hasRunning = jobs.value.some(j => isRunning(j.status))
    if (hasRunning) load()
  }, 4000)
}

async function retry(row) {
  try {
    await ElMessageBox.confirm('确认重新生成？将基于相同参数创建新任务', '重试', { type: 'warning' })
    const r = await GenerationsApi.retry(row.id)
    ElMessage.success(`新任务已创建: ${r.id.slice(0, 8)}...`)
    load()
  } catch (e) {
    if (e !== 'cancel') ElMessage.error('重试失败: ' + e.message)
  }
}

async function cancel(row) {
  try {
    await ElMessageBox.confirm('请求取消？注意：已提交到 Provider 的任务可能继续产生费用', '取消', { type: 'warning' })
    await GenerationsApi.cancel(row.id)
    ElMessage.success('取消请求已发送')
    load()
  } catch (e) {
    if (e !== 'cancel') ElMessage.error('取消失败: ' + e.message)
  }
}

function showDetail(row) { selectedJob.value = row; detailVisible.value = true }

const modeLabel = (m) => ({
  i2v: '图生视频', r2v_motion: '动作迁移', r2v_reference: '视频参考',
  t2v: '文生视频', music_drive: '音乐驱动', dance_template: '舞蹈模板',
  image_gen: '生图', image_edit: '图生图', legacy: '旧任务'
}[m] || m)
const shortModel = (id) => {
  const map = {
    'doubao-seedance-2-5-260628': 'Seedance 2.5',
    'doubao-seedance-2-0-260128': 'Seedance 2.0',
    'doubao-seedance-2-0-fast-260128': 'Seedance 2.0 Fast',
    'doubao-seedance-2-0-mini-260615': 'Seedance 2.0 Mini',
    'doubao-seedream-4-0-20260415': 'Seedream 4.0',
    'kling-v2-6': 'Kling v2-6',
    'kling-v3': 'Kling v3'
  }
  return map[id] || id?.slice(0, 28) || '—'
}
const statusLabel = (s) => ({
  queued: '排队中', submitting: '提交中', submitted: '已提交',
  running: '生成中', postprocessing: '后处理', succeeded: '成功',
  failed: '失败', reconciling: '核对中',
  cancel_requested: '请求取消', cancelled: '已取消'
}[s] || s)
const statusType = (s) => ({
  queued: 'info', submitting: 'warning', submitted: 'warning',
  running: 'warning', postprocessing: 'warning', succeeded: 'success',
  failed: 'danger', reconciling: 'warning',
  cancel_requested: 'info', cancelled: 'info'
}[s] || 'info')
const isRunning = (s) => ['queued','submitting','submitted','running','postprocessing','reconciling'].includes(s)
const isCancelable = (s) => ['queued','submitting','submitted','running'].includes(s)
const formatTime = (t) => t ? new Date(t).toLocaleString('zh-CN', { hour12: false }) : '—'

onMounted(() => { load(); startPolling() })
onUnmounted(() => { if (pollTimer) clearInterval(pollTimer) })
</script>

<style scoped>
.page-header { margin-bottom: 16px; }
.page-header h2 { margin: 0 0 4px 0; font-size: 18px; }
.page-header .hint { margin: 0; color: #6b7280; font-size: 13px; }
.filter-card { margin-bottom: 4px; }
.model-cell { font-family: monospace; font-size: 12px; }
.muted { color: #9ca3af; font-size: 12px; }
.spin { animation: spin 1s linear infinite; margin-left: 4px; }
@keyframes spin { to { transform: rotate(360deg); } }
.error-msg { color: #dc2626; white-space: pre-wrap; font-size: 12px; }
</style>
