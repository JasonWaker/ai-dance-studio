<template>
  <div>
    <el-card shadow="never" style="margin-bottom:16px">
      <template #header><span class="card-title">官方话题（发布时带上 2–3 个）</span></template>
      <el-table :data="topics" size="small">
        <el-table-column prop="name" label="话题" />
        <el-table-column prop="hot_score" label="热度" width="120" />
        <el-table-column label="状态" width="100">
          <template #default="{ row }"><el-tag :type="row.enabled ? 'success' : 'info'" size="small">{{ row.enabled ? '启用' : '停用' }}</el-tag></template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-row :gutter="16">
      <el-col :span="12">
        <el-card shadow="never">
          <template #header><span class="card-title">今日灵感（解决词穷）</span></template>
          <el-space direction="vertical" fill style="width:100%">
            <el-button type="primary" plain :icon="MagicStick" @click="roll" :loading="rolling">随机抽取一组灵感</el-button>
            <el-empty v-if="!inspiration.length" description="点击上方按钮抽取灵感" :image-size="80" />
            <div v-for="g in inspiration" :key="g.id" class="insp">
              <el-tag size="small" type="warning">{{ g.category }}</el-tag>
              <span class="insp-title">{{ g.title }}</span>
              <div class="insp-content">{{ g.content }}</div>
            </div>
          </el-space>
        </el-card>
      </el-col>
      <el-col :span="12">
        <el-card shadow="never">
          <template #header><span class="card-title">素材准备清单</span></template>
          <el-alert type="info" :closable="false" show-icon title="每日批次 = 10 条候选 / 2 条达标" description="选题 20–30 分钟 → 生图 30–60 分钟 → 生成 → 剪辑 → 发布" />
          <ul class="todo">
            <li>圈定 3–5 个可蹭话题（见上方列表）</li>
            <li>收藏 3–5 条爆款舞蹈参考视频（8–12s、动作幅度大）</li>
            <li>准备 3 首节奏明快的音乐（可在资产库上传并自动测 BPM）</li>
            <li>去提示词中心挑选造型 / 场景 / 文案组合</li>
          </ul>
          <el-button type="primary" :icon="Plus" @click="$router.push('/assets')">去资产库上传素材</el-button>
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { MagicStick, Plus } from '@element-plus/icons-vue'
import { TopicsApi, PromptsApi } from '@/api'

const topics = ref([])
const inspiration = ref([])
const rolling = ref(false)

async function roll() {
  rolling.value = true
  try {
    inspiration.value = await PromptsApi.random({ count: 4 })
  } finally {
    rolling.value = false
  }
}

onMounted(async () => {
  try { topics.value = await TopicsApi.list() } catch (e) { /* ignore */ }
  roll()
})
</script>

<style scoped>
.card-title { font-weight: 600; }
.insp { border: 1px solid #e5e7eb; border-radius: 8px; padding: 8px 10px; margin-bottom: 8px; }
.insp-title { font-weight: 600; margin-left: 6px; }
.insp-content { color: #6b7280; font-size: 13px; margin-top: 4px; }
.todo { padding-left: 18px; color: #4b5563; line-height: 2; }
</style>
