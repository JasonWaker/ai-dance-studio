<template>
  <div>
    <el-row :gutter="16">
      <el-col :span="12">
        <el-card shadow="never">
          <template #header><span class="card-title">发布合规检查</span></template>
          <el-checkbox-group v-model="checked" class="check-group">
            <el-checkbox v-for="c in checklist" :key="c.key" :label="c.key" :value="c.key">{{ c.label }}</el-checkbox>
          </el-checkbox-group>
          <el-divider content-position="left">文案快速检测</el-divider>
          <el-input v-model="text" type="textarea" :rows="3" placeholder="粘贴要发布的标题 + 文案 + 话题，检查违禁词与擦边词" />
          <div style="margin-top:12px;display:flex;gap:8px">
            <el-button type="primary" @click="runCheck">运行检查</el-button>
            <el-button @click="reset">重置</el-button>
          </div>
          <el-alert v-if="result" :type="result.passed ? 'success' : 'error'" :closable="false" style="margin-top:12px"
            :title="result.passed ? '通过，可发布' : '存在问题，请修正'" :description="result.problems.join('；')" />
        </el-card>
      </el-col>
      <el-col :span="12">
        <el-card shadow="never">
          <template #header><span class="card-title">发布前操作清单</span></template>
          <ul class="steps">
            <li>1. 画面前 5 秒标注 <b>"本视频含 AI 生成内容"</b></li>
            <li>2. 发布页勾选 <b>AI 生成标签</b>（未标注会被限流 50%–80%）</li>
            <li>3. 只使用 <b>AI 虚拟形象</b>或自有授权肖像，禁止真人/名人脸</li>
            <li>4. 动作控制在<b>舞蹈欣赏 / 穿搭展示 / 健身向</b>，避开"魅惑舞蹈"擦边</li>
            <li>5. 音乐选<b>平台曲库 / 已授权</b>素材</li>
            <li>6. 一次发 1–2 条，避免批量搬运同质化</li>
            <li>7. 带上 2–3 个官方话题（去选题中心选）</li>
          </ul>
          <el-button type="primary" :icon="Promotion" @click="$router.push('/videos')">去成品库选择要发布的成片</el-button>
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { Promotion } from '@element-plus/icons-vue'
import { VideosApi, HealthApi } from '@/api'

const checklist = ref([])
const checked = ref([])
const text = ref('')
const result = ref(null)

async function runCheck() {
  const data = {
    title: text.value,
    caption: '',
    aiLabeled: checked.value.includes('aiLabeled'),
    aiTagChecked: checked.value.includes('aiTagChecked'),
    hasRealFace: checked.value.includes('noRealFace') ? false : true
  }
  // hasRealFace 语义反转：勾选 noRealFace 表示无真人面容
  data.hasRealFace = !checked.value.includes('noRealFace')
  try {
    result.value = await VideosApi.complianceCheck(data)
  } catch (e) { result.value = null }
}
function reset() { checked.value = []; text.value = ''; result.value = null }

onMounted(async () => {
  try {
    const h = await HealthApi.get()
    checklist.value = h.checklist || []
  } catch (e) {
    checklist.value = [
      { key: 'aiLabeled', label: '画面前 5 秒标注"本视频含 AI 生成内容"' },
      { key: 'aiTagChecked', label: '发布页勾选 AI 生成标签' },
      { key: 'noRealFace', label: '无真人面容/未授权肖像' },
      { key: 'noErotic', label: '无低俗擦边动作/文案/暗示' },
      { key: 'noWatermark', label: '无水印、无违禁词' },
      { key: 'noDuplicate', label: '非批量搬运同质化' },
      { key: 'copyrightOk', label: '舞源/音乐版权来源合规' }
    ]
  }
})
</script>

<style scoped>
.card-title { font-weight: 600; }
.check-group { display: flex; flex-direction: column; gap: 10px; }
.steps { padding-left: 18px; color: #4b5563; line-height: 2.1; }
</style>
