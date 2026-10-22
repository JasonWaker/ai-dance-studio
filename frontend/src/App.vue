<template>
  <el-container style="height: 100vh">
    <el-aside width="220px" class="aside">
      <div class="logo">
        <el-icon size="22" color="#fff"><VideoCamera /></el-icon>
        <span>AI 卡点舞工作台</span>
      </div>
      <el-menu :default-active="route.path" router class="menu">
        <el-menu-item index="/generate"><el-icon><VideoCamera /></el-icon><b>AI 视频生成</b></el-menu-item>
        <el-menu-item index="/jobs"><el-icon><List /></el-icon>任务中心</el-menu-item>
        <el-menu-item index="/models"><el-icon><Cpu /></el-icon>模型中心</el-menu-item>
        <el-divider style="margin: 8px 16px; border-color: rgba(255,255,255,.12)" />
        <el-menu-item index="/dashboard"><el-icon><DataAnalysis /></el-icon>数据看板</el-menu-item>
        <el-menu-item index="/topics"><el-icon><TrendCharts /></el-icon>选题中心</el-menu-item>
        <el-menu-item index="/assets"><el-icon><Collection /></el-icon>资产库</el-menu-item>
        <el-menu-item index="/tasks"><el-icon><VideoPlay /></el-icon>旧任务台</el-menu-item>
        <el-menu-item index="/review"><el-icon><Checked /></el-icon>质检台</el-menu-item>
        <el-menu-item index="/prompts"><el-icon><MagicStick /></el-icon>提示词中心</el-menu-item>
        <el-menu-item index="/videos"><el-icon><FolderOpened /></el-icon>成品库</el-menu-item>
        <el-menu-item index="/publish"><el-icon><Promotion /></el-icon>发布助手</el-menu-item>
      </el-menu>
    </el-aside>

    <el-container>
      <el-header class="header">
        <div class="page-title">{{ route.meta.title || '工作台' }}</div>
        <div class="header-right">
          <el-tag v-if="health.mockMode" type="warning" size="small">模拟模式（未配置密钥时自动模拟生成）</el-tag>
          <el-tooltip v-for="p in providerTags" :key="p.name" :content="p.title" placement="bottom">
            <el-tag :type="p.ok ? 'success' : 'info'" size="small">{{ p.name }}: {{ p.ok ? '已配置' : '未配置' }}</el-tag>
          </el-tooltip>
          <el-button size="small" :icon="Refresh" circle @click="loadHealth" />
        </div>
      </el-header>
      <el-main class="main">
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { Refresh } from '@element-plus/icons-vue'
import { HealthApi } from '@/api'

const route = useRoute()
const health = ref({ providers: {}, mockMode: false })

const providerTags = computed(() => {
  const p = health.value.providers || {}
  return [
    { name: 'Seedance', ok: !!p.seedance?.configured, title: `Seedance ${p.seedance?.model || ''} 密钥已配置` },
    { name: '可灵', ok: !!p.kling?.configured, title: '可灵 Kling 密钥已配置' },
    { name: '即梦', ok: !!p.jimeng?.configured, title: '即梦密钥已配置' }
  ]
})

async function loadHealth() {
  try {
    health.value = await HealthApi.get()
  } catch (e) {
    health.value = { providers: {}, mockMode: false }
  }
}
onMounted(loadHealth)
</script>

<style>
body { margin: 0; font-family: -apple-system, 'PingFang SC', 'Microsoft YaHei', sans-serif; background: #f5f7fa; }
.aside { background: #001529; }
.aside .logo {
  display: flex; align-items: center; gap: 8px;
  color: #fff; font-weight: 600; font-size: 15px;
  padding: 16px 18px;
}
.menu { border-right: none; background: transparent; }
.menu .el-menu-item { color: rgba(255,255,255,.68); }
.menu .el-menu-item:hover { background: rgba(255,255,255,.08); color: #fff; }
.menu .el-menu-item.is-active { background: #2563eb; color: #fff; }
.header {
  display: flex; align-items: center; justify-content: space-between;
  background: #fff; border-bottom: 1px solid #e5e7eb;
}
.header .page-title { font-size: 16px; font-weight: 600; }
.header .header-right { display: flex; align-items: center; gap: 8px; }
.main { padding: 16px; overflow: auto; }
</style>
