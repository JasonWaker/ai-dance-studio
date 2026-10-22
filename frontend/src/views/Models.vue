<template>
  <div>
    <div class="page-header">
      <h2>🧠 模型中心</h2>
      <p class="hint">所有可用 AI 视频生成模型及其能力配置（数据来自 Supabase model_capabilities 表）</p>
    </div>

    <el-table :data="caps" stripe style="width: 100%" v-loading="loading">
      <el-table-column prop="provider" label="Provider" width="120">
        <template #default="{ row }">
          <el-tag :type="row.provider === 'kling' ? 'warning' : 'primary'" size="small">
            {{ row.provider === 'kling' ? 'Kling' : 'Volcengine' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="display_name" label="模型" width="240" />
      <el-table-column prop="model_id" label="Model ID" show-overflow-tooltip width="320">
        <template #default="{ row }"><code>{{ row.model_id }}</code></template>
      </el-table-column>
      <el-table-column prop="enabled" label="状态" width="80">
        <template #default="{ row }">
          <el-tag :type="row.enabled ? 'success' : 'danger'" size="small">{{ row.enabled ? '启用' : '禁用' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="支持模式" min-width="220">
        <template #default="{ row }">
          <el-tag v-for="m in row.supported_modes" :key="m" size="small" style="margin: 2px;">{{ modeLabel(m) }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="输入能力" min-width="180">
        <template #default="{ row }">
          <div class="cap-row">
            <span :class="capOn(row.supported_inputs?.image)">🎨图</span>
            <span :class="capOn(row.supported_inputs?.video)">🎬视频</span>
            <span :class="capOn(row.supported_inputs?.audio)">🎵音频</span>
          </div>
        </template>
      </el-table-column>
      <el-table-column label="时长限制" width="140">
        <template #default="{ row }">
          <span v-if="row.constraints?.min_duration_s && row.constraints?.max_duration_s">
            {{ row.constraints.min_duration_s }}–{{ row.constraints.max_duration_s }}s
          </span>
          <span v-else-if="row.constraints?.max_duration_s">≤ {{ row.constraints.max_duration_s }}s</span>
          <span v-else class="muted">—</span>
        </template>
      </el-table-column>
      <el-table-column label="备注" min-width="200">
        <template #default="{ row }">
          <span class="muted">{{ row.verification_note }}</span>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { ModelsApi } from '@/api'

const caps = ref([])
const loading = ref(false)

async function load() {
  loading.value = true
  try {
    caps.value = await ModelsApi.capabilities()
  } catch (e) {
    console.error(e)
  } finally {
    loading.value = false
  }
}

const modeLabel = (m) => ({
  i2v: '图生视频', r2v_motion: '动作迁移', r2v_reference: '视频参考',
  t2v: '文生视频', music_drive: '音乐驱动', dance_template: '舞蹈模板',
  image_gen: '生图', image_edit: '图生图', legacy: '旧任务'
}[m] || m)

const capOn = (v) => v ? 'cap-on' : 'cap-off'

onMounted(load)
</script>

<style scoped>
.page-header { margin-bottom: 16px; }
.page-header h2 { margin: 0 0 4px 0; font-size: 18px; }
.page-header .hint { margin: 0; color: #6b7280; font-size: 13px; }
.cap-row { display: flex; gap: 8px; }
.cap-row span { font-size: 12px; padding: 2px 6px; border-radius: 4px; }
.cap-on { background: #dcfce7; color: #15803d; }
.cap-off { background: #fee2e2; color: #b91c1c; opacity: .6; }
.muted { color: #9ca3af; font-size: 12px; }
</style>
