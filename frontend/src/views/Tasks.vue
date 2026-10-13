<template>
  <div>
    <el-card shadow="never" style="margin-bottom:16px">
      <template #header><span class="card-title">创建生成任务</span></template>
      <el-form :inline="true" :model="form" label-width="90px">
        <el-form-item label="任务类型">
          <el-select v-model="form.type" style="width:180px" @change="onTypeChange">
            <el-option label="动作迁移（换人不换动作）" value="motion" />
            <el-option label="音乐驱动（BGM 自动编舞）" value="music_drive" />
            <el-option label="舞蹈模板直出（最省钱）" value="dance" />
            <el-option label="生图（先出效果图）" value="image" />
            <el-option label="换装" value="outfit" />
          </el-select>
        </el-form-item>

        <el-form-item label="模型版本">
          <el-select v-model="form.model_version" style="width:230px">
            <el-option v-for="m in models" :key="m.value" :label="m.label" :value="m.value" />
          </el-select>
          <div class="cost-tip">预估：{{ costTip }}</div>
        </el-form-item>

        <el-form-item v-if="form.type === 'dance'" label="舞蹈模板">
          <div class="dance-row">
            <el-select v-model="form.template_id" clearable filterable style="width:200px" @change="onTemplateChange">
              <el-option v-for="t in danceTemplates" :key="t.id" :label="t.name" :value="t.id" />
            </el-select>
            <el-button size="small" :icon="Plus" @click="tplDialog = true">新增舞蹈</el-button>
          </div>
        </el-form-item>

        <el-form-item label="模特">
          <el-select v-model="form.model_id" clearable style="width:140px">
            <el-option v-for="m in modelsList" :key="m.id" :label="m.name" :value="m.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="造型">
          <el-select v-model="form.outfit_id" clearable style="width:140px">
            <el-option v-for="o in outfits" :key="o.id" :label="o.name" :value="o.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="场景">
          <el-select v-model="form.scene_id" clearable style="width:140px">
            <el-option v-for="s in scenes" :key="s.id" :label="s.name" :value="s.id" />
          </el-select>
        </el-form-item>
        <el-form-item v-if="form.type === 'motion'" label="舞源(参考视频)">
          <el-select v-model="form.dance_source_id" clearable style="width:140px">
            <el-option v-for="d in danceSources" :key="d.id" :label="d.name" :value="d.id" />
          </el-select>
        </el-form-item>
        <el-form-item v-if="form.type === 'music_drive' || form.type === 'dance'" label="音乐">
          <el-select v-model="form.music_id" clearable style="width:140px">
            <el-option v-for="m in music" :key="m.id" :label="m.name" :value="m.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="时长(s)">
          <el-input-number v-model="form.duration" :min="4" :max="30" style="width:110px" />
        </el-form-item>
        <el-form-item label="比例">
          <el-select v-model="form.ratio" style="width:90px">
            <el-option label="9:16" value="9:16" />
            <el-option label="16:9" value="16:9" />
            <el-option label="1:1" value="1:1" />
          </el-select>
        </el-form-item>

        <el-form-item label="提示词">
          <div class="prompt-row">
            <el-input v-model="form.prompt" type="textarea" :rows="2" style="width:400px"
              placeholder="描述形象、动作或舞风；词穷点右侧 💡 词库" />
            <el-button size="small" :icon="MagicStick" @click="libDialog = true">💡 词库</el-button>
          </div>
        </el-form-item>
        <el-form-item>
          <el-button type="primary" :icon="VideoPlay" :loading="creating" @click="createTask">创建任务</el-button>
        </el-form-item>
      </el-form>
      <el-alert v-if="showMockTip" type="warning" :closable="false" show-icon style="margin-top:8px"
        title="当前未检测到 AI 密钥配置，任务将以模拟模式生成；在 backend/.env 填入密钥后自动切换真实生成。" />
      <el-alert v-else type="success" :closable="false" show-icon style="margin-top:8px"
        title="已接入真实生成：火山方舟（Seedance 视频 / Seedream 生图）+ 可灵（动作迁移）。提交任务即真实调用（按模型计费）。" />
    </el-card>

    <el-card shadow="never">
      <template #header>
        <div class="head">
          <span class="card-title">任务列表</span>
          <el-button size="small" :icon="Refresh" circle @click="load" />
        </div>
      </template>
      <el-table :data="tasks" size="small" empty-text="暂无任务">
        <el-table-column prop="type" label="类型" width="105">
          <template #default="{ row }"><el-tag size="small">{{ typeLabel(row.type) }}</el-tag></template>
        </el-table-column>
        <el-table-column prop="model_version" label="模型" width="150" />
        <el-table-column label="状态" width="100">
          <template #default="{ row }"><el-tag :type="statusType(row.status)" size="small">{{ statusLabel(row.status) }}</el-tag></template>
        </el-table-column>
        <el-table-column label="结果" width="110">
          <template #default="{ row }">
            <el-image v-if="row.result_url" :src="row.result_url" style="width:60px;height:80px" fit="cover" :preview-src-list="[row.result_url]" preview-teleported />
            <span v-else>-</span>
          </template>
        </el-table-column>
        <el-table-column prop="created_at" label="创建时间" width="165" />
        <el-table-column label="失败原因" min-width="130">
          <template #default="{ row }"><span class="err">{{ row.error || '' }}</span></template>
        </el-table-column>
        <el-table-column label="操作" width="110" fixed="right">
          <template #default="{ row }">
            <el-button size="small" text type="primary" @click="showDetail(row)">详情 / 回溯</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- 提示词库弹窗 -->
    <el-dialog v-model="libDialog" title="💡 提示词库（点击即追加，解决词穷）" width="640px">
      <el-tabs v-model="libCategory">
        <el-tab-pane v-for="cat in libGroups" :key="cat" :label="cat" :name="cat" />
      </el-tabs>
      <div class="lib-words">
        <el-tag v-for="p in currentLibItems" :key="p.id" class="lib-tag" size="large" closable @click="appendPrompt(p.content)">
          {{ p.title || p.content.slice(0, 16) }}
        </el-tag>
        <el-empty v-if="!currentLibItems.length" description="该分类暂无词条" :image-size="60" />
      </div>
      <template #footer><span class="lib-hint">点击词条追加到提示词框（自动用逗号连接）</span></template>
    </el-dialog>

    <!-- 新增舞蹈模板弹窗 -->
    <el-dialog v-model="tplDialog" title="新增舞蹈模板（入库，所有人共享）" width="480px">
      <el-form label-width="90px">
        <el-form-item label="舞蹈名"><el-input v-model="newTpl.name" placeholder="如：科目三" /></el-form-item>
        <el-form-item label="动作要点"><el-input v-model="newTpl.desc" type="textarea" :rows="3" placeholder="越具体越好，如：双手甩动，脚步左右横移，扭胯" /></el-form-item>
      </el-form>
      <div class="tpl-hint">💡 舞蹈名越火（全网有人拍过），Seedance 跳得越准；冷门舞蹈需要写更详细的动作描述</div>
      <template #footer>
        <el-button @click="tplDialog = false">取消</el-button>
        <el-button type="primary" :loading="creatingTpl" @click="saveTpl">入库</el-button>
      </template>
    </el-dialog>

    <!-- 任务详情 / prompt 回溯弹窗 -->
    <el-dialog v-model="detailDialog" title="任务详情（完整提示词回溯）" width="560px">
      <template v-if="detail">
        <el-descriptions :column="2" size="small" border>
          <el-descriptions-item label="类型">{{ typeLabel(detail.type) }}</el-descriptions-item>
          <el-descriptions-item label="状态">{{ statusLabel(detail.status) }}</el-descriptions-item>
          <el-descriptions-item label="模型">{{ detail.model_version }}</el-descriptions-item>
          <el-descriptions-item label="创建时间">{{ detail.created_at }}</el-descriptions-item>
        </el-descriptions>
        <div class="detail-sec">完整生成提示词（送 AI 的原文，可复制存档复现）</div>
        <div class="prompt-box">{{ promptOf(detail) }}</div>
        <el-button size="small" type="primary" text @click="copyPrompt">📋 复制</el-button>
        <el-divider />
        <div class="detail-sec">生成结果</div>
        <el-image v-if="detail.result_url" :src="detail.result_url" style="width:140px;height:190px" fit="cover" :preview-src-list="[detail.result_url]" preview-teleported />
        <span v-else class="err">{{ detail.error || '暂无结果' }}</span>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { VideoPlay, Refresh, Plus, MagicStick } from '@element-plus/icons-vue'
import { ElMessage } from 'element-plus'
import { TasksApi, AssetsApi, TemplatesApi, PromptsApi, HealthApi } from '@/api'

const models = [
  { value: 'seedance-2.5', label: 'Seedance 2.5（音频驱动·30s·¥2/秒）' },
  { value: 'seedance-2.0', label: 'Seedance 2.0（视频参考·15s·¥1/秒）' },
  { value: 'seedance-2.0-fast', label: 'Seedance 2.0 fast（低成本·¥0.8/秒）' },
  { value: 'seedance-2.0-mini', label: 'Seedance 2.0 mini（最省钱·¥0.5/秒）' },
  { value: 'kling-v2-6', label: '可灵 Kling v2.6（动作迁移·积分计费）' },
  { value: 'kling-v3', label: '可灵 Kling v3（高品质·积分计费）' }
]

const form = ref({ type: 'motion', model_version: 'seedance-2.5', duration: 10, ratio: '9:16', prompt: '' })
const tasks = ref([])
const modelsList = ref([]); const outfits = ref([]); const scenes = ref([])
const danceSources = ref([]); const music = ref([]); const danceTemplates = ref([])
const creating = ref(false); const showMockTip = ref(false)
let timer = null

// 词库
const libDialog = ref(false)
const libCategory = ref('造型')
const libGroups = ref([])
const libAll = ref([])
const currentLibItems = computed(() => libAll.value.filter((p) => p.category === libCategory.value))

// 舞蹈模板
const tplDialog = ref(false)
const newTpl = ref({ name: '', desc: '' })
const creatingTpl = ref(false)

// 详情
const detailDialog = ref(false)
const detail = ref(null)

const costTip = computed(() => {
  const m = models.find((x) => x.value === form.value.model_version)
  const sec = Math.max(4, form.value.duration)
  if (form.value.model_version?.startsWith('kling')) return '可灵按官方积分计价（约¥0.3-1/秒）'
  const price = { 'seedance-2.5': 2, 'seedance-2.0': 1, 'seedance-2.0-fast': 0.8, 'seedance-2.0-mini': 0.5 }[form.value.model_version] || 1
  return `约 ¥${(price * sec).toFixed(1)}（${sec}秒）`
})

function typeLabel(t) { return { motion: '动作迁移', music_drive: '音乐驱动', dance: '舞蹈直出', image: '生图', outfit: '换装' }[t] || t }
function statusLabel(s) { return { queued: '排队中', running: '生成中', done: '待质检', verified: '已通过', rejected: '已重做', failed: '失败' }[s] || s }
function statusType(s) { return { queued: 'info', running: 'warning', done: 'primary', verified: 'success', rejected: 'danger', failed: 'danger' }[s] || 'info' }
function promptOf(row) {
  try { return JSON.parse(row.params || '{}').prompt || '-' } catch { return '-' }
}
function onTypeChange() {
  if (form.value.type === 'dance' && !form.value.model_version?.startsWith('seedance')) {
    form.value.model_version = 'seedance-2.0-mini' // 舞蹈直出默认最省钱模型
  }
  if (form.value.type === 'image') form.value.model_version = 'seedance-2.5'
}
function onTemplateChange(id) {
  const t = danceTemplates.value.find((x) => x.id === id)
  if (!t) return
  form.value.template_name = t.name
  form.value.template_desc = t.prompt || ''
  // 自动组装提示词
  const outfit = outfits.value.find((o) => o.id === form.value.outfit_id)?.name || '默认造型'
  const scene = scenes.value.find((s) => s.id === form.value.scene_id)?.name || '室内'
  form.value.prompt = `一位20岁左右的长发亚洲女孩，身穿${outfit}，站在${scene}场景中，跳【${t.name}】舞，动作要点：${t.prompt || '大幅度卡点、律动感强'}，动作与音乐重音精准对齐，动作连贯流畅，9:16竖构图`
}
function appendPrompt(text) {
  if (!text) return
  form.value.prompt = form.value.prompt ? `${form.value.prompt}，${text}` : text
  ElMessage.success('已追加')
}
async function saveTpl() {
  if (!newTpl.value.name) return ElMessage.warning('舞蹈名必填')
  creatingTpl.value = true
  try {
    await TemplatesApi.create({ type: '舞蹈', name: newTpl.value.name, prompt: newTpl.value.desc })
    ElMessage.success('已入库，所有人可见')
    tplDialog.value = false
    newTpl.value = { name: '', desc: '' }
    loadTemplates()
  } catch (e) { ElMessage.error('入库失败：' + (e.message || '')) } finally { creatingTpl.value = false }
}
async function copyPrompt() {
  try {
    await navigator.clipboard.writeText(promptOf(detail.value))
    ElMessage.success('已复制完整提示词')
  } catch { ElMessage.warning('复制失败，请手动选择') }
}
function showDetail(row) {
  detail.value = row
  detailDialog.value = true
}

async function createTask() {
  creating.value = true
  try {
    const params = {
      prompt: form.value.prompt || undefined,
      duration: form.value.duration,
      ratio: form.value.ratio,
      template_name: form.value.template_name,
      template_desc: form.value.template_desc
    }
    const data = {
      type: form.value.type,
      model_version: form.value.model_version,
      model_id: form.value.model_id || undefined,
      outfit_id: form.value.outfit_id || undefined,
      scene_id: form.value.scene_id || undefined,
      dance_source_id: form.value.type === 'motion' ? form.value.dance_source_id || undefined : undefined,
      music_id: (form.value.type === 'music_drive' || form.value.type === 'dance') ? form.value.music_id || undefined : undefined,
      params
    }
    await TasksApi.create(data)
    ElMessage.success(`任务已创建并进入队列（${costTip.value}）`)
    load()
  } catch (e) {
    ElMessage.error('创建失败：' + (e.message || ''))
  } finally {
    creating.value = false
  }
}

async function loadTemplates() {
  try { danceTemplates.value = await TemplatesApi.list('舞蹈') } catch (e) { danceTemplates.value = [] }
}
async function loadLib() {
  try {
    libAll.value = await PromptsApi.list()
    libGroups.value = [...new Set(libAll.value.map((p) => p.category))]
  } catch (e) { libAll.value = [] }
}

async function load() {
  try {
    tasks.value = await TasksApi.list()
    const [m, o, s, d, mu, h] = await Promise.all([
      AssetsApi.list('models'), AssetsApi.list('outfits'), AssetsApi.list('scenes'),
      AssetsApi.list('danceSources'), AssetsApi.list('music'), HealthApi.get()
    ])
    modelsList.value = m; outfits.value = o; scenes.value = s
    danceSources.value = d; music.value = mu
    const p = h.providers || {}
    showMockTip.value = h.mockMode || (!p.seedance?.configured && !p.kling?.configured && !p.jimeng?.configured)
  } catch (e) { /* ignore */ }
}

onMounted(() => {
  load(); loadTemplates(); loadLib()
  timer = setInterval(load, 4000)
})
onUnmounted(() => clearInterval(timer))
</script>

<style scoped>
.card-title { font-weight: 600; }
.head { display: flex; justify-content: space-between; align-items: center; }
.cost-tip { font-size: 12px; color: #b45309; margin-top: 2px; }
.dance-row, .prompt-row { display: flex; gap: 8px; align-items: flex-start; }
.lib-words { display: flex; flex-wrap: wrap; gap: 8px; min-height: 60px; }
.lib-tag { cursor: pointer; }
.lib-hint { font-size: 12px; color: #94a3b8; }
.tpl-hint { font-size: 12px; color: #b45309; background: #fffbeb; border-radius: 6px; padding: 6px 10px; }
.detail-sec { font-weight: 600; margin: 8px 0; }
.prompt-box { background: #f1f5f9; border-radius: 6px; padding: 10px; font-size: 13px; white-space: pre-wrap; word-break: break-all; max-height: 220px; overflow: auto; }
.err { color: #dc2626; font-size: 12px; }
</style>
