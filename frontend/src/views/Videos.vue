<template>
  <div>
    <el-card shadow="never" style="margin-bottom:16px">
      <div class="head">
        <span class="card-title">成品库（仅"已通过质检"的视频）</span>
        <div>
          <el-button type="primary" :icon="Download" :disabled="!selected.length" @click="doExport">导出选中（{{ selected.length }}）</el-button>
          <el-button size="small" :icon="Refresh" circle @click="load" />
        </div>
      </div>
    </el-card>

    <el-card shadow="never">
      <el-table :data="videos" size="small" empty-text="暂无成品（先去任务台生成并通过质检）" @selection-change="(v) => (selected = v)">
        <el-table-column type="selection" width="45" />
        <el-table-column label="预览" width="110">
          <template #default="{ row }">
            <el-image v-if="row.file_url" :src="row.file_url" style="width:70px;height:90px" fit="cover" :preview-src-list="[row.file_url]" preview-teleported />
            <span v-else>-</span>
          </template>
        </el-table-column>
        <el-table-column prop="resolution" label="分辨率" width="100" />
        <el-table-column prop="bpm" label="BPM" width="90" />
        <el-table-column label="合规状态" width="110">
          <template #default="{ row }"><el-tag :type="row.compliance === 'passed' ? 'success' : 'warning'" size="small">{{ row.compliance }}</el-tag></template>
        </el-table-column>
        <el-table-column label="播放/点赞" width="140">
          <template #default="{ row }">
            <span class="stat-text">▶ {{ row.play_count || 0 }} | ♥ {{ row.like_count || 0 }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="created_at" label="创建时间" width="170" />
        <el-table-column label="操作" width="220" fixed="right">
          <template #default="{ row }">
            <el-button size="small" text type="primary" @click="checkCompliance(row)">合规预检</el-button>
            <el-button size="small" text @click="fillStats(row)">数据回填</el-button>
            <el-button v-if="row.file_url" size="small" text type="primary" @click="download(row)">下载</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- 合规预检弹窗 -->
    <el-dialog v-model="complianceDialog" title="发布前合规预检" width="560px">
      <el-form label-width="110px">
        <el-form-item label="标题"><el-input v-model="complianceForm.title" placeholder="发布标题" /></el-form-item>
        <el-form-item label="文案"><el-input v-model="complianceForm.caption" type="textarea" :rows="3" placeholder="发布文案 / 话题" /></el-form-item>
        <el-form-item label="AI 标注">
          <el-checkbox v-model="complianceForm.aiLabeled">画面前 5 秒标注"本视频含 AI 生成内容"</el-checkbox>
        </el-form-item>
        <el-form-item label="平台标签">
          <el-checkbox v-model="complianceForm.aiTagChecked">发布页勾选 AI 生成标签</el-checkbox>
        </el-form-item>
        <el-form-item label="肖像">
          <el-checkbox v-model="complianceForm.hasRealFace">画面含真人面容</el-checkbox>
        </el-form-item>
      </el-form>
      <el-divider content-position="left">检查结果</el-divider>
      <template v-if="complianceResult">
        <el-alert v-if="complianceResult.passed" type="success" :closable="false" title="通过：可发布" />
        <el-alert v-else type="error" :closable="false" title="存在风险，请修正" :description="complianceResult.problems.join('；')" />
      </template>
      <template #footer>
        <el-button type="primary" @click="runCompliance">运行检查</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { Download, Refresh } from '@element-plus/icons-vue'
import { ElMessage } from 'element-plus'
import { VideosApi } from '@/api'

const videos = ref([])
const selected = ref([])
const complianceDialog = ref(false)
const complianceForm = ref({})
const complianceResult = ref(null)

async function load() {
  try { videos.value = await VideosApi.list('passed') } catch (e) { videos.value = [] }
}
function checkCompliance(row) {
  complianceForm.value = { title: row.title || '', caption: '', aiLabeled: false, aiTagChecked: false, hasRealFace: false }
  complianceResult.value = null
  complianceDialog.value = true
}
async function runCompliance() {
  try {
    complianceResult.value = await VideosApi.complianceCheck(complianceForm.value)
  } catch (e) { ElMessage.error('检查失败') }
}
async function doExport() {
  const ids = selected.value.map((v) => v.id)
  if (!ids.length) return
  try {
    const res = await VideosApi.export(ids)
    ElMessage.success(`已生成导出任务，共 ${res.files.length} 个成品`)
  } catch (e) { ElMessage.error('导出失败：' + (e.message || '')) }
}
function download(row) {
  const a = document.createElement('a')
  a.href = row.file_url
  a.download = `${row.id.slice(0, 8)}.mp4`
  a.click()
}
async function fillStats(row) {
  const { value } = await ElMessageBoxPrompt()
  if (value) {
    try {
      await VideosApi.stats(row.id, { play_count: value, like_count: Math.round(value * 0.08) })
      ElMessage.success('已回填')
      load()
    } catch (e) { ElMessage.error('回填失败') }
  }
}
function ElMessageBoxPrompt() {
  return import('element-plus').then(({ ElMessageBox }) =>
    ElMessageBox.prompt('输入播放量（点赞自动按 8% 估算）', '数据回填', { confirmButtonText: '保存', inputPattern: /^\d+$/, inputErrorMessage: '请输入数字' })
  )
}

onMounted(load)
</script>

<style scoped>
.head { display: flex; justify-content: space-between; align-items: center; }
.card-title { font-weight: 600; }
.stat-text { color: #6b7280; font-size: 13px; }
</style>
