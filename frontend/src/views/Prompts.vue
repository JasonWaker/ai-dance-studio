<template>
  <div>
    <el-row :gutter="16">
      <el-col :span="16">
        <el-card shadow="never">
          <template #header>
            <div class="head">
              <span class="card-title">提示词库</span>
              <el-button type="primary" size="small" :icon="Plus" @click="dialog = true">新增提示词</el-button>
            </div>
          </template>

          <div class="filters">
            <el-select v-model="category" clearable placeholder="全部分类" style="width:140px" @change="load">
              <el-option v-for="c in categories" :key="c" :label="c" :value="c" />
            </el-select>
            <el-input v-model="keyword" placeholder="搜索关键词…" clearable style="width:220px" @change="load" />
            <el-button type="primary" plain :icon="MagicStick" @click="rollRandom" :loading="rolling">随机灵感（解决词穷）</el-button>
          </div>

          <el-table :data="filtered" size="small" empty-text="暂无提示词">
            <el-table-column prop="category" label="分类" width="90">
              <template #default="{ row }"><el-tag size="small" type="warning">{{ row.category }}</el-tag></template>
            </el-table-column>
            <el-table-column prop="title" label="标题" width="140" />
            <el-table-column prop="content" label="内容" min-width="240" />
            <el-table-column prop="hot_count" label="热度" width="80" />
            <el-table-column label="操作" width="150" fixed="right">
              <template #default="{ row }">
                <el-button size="small" type="primary" text @click="copyPrompt(row)">复制</el-button>
                <el-button size="small" text @click="use(row)">使用+1</el-button>
                <el-button size="small" type="danger" text @click="remove(row.id)">删除</el-button>
              </template>
            </el-table-column>
          </el-table>

          <el-divider content-position="left">随机灵感结果</el-divider>
          <div v-if="inspiration.length" class="insp-list">
            <div v-for="g in inspiration" :key="g.id" class="insp">
              <el-tag size="small" type="warning">{{ g.category }}</el-tag>
              <span class="insp-title">{{ g.title }}</span>
              <div class="insp-content">{{ g.content }}</div>
              <el-button size="small" type="primary" text @click="copyPrompt(g)">复制这段</el-button>
            </div>
          </div>
          <el-empty v-else-if="rolled" description="点击随机灵感按钮，抽取造型、场景、文案组合" :image-size="70" />
        </el-card>
      </el-col>
      <el-col :span="8">
        <el-card shadow="never">
          <template #header><span class="card-title">词穷急救指南</span></template>
          <ul class="guide">
            <li><b>要画面细节</b>：搜"造型 / 场景"，复制后直接接进任务提示词</li>
            <li><b>要动作描述</b>：搜"动作"，如"复刻参考视频舞蹈、重音卡点"</li>
            <li><b>要文案</b>：搜"文案"，避免违禁词（发布前过一遍发布助手）</li>
            <li><b>组合套路</b>：造型 + 场景 + 动作 + 情绪 + 画质词，一次拼好</li>
          </ul>
        </el-card>
      </el-col>
    </el-row>

    <el-dialog v-model="dialog" title="新增提示词" width="500px">
      <el-form label-width="80px">
        <el-form-item label="分类">
          <el-select v-model="newItem.category" style="width:100%">
            <el-option v-for="c in ['造型', '场景', '动作', '文案', '画质', '运镜']" :key="c" :label="c" :value="c" />
          </el-select>
        </el-form-item>
        <el-form-item label="标题"><el-input v-model="newItem.title" placeholder="如：辣妹风 / 走廊卡点" /></el-form-item>
        <el-form-item label="内容"><el-input v-model="newItem.content" type="textarea" :rows="3" placeholder="提示词正文" /></el-form-item>
        <el-form-item label="标签"><el-input v-model="newItem.tags" placeholder="逗号分隔，如：辣妹,走廊" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialog = false">取消</el-button>
        <el-button type="primary" @click="create">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { Plus, MagicStick } from '@element-plus/icons-vue'
import { ElMessage } from 'element-plus'
import { PromptsApi } from '@/api'

const all = ref([])
const categories = ref([])
const category = ref('')
const keyword = ref('')
const inspiration = ref([])
const rolled = ref(false)
const rolling = ref(false)
const dialog = ref(false)
const newItem = ref({})

const filtered = computed(() => {
  let list = all.value
  if (category.value) list = list.filter((p) => p.category === category.value)
  if (keyword.value) list = list.filter((p) => (p.title + p.content + p.tags).includes(keyword.value))
  return list
})

async function load() {
  try {
    all.value = await PromptsApi.list({ category: category.value || undefined, keyword: keyword.value || undefined })
    categories.value = await PromptsApi.categories()
  } catch (e) { all.value = [] }
}
async function rollRandom() {
  rolling.value = true; rolled.value = true
  try { inspiration.value = await PromptsApi.random({ count: 4 }) } finally { rolling.value = false }
}
async function copyPrompt(row) {
  try {
    await navigator.clipboard.writeText(row.content)
    ElMessage.success('已复制，可粘贴到任务台提示词框')
  } catch {
    ElMessage.warning('复制失败，请手动选择')
  }
}
async function use(row) {
  try { await PromptsApi.use(row.id); load() } catch (e) { /* ignore */ }
}
async function remove(id) {
  try { await PromptsApi.remove(id); load(); ElMessage.success('已删除') } catch (e) { ElMessage.error('删除失败') }
}
async function create() {
  if (!newItem.value.content) return ElMessage.warning('内容必填')
  try {
    await PromptsApi.create(newItem.value)
    ElMessage.success('已保存')
    dialog.value = false; newItem.value = {}; load()
  } catch (e) { ElMessage.error('保存失败') }
}

onMounted(load)
</script>

<style scoped>
.head { display: flex; justify-content: space-between; align-items: center; }
.card-title { font-weight: 600; }
.filters { display: flex; gap: 10px; margin-bottom: 12px; }
.insp { border: 1px solid #e5e7eb; border-radius: 8px; padding: 8px 10px; margin-bottom: 8px; }
.insp-title { font-weight: 600; margin-left: 6px; }
.insp-content { color: #6b7280; font-size: 13px; margin: 4px 0; }
.guide { padding-left: 18px; color: #4b5563; line-height: 2; }
</style>
