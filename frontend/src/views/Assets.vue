<template>
  <div>
    <el-card shadow="never">
      <template #header>
        <div class="head">
          <span class="card-title">资产库</span>
          <el-button type="primary" :icon="Plus" @click="openCreate">新建{{ cur.label }}</el-button>
        </div>
      </template>
      <el-tabs v-model="activeTab" @tab-change="load">
        <el-tab-pane v-for="c in confs" :key="c.key" :label="c.label" :name="c.key" />
      </el-tabs>

      <el-table :data="rows" size="small" empty-text="暂无数据">
        <el-table-column v-for="col in cur.columns" :key="col.key" :prop="col.key" :label="col.label" :width="col.width || 150">
          <template v-if="col.type === 'image'" #default="{ row }">
            <el-image v-if="row[col.key]" :src="row[col.key]" style="width:60px;height:80px" fit="cover" :preview-src-list="[row[col.key]]" preview-teleported />
            <span v-else>-</span>
          </template>
          <template v-else-if="col.type === 'media'" #default="{ row }">
            <el-image v-if="row[col.key]" :src="row[col.key]" style="width:80px;height:45px" fit="cover" :preview-src-list="[row[col.key]]" preview-teleported />
            <span v-else>-</span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="100" fixed="right">
          <template #default="{ row }">
            <el-button size="small" type="danger" text @click="remove(row.id)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-dialog v-model="dialog" :title="'新建' + cur.label" width="520px">
      <el-form label-width="90px">
        <el-form-item v-for="f in cur.form" :key="f.key" :label="f.label">
          <el-input v-if="f.type === 'text'" v-model="form[f.key]" :placeholder="f.placeholder || ''" />
          <el-input v-else-if="f.type === 'number'" v-model.number="form[f.key]" type="number" placeholder="可留空" />
          <div v-else-if="f.type === 'upload'" style="width:100%">
            <el-upload
              :show-file-list="false"
              :http-request="(opt) => doUpload(opt, f)"
              accept="image/*,video/*,audio/*"
            >
              <el-button :icon="UploadFilled" :loading="uploading[f.key]">上传文件{{ f.bpmHint ? '（自动测 BPM）' : '' }}</el-button>
            </el-upload>
            <div v-if="form[f.urlKey]" class="uploaded"><el-tag size="small" type="success">已上传</el-tag><span class="url-text">{{ form[f.urlKey] }}</span></div>
            <div v-if="form[f.bpmKey]" class="bpm-tag">检测 BPM：{{ form[f.bpmKey] }}</div>
          </div>
          <el-select v-else-if="f.type === 'select'" v-model="form[f.key]" clearable style="width:100%">
            <el-option v-for="o in f.options" :key="o" :label="o" :value="o" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialog = false">取消</el-button>
        <el-button type="primary" @click="create">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { Plus, UploadFilled } from '@element-plus/icons-vue'
import { ElMessage } from 'element-plus'
import { AssetsApi, BeatApi } from '@/api'

const activeTab = ref('models')
const rows = ref([])
const dialog = ref(false)
const form = ref({})
const uploading = ref({})

const confs = [
  {
    key: 'models', label: '模特', api: 'models', columns: [
      { key: 'name', label: '名称' },
      { key: 'face_seed', label: '人脸 seed' },
      { key: 'ref_image', label: '形象图', type: 'image' },
      { key: 'status', label: '状态', width: 90 }
    ],
    form: [
      { key: 'name', label: '名称', type: 'text', placeholder: '如：小美（辣妹风）' },
      { key: 'face_seed', label: '人脸 seed', type: 'text', placeholder: '固定 seed 保持脸一致' },
      { key: 'style_prompt', label: '画风提示词', type: 'text' },
      { key: 'ref_image', label: '形象图', type: 'upload', urlKey: 'ref_image' }
    ]
  },
  {
    key: 'outfits', label: '造型', api: 'outfits', columns: [
      { key: 'name', label: '名称' },
      { key: 'style_tag', label: '风格标签', width: 120 },
      { key: 'image', label: '服装图', type: 'image' },
      { key: 'status', label: '状态', width: 90 }
    ],
    form: [
      { key: 'name', label: '名称', type: 'text', placeholder: '如：辣妹风套装' },
      { key: 'style_tag', label: '风格标签', type: 'select', options: ['辣妹', '甜妹', '运动', '职场'] },
      { key: 'image', label: '服装图', type: 'upload', urlKey: 'image' }
    ]
  },
  {
    key: 'scenes', label: '场景', api: 'scenes', columns: [
      { key: 'name', label: '名称' },
      { key: 'type', label: '类型', width: 120 },
      { key: 'description', label: '描述' },
      { key: 'ref_image', label: '参考图', type: 'image' }
    ],
    form: [
      { key: 'name', label: '名称', type: 'text', placeholder: '如：居家走廊' },
      { key: 'type', label: '类型', type: 'select', options: ['居家走廊', '卧室', '街拍', '纯色背景'] },
      { key: 'description', label: '描述', type: 'text' },
      { key: 'ref_image', label: '参考图', type: 'upload', urlKey: 'ref_image' }
    ]
  },
  {
    key: 'danceSources', label: '舞源', api: 'danceSources', columns: [
      { key: 'name', label: '名称' },
      { key: 'genre', label: '舞种', width: 120 },
      { key: 'bpm', label: 'BPM', width: 80 },
      { key: 'duration_s', label: '时长(s)', width: 90 },
      { key: 'video_url', label: '视频', type: 'media' }
    ],
    form: [
      { key: 'name', label: '名称', type: 'text', placeholder: '如：巴提巴提舞参考' },
      { key: 'genre', label: '舞种', type: 'select', options: ['K-pop', '抖音热舞', '手势舞', '经典舞'] },
      { key: 'source', label: '来源', type: 'text' },
      { key: 'video_url', label: '舞蹈视频', type: 'upload', urlKey: 'video_url', bpmKey: 'bpm', bpmHint: true }
    ]
  },
  {
    key: 'music', label: '音乐', api: 'music', columns: [
      { key: 'name', label: '名称' },
      { key: 'style', label: '风格', width: 100 },
      { key: 'bpm', label: 'BPM', width: 80 },
      { key: 'copyright', label: '版权', width: 110 }
    ],
    form: [
      { key: 'name', label: '名称', type: 'text', placeholder: '如：K-pop 舞曲 129BPM' },
      { key: 'style', label: '风格', type: 'select', options: ['K-pop', '电子', '流行', '说唱', '纯音乐'] },
      { key: 'copyright', label: '版权', type: 'select', options: ['unverified', 'own', 'licensed'] },
      { key: 'audio_url', label: '音乐文件', type: 'upload', urlKey: 'audio_url', bpmKey: 'bpm', bpmHint: true }
    ]
  }
]

const cur = computed(() => confs.find((c) => c.key === activeTab.value))

async function load() {
  try { rows.value = await AssetsApi.list(cur.value.api) } catch (e) { rows.value = [] }
}
function openCreate() {
  form.value = {}
  uploading.value = {}
  dialog.value = true
}
async function doUpload(opt, field) {
  uploading.value[field.key] = true
  try {
    if (field.bpmHint) {
      // 舞源/音乐：上传并自动检测 BPM
      const res = await BeatApi.detect(opt.file)
      form.value[field.urlKey] = res.url
      if (res.bpm) form.value[field.bpmKey] = res.bpm
      ElMessage.success(res.bpm ? `已上传，检测 BPM=${res.bpm}` : '已上传（未检测到节拍）')
    } else {
      const res = await AssetsApi.upload(opt.file)
      form.value[field.urlKey] = res.url
      ElMessage.success('已上传')
    }
  } catch (e) {
    ElMessage.error('上传失败：' + (e.message || ''))
  } finally {
    uploading.value[field.key] = false
  }
}
async function create() {
  const data = { ...form.value }
  Object.keys(data).forEach((k) => { if (data[k] === '' || data[k] === undefined) delete data[k] })
  try {
    await AssetsApi.create(cur.value.api, data)
    ElMessage.success('已保存')
    dialog.value = false
    load()
  } catch (e) {
    ElMessage.error('保存失败：' + (e.message || ''))
  }
}
async function remove(id) {
  try {
    await AssetsApi.remove(cur.value.api, id)
    ElMessage.success('已删除')
    load()
  } catch (e) { ElMessage.error('删除失败') }
}

onMounted(load)
</script>

<style scoped>
.head { display: flex; justify-content: space-between; align-items: center; }
.card-title { font-weight: 600; }
.uploaded { margin-top: 6px; display: flex; align-items: center; gap: 6px; }
.url-text { font-size: 12px; color: #6b7280; word-break: break-all; }
.bpm-tag { margin-top: 4px; font-size: 12px; color: #b45309; }
</style>
