<template>
  <div class="generate-wrap">
    <!-- 顶部：Tab 切换四种模式 -->
    <div class="mode-tabs">
      <div class="page-title">🎬 AI 视频生成台</div>
      <el-tabs v-model="activeMode" type="card" class="mode-tabs-inner" @change="onModeChange">
        <el-tab-pane label="📸 图生视频 (I2V)" name="i2v" />
        <el-tab-pane label="🎭 动作迁移 (R2V)" name="r2v_motion" />
        <el-tab-pane label="🎬 视频参考 (R2V)" name="r2v_reference" />
        <el-tab-pane label="✍️ 文生视频 (T2V)" name="t2v" />
      </el-tabs>
    </div>

    <el-row :gutter="16">
      <!-- 左栏：表单 -->
      <el-col :span="14">
        <el-card shadow="never" class="form-card">
          <el-form :model="form" label-width="100px" label-position="top" size="default">

            <!-- 模型选择（能力驱动） -->
            <el-form-item label="模型选择">
              <div class="model-picker">
                <div
                  v-for="m in availableModels"
                  :key="m.model_id"
                  class="model-tile"
                  :class="{ active: form.model_id === m.model_id, disabled: !m.enabled }"
                  @click="selectModel(m)"
                >
                  <div class="tile-name">
                    {{ m.display_name || shortModel(m.model_id) }}
                    <el-tag v-if="m.provider === 'kling'" size="small" type="warning" style="margin-left:4px">Kling</el-tag>
                  </div>
                  <div class="tile-info">
                    <span v-if="m.constraints?.max_duration_s">≤{{ m.constraints.max_duration_s }}s</span>
                    <span class="dot">·</span>
                    <span :class="!m.supported_inputs?.video ? 'na' : 'ok'">
                      {{ m.supported_inputs?.video ? '支持视频参考' : '不支持视频' }}
                    </span>
                  </div>
                  <div class="tile-inputs">
                    <span class="ic" :class="m.supported_inputs?.image ? 'ok' : 'na'">🎨</span>
                    <span class="ic" :class="m.supported_inputs?.video ? 'ok' : 'na'">🎬</span>
                    <span class="ic" :class="m.supported_inputs?.audio ? 'ok' : 'na'">🎵</span>
                  </div>
                </div>
                <div v-if="availableModels.length === 0" class="no-model">
                  <el-alert type="warning" :closable="false">当前模式暂无可用模型，请到「模型中心」配置</el-alert>
                </div>
              </div>
            </el-form-item>

            <!-- 素材上传区（按模式动态） -->
            <el-form-item :label="modeAssetLabel">
              <div class="upload-area">
                <!-- 图片上传 -->
                <div v-if="needImage" class="upload-slot">
                  <div class="slot-label">
                    {{ modeImageLabel }}
                    <el-tag type="danger" size="small">必填</el-tag>
                  </div>
                  <div v-if="form.image_ref" class="preview-box">
                    <img :src="form.image_ref" class="preview-img" @click="clearImage" />
                    <div class="clear-btn" @click="clearImage">✕</div>
                  </div>
                  <el-upload v-else :show-file-list="false" :before-upload="(f) => handleImageUpload(f, 'image')" accept="image/*" drag>
                    <div class="upload-placeholder">
                      <el-icon :size="24"><Picture /></el-icon>
                      <div class="tip">拖拽图片到此处 / 点击选择</div>
                    </div>
                  </el-upload>
                </div>

                <!-- 视频上传 -->
                <div v-if="needVideo" class="upload-slot">
                  <div class="slot-label">
                    {{ modeVideoLabel }}
                    <el-tag type="danger" size="small">必填</el-tag>
                  </div>
                  <div v-if="form.reference_video" class="preview-box video-preview">
                    <video :src="form.reference_video" controls />
                    <div class="video-info">
                      <el-tag type="info" size="small">参考视频</el-tag>
                      <el-button size="small" link @click="clearVideo">清除</el-button>
                    </div>
                  </div>
                  <el-upload v-else :show-file-list="false" :before-upload="(f) => handleImageUpload(f, 'video')" accept="video/*" drag>
                    <div class="upload-placeholder">
                      <el-icon :size="24"><Film /></el-icon>
                      <div class="tip">拖拽视频到此处（支持 mp4/mov）</div>
                    </div>
                  </el-upload>
                </div>

                <!-- 音频上传 -->
                <div v-if="needAudio" class="upload-slot">
                  <div class="slot-label">音乐（可选）</div>
                  <div v-if="form.audio_ref" class="audio-box">
                    <audio :src="form.audio_ref" controls />
                    <el-button size="small" link @click="clearAudio">清除</el-button>
                  </div>
                  <el-upload v-else :show-file-list="false" :before-upload="(f) => handleImageUpload(f, 'audio')" accept="audio/*">
                    <el-button :icon="Headset">上传音乐</el-button>
                  </el-upload>
                </div>
              </div>
            </el-form-item>

            <!-- Prompt -->
            <el-form-item label="Prompt 提示词">
              <el-input v-model="form.prompt" type="textarea" :rows="4" :placeholder="promptPlaceholder" maxlength="2000" show-word-limit />
              <div class="prompt-templates">
                <span class="tmpl-label">🎨 快速插入：</span>
                <el-tag v-for="t in quickPrompts" :key="t" class="tmpl-tag" effect="plain" @click="insertPrompt(t)">{{ t }}</el-tag>
              </div>
            </el-form-item>

            <!-- 参数区 -->
            <el-row :gutter="12">
              <el-col :span="8">
                <el-form-item label="画面比例">
                  <el-select v-model="form.aspect_ratio" style="width: 100%">
                    <el-option label="9:16 竖屏" value="9:16" />
                    <el-option label="16:9 横屏" value="16:9" />
                    <el-option label="1:1 方形" value="1:1" />
                  </el-select>
                </el-form-item>
              </el-col>
              <el-col :span="8">
                <el-form-item label="时长（秒）">
                  <el-input-number v-model="form.duration_seconds" :min="4" :max="maxDuration" :step="1" style="width: 100%" />
                  <div class="muted">
                    {{ currentCaps?.constraints?.min_duration_s || 4 }}–{{ maxDuration }}s
                  </div>
                </el-form-item>
              </el-col>
              <el-col :span="8">
                <el-form-item label="预设档位">
                  <el-radio-group v-model="preset">
                    <el-radio-button value="preview">预览档</el-radio-button>
                    <el-radio-button value="quality">正式档</el-radio-button>
                  </el-radio-group>
                </el-form-item>
              </el-col>
            </el-row>

            <!-- 提交 -->
            <div class="submit-area">
              <el-button type="primary" size="large" :loading="submitting" :disabled="!canSubmit" @click="submit">
                🚀 立即生成
              </el-button>
              <div class="cost-est" v-if="costEstimate">
                <el-tag type="info" size="small">💰 预估 ≈ ¥{{ costEstimate }}</el-tag>
                <span class="muted">（实际以账单为准）</span>
              </div>
              <div v-if="!canSubmit && formErrors.length" class="form-errors">
                <el-alert v-for="e in formErrors" :key="e" :title="e" type="warning" :closable="false" size="small" show-icon />
              </div>
            </div>
          </el-form>
        </el-card>
      </el-col>

      <!-- 右栏：最近任务 + 状态 -->
      <el-col :span="10">
        <el-card shadow="never" class="right-card">
          <template #header>
            <div class="card-header">
              <span>📊 最近生成任务</span>
              <el-button size="small" link :icon="Refresh" @click="loadRecentJobs">刷新</el-button>
            </div>
          </template>
          <div v-if="recentJobs.length === 0" class="empty">
            <el-empty description="暂无任务，先在左侧提交一个试试" :image-size="80" />
          </div>
          <div v-for="job in recentJobs" :key="job.id" class="job-card">
            <div class="job-header">
              <el-tag :type="statusTag(job.status).type" size="small">{{ statusTag(job.status).text }}</el-tag>
              <span class="job-id muted">{{ job.id.slice(0, 8) }}</span>
            </div>
            <div class="job-mode">{{ modeLabel(job.mode) }} · {{ shortModel(job.model_id) }}</div>
            <div class="job-prompt muted">{{ job.prompt?.slice(0, 60) || '—' }}</div>
            <div v-if="job.failure_message" class="job-error">
              ⚠️ {{ job.failure_message?.slice(0, 80) }}
            </div>
            <div v-if="job.result_url" class="job-result">
              <video :src="job.result_url" controls />
            </div>
            <div class="job-footer">
              <span class="muted">{{ formatTime(job.created_at) }}</span>
              <el-button size="small" link @click="cloneJob(job)">📋 复制参数</el-button>
            </div>
          </div>
        </el-card>

        <el-card shadow="never" class="right-card" style="margin-top: 12px">
          <template #header><span>📌 说明</span></template>
          <ul class="tips">
            <li>提交后**立即获得任务 ID**，后台 Worker 异步处理</li>
            <li>页面关闭不影响，到「任务中心」查看进度</li>
            <li>模型能力标注为红色的参数**不支持**会被后端拦截</li>
            <li>可灵动作迁移需要参考图片 + 舞蹈视频</li>
            <li>文生视频（T2V）最省钱：Seedance 2.0 mini</li>
          </ul>
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<script setup>import { ref, computed, onMounted, onUnmounted } from 'vue';
import { ElMessage } from 'element-plus';
import { Refresh, Picture, Film, Headset } from '@element-plus/icons-vue';
import { GenerationsApi, MediaApi, ModelsApi, HealthApi } from '@/api';
// ========== 状态 ==========
const activeMode = ref('i2v');
const form = ref({
 provider: '',
 model_id: '',
 prompt: '',
 negative_prompt: '',
 image_ref: '',
 reference_video: '',
 audio_ref: '',
 aspect_ratio: '9:16',
 duration_seconds: 10
});
const submitting = ref(false);
const preset = ref('preview');
const caps = ref([]);
const recentJobs = ref([]);
let pollTimer = null;
const quickPrompts = [
 '全身正面朝向镜头、固定机位、自然舞蹈',
 '动作幅度大、卡点精准、律动感强',
 '手持自拍视角、自然摆动、街景背景',
 '特写、氛围感、霓虹灯光',
 'K-pop 风格、性感、舞台感',
 '固定镜头、全身构图、背景简洁'
];
// ========== 计算属性 ==========
const availableModels = computed(() => {
 return caps.value.filter(c => {
 const modes = c.supported_modes || [];
 return modes.includes(activeMode.value) && c.enabled;
 });
});
const currentCaps = computed(() => caps.value.find(c => c.model_id === form.value.model_id));
const maxDuration = computed(() => {
 return currentCaps.value?.constraints?.max_duration_s || 15;
});
const needImage = computed(() => ['i2v', 'r2v_motion', 'r2v_reference'].includes(activeMode.value));
const needVideo = computed(() => ['r2v_motion', 'r2v_reference'].includes(activeMode.value));
const needAudio = computed(() => activeMode.value === 'music_drive');
const modeAssetLabel = computed(() => {
 if (activeMode.value === 'i2v') return '首帧图片';
 if (activeMode.value === 'r2v_motion') return '人物图片 + 舞蹈视频';
 if (activeMode.value === 'r2v_reference') return '参考视频（可加人物/场景图）';
 return '（可上传参考图）';
});
const modeImageLabel = computed(() => {
 if (activeMode.value === 'i2v') return '首帧图片';
 if (activeMode.value === 'r2v_motion') return '人物/角色形象图';
 if (activeMode.value === 'r2v_reference') return '人物参考图（可选）';
 return '参考图片';
});
const modeVideoLabel = computed(() => {
 if (activeMode.value === 'r2v_motion') return '舞蹈动作参考视频';
 if (activeMode.value === 'r2v_reference') return '多模态参考视频';
 return '参考视频';
});
const promptPlaceholder = computed(() => {
 const ph = {
 i2v: '描述想生成的视频内容，如："人物正面朝向镜头，做自然流畅的舞蹈动作，固定机位，全身构图"',
 r2v_motion: '可选：描述想强调的动作细节，如："复刻参考视频的卡点动作，律动更强"',
 r2v_reference: '描述参考视频再创作的方向，如："保留镜头节奏但把人物换成中国女孩，背景改为赛博朋克风"',
 t2v: '自由输入，如："一个穿黑色连衣裙的女孩在霓虹街头跳舞，慢动作，电影感，9:16竖屏"',
 music_drive: '描述想让角色跳什么风格的舞，如："跟随音乐重音自动编排，K-pop 风格，动作幅度大"',
 dance_template: '已选舞蹈模板，可补充风格要求："巴提巴提舞，动作更夸张，卡点更准"'
 };
 return ph[activeMode.value] || '输入提示词';
});
const formErrors = computed(() => {
 const errs = [];
 if (!form.value.model_id)
 errs.push('请选择一个模型');
 if (needImage.value && !form.value.image_ref)
 errs.push('请上传参考图片');
 if (needVideo.value && !form.value.reference_video)
 errs.push('请上传参考视频');
 // 模型能力校验
 const caps = currentCaps.value;
 if (caps && activeMode.value === 'r2v_motion' && !caps.supported_inputs?.video) {
 errs.push(`模型 ${caps.display_name} 不支持视频参考，请切换到 Seedance 2.5 或 Kling`);
 }
 if (caps && activeMode.value === 'i2v' && !caps.supported_inputs?.image) {
 errs.push(`模型 ${caps.display_name} 不支持图片输入`);
 }
 return errs;
});
const canSubmit = computed(() => formErrors.value.length === 0 && !submitting.value);
const costEstimate = computed(() => {
 const c = currentCaps.value?.pricing_info;
 if (!c)
 return null;
 // 粗估算
 const dur = form.value.duration_seconds || 10;
 if (c.unit === 'video') {
 // 按秒计费，约 ¥0.5-1/s
 return (dur * 0.8).toFixed(1);
 }
 return null;
});
// ========== 方法 ==========
function selectModel(m) {
 form.value.model_id = m.model_id;
 form.value.provider = m.provider;
 // 自动调整时长到模型限制内
 const cap = m.constraints;
 if (cap?.max_duration_s && form.value.duration_seconds > cap.max_duration_s) {
 form.value.duration_seconds = Math.min(form.value.duration_seconds, cap.max_duration_s);
 }
 if (cap?.min_duration_s && form.value.duration_seconds < cap.min_duration_s) {
 form.value.duration_seconds = cap.min_duration_s;
 }
}
function onModeChange() {
 // 切换模式时自动选一个适配模型
 const first = availableModels.value.find(m => m.enabled);
 if (first)
 selectModel(first);
 // 清空不适用的素材
 if (!needImage.value)
 form.value.image_ref = '';
 if (!needVideo.value)
 form.value.reference_video = '';
 if (!needAudio.value)
 form.value.audio_ref = '';
}
async function handleImageUpload(file, kind) {
 try {
 const r = await MediaApi.upload(file, kind);
 if (kind === 'image')
 form.value.image_ref = r.url;
 if (kind === 'video')
 form.value.reference_video = r.url;
 if (kind === 'audio')
 form.value.audio_ref = r.url;
 ElMessage.success('上传成功: ' + (r.storage_provider === 'supabase' ? 'Supabase Storage' : '本地'));
 }
 catch (e) {
 ElMessage.error('上传失败: ' + e.message);
 }
 return false; // 阻止 el-upload 默认行为
}
function clearImage() { form.value.image_ref = ''; }
function clearVideo() { form.value.reference_video = ''; }
function clearAudio() { form.value.audio_ref = ''; }
function insertPrompt(t) {
 form.value.prompt = form.value.prompt ? form.value.prompt + '，' + t : t;
}
async function submit() {
 if (!canSubmit.value) {
 ElMessage.warning(formErrors.value.join('；'));
 return;
 }
 submitting.value = true;
 try {
 const r = await GenerationsApi.create({
 mode: activeMode.value,
 provider: form.value.provider,
 model_id: form.value.model_id,
 prompt: form.value.prompt,
 negative_prompt: form.value.negative_prompt,
 image_ref: form.value.image_ref,
 reference_video: form.value.reference_video,
 audio_ref: form.value.audio_ref,
 aspect_ratio: form.value.aspect_ratio,
 duration_seconds: form.value.duration_seconds,
 params: { preset: preset.value }
 });
 ElMessage.success(`✅ 任务已创建! ID: ${r.id.slice(0, 8)}...`);
 // 清空表单（保留模型）
 form.value.prompt = '';
 form.value.image_ref = '';
 form.value.reference_video = '';
 form.value.audio_ref = '';
 loadRecentJobs();
 // 跳转到任务中心
 // router.push('/jobs');
 }
 catch (e) {
 ElMessage.error('提交失败: ' + (e.message || JSON.stringify(e).slice(0, 100)));
 }
 finally {
 submitting.value = false;
 }
}
async function loadCaps() {
 try {
 caps.value = await ModelsApi.capabilities();
 // 自动选默认模型
 const first = caps.value.find(c => (c.supported_modes || []).includes(activeMode.value) && c.enabled);
 if (first)
 selectModel(first);
 }
 catch (e) {
 console.warn('加载模型能力失败', e);
 }
}
async function loadRecentJobs() {
 try {
 const list = await GenerationsApi.list({ limit: 10 });
 recentJobs.value = list;
 }
 catch (e) {
 console.warn(e);
 }
}
function cloneJob(job) {
 activeMode.value = job.mode;
 form.value.model_id = job.model_id;
 form.value.provider = job.provider;
 form.value.prompt = job.prompt || '';
 form.value.image_ref = job.input_snapshot?.image_ref || '';
 form.value.reference_video = job.input_snapshot?.reference_video || '';
 form.value.audio_ref = job.input_snapshot?.audio_ref || '';
 form.value.aspect_ratio = job.aspect_ratio || '9:16';
 form.value.duration_seconds = job.duration_seconds || 10;
 ElMessage.success('已复制参数，可调整后重新生成');
}
// ========== 工具 ==========
const shortModel = (id) => {
 const map = {
 'doubao-seedance-2-5-260628': 'Seedance 2.5',
 'doubao-seedance-2-0-260128': 'Seedance 2.0',
 'doubao-seedance-2-0-fast-260128': 'Seedance 2.0 Fast',
 'doubao-seedance-2-0-mini-260615': 'Seedance 2.0 Mini',
 'kling-v2-6': 'Kling v2-6', 'kling-v3': 'Kling v3'
 };
 return map[id] || id?.slice(0, 24) || '—';
};
const modeLabel = (m) => ({
 i2v: '图生视频', r2v_motion: '动作迁移', r2v_reference: '视频参考',
 t2v: '文生视频', music_drive: '音乐驱动', dance_template: '舞蹈模板', legacy: '旧任务'
}[m] || m);
const statusTag = (s) => ({
 queued: { type: 'info', text: '排队' }, submitting: { type: 'warning', text: '提交中' },
 submitted: { type: 'warning', text: '已提交' }, running: { type: 'warning', text: '生成中' },
 succeeded: { type: 'success', text: '完成' }, failed: { type: 'danger', text: '失败' },
 cancelled: { type: 'info', text: '已取消' }
}[s] || { type: 'info', text: s });
const formatTime = (t) => t ? new Date(t).toLocaleString('zh-CN', { hour12: false }) : '—';
// ========== 生命周期 ==========
onMounted(async () => {
 await loadCaps();
 await loadRecentJobs();
 pollTimer = setInterval(loadRecentJobs, 5000);
});
onUnmounted(() => { if (pollTimer)
 clearInterval(pollTimer); });
</script>

<style scoped>
.generate-wrap {}
.mode-tabs { display: flex; align-items: center; gap: 16px; margin-bottom: 12px; }
.mode-tabs .page-title { margin: 0; font-size: 18px; font-weight: 600; white-space: nowrap; }
.mode-tabs-inner { border-bottom: none; }
.mode-tabs-inner :deep(.el-tabs__nav-wrap::after) { display: none; }
.form-card, .right-card { border: 1px solid #e5e7eb; border-radius: 8px; }
.model-picker { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 8px; width: 100%; }
.model-tile {
 border: 1px solid #e5e7eb; border-radius: 8px; padding: 10px 12px;
 cursor: pointer; transition: all .15s; background: #fafafa;
}
.model-tile:hover { border-color: #2563eb; }
.model-tile.active { border-color: #2563eb; background: #eff6ff; box-shadow: 0 0 0 2px rgba(37,99,235,.1); }
.model-tile.disabled { opacity: .4; cursor: not-allowed; }
.tile-name { font-weight: 600; font-size: 13px; display: flex; align-items: center; }
.tile-info { font-size: 11px; color: #6b7280; margin-top: 4px; display: flex; gap: 6px; align-items: center; }
.tile-info .dot { opacity: .4; }
.tile-info .na { color: #dc2626; text-decoration: line-through; }
.tile-info .ok { color: #15803d; }
.tile-inputs { display: flex; gap: 4px; margin-top: 6px; font-size: 14px; }
.tile-inputs .ic.na { opacity: .3; }
.no-model { padding: 16px; grid-column: 1 / -1; }
.upload-area { display: flex; gap: 12px; flex-wrap: wrap; width: 100%; }
.upload-slot { flex: 1; min-width: 180px; }
.slot-label { font-size: 12px; color: #374151; margin-bottom: 4px; display: flex; gap: 6px; align-items: center; }
.upload-placeholder {
 border: 2px dashed #d1d5db; border-radius: 8px; padding: 20px; text-align: center;
 color: #9ca3af; cursor: pointer; transition: all .15s; background: #fafafa;
}
.upload-placeholder:hover { border-color: #2563eb; color: #2563eb; }
.upload-placeholder .tip { font-size: 12px; margin-top: 6px; }
.preview-box { position: relative; width: 100%; height: 140px; border-radius: 8px; overflow: hidden; background: #f3f4f6; }
.preview-img { width: 100%; height: 100%; object-fit: cover; cursor: pointer; }
.preview-box.video-preview { height: 160px; }
.preview-box video { width: 100%; height: 100%; object-fit: contain; background: #000; }
.video-info { position: absolute; bottom: 4px; left: 4px; right: 4px; display: flex; justify-content: space-between; }
.clear-btn {
 position: absolute; top: 4px; right: 4px; width: 22px; height: 22px; border-radius: 50%;
 background: rgba(0,0,0,.6); color: #fff; display: flex; align-items: center; justify-content: center;
 cursor: pointer; font-size: 12px;
}
.audio-box { display: flex; align-items: center; gap: 8px; }
.prompt-templates { margin-top: 6px; display: flex; flex-wrap: wrap; gap: 4px; align-items: center; }
.tmpl-label { font-size: 11px; color: #6b7280; }
.tmpl-tag { cursor: pointer; font-size: 11px; }
.tmpl-tag:hover { color: #2563eb; border-color: #2563eb; }
.submit-area { margin-top: 8px; display: flex; flex-direction: column; gap: 8px; }
.cost-est { display: flex; align-items: center; gap: 8px; }
.muted { color: #9ca3af; font-size: 12px; }
.form-errors { display: flex; flex-direction: column; gap: 4px; }
.card-header { display: flex; justify-content: space-between; align-items: center; }
.empty { padding: 20px; }
.job-card { border: 1px solid #e5e7eb; border-radius: 6px; padding: 10px 12px; margin-bottom: 8px; }
.job-header { display: flex; justify-content: space-between; align-items: center; }
.job-mode { font-size: 12px; font-weight: 600; margin: 4px 0; }
.job-prompt { font-size: 12px; margin-bottom: 4px; }
.job-error { color: #dc2626; font-size: 11px; margin: 4px 0; }
.job-result video { width: 100%; max-height: 180px; border-radius: 4px; margin-top: 6px; }
.job-footer { display: flex; justify-content: space-between; margin-top: 6px; align-items: center; }
.tips { margin: 0; padding-left: 18px; color: #6b7280; font-size: 12px; line-height: 1.8; }
.tips li { margin-bottom: 2px; }
</style>
