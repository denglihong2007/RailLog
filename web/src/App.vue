<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ArrowRight, CheckCircle2, Code2, Download, Monitor, Route, Smartphone, TrainFront } from '@lucide/vue'

interface LatestRelease {
  version: string
  name: string
  releaseUrl: string
  windowsDownloadUrl: string | null
  androidDownloadUrl: string | null
  domesticDownloadName: string
  windowsDomesticDownloadUrl: string | null
  androidDomesticDownloadUrl: string | null
}

interface DownloadLinks {
  domesticDownloadName: string
  windowsDomesticDownloadUrl: string | null
  androidDomesticDownloadUrl: string | null
}

const fallbackReleaseUrl = 'https://github.com/denglihong2007/RailLog/releases/latest'
const release = ref<LatestRelease | null>(null)
const downloadLinks = ref<DownloadLinks | null>(null)
const releaseState = ref<'loading' | 'ready' | 'unavailable'>('loading')
const apiBase = (import.meta.env.VITE_API_URL ?? '').replace(/\/$/, '')
const downloadLanding = window.location.pathname.startsWith('/download') || new URLSearchParams(window.location.search).has('download')
const windowsUrl = computed(() => release.value?.windowsDownloadUrl ?? release.value?.releaseUrl ?? fallbackReleaseUrl)
const androidUrl = computed(() => release.value?.androidDownloadUrl ?? release.value?.releaseUrl ?? fallbackReleaseUrl)
const versionLabel = computed(() => release.value ? `最新版本 ${release.value.version}` : 'GitHub Releases')

onMounted(async () => {
  try {
    const response = await fetch(`${apiBase}/api/updates/downloads`)
    if (response.ok) downloadLinks.value = (await response.json()) as DownloadLinks
  } catch {
    downloadLinks.value = null
  }
  try {
    const response = await fetch(`${apiBase}/api/updates/latest`)
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    release.value = (await response.json()) as LatestRelease
    releaseState.value = 'ready'
  } catch {
    releaseState.value = 'unavailable'
  }
})
</script>

<template>
  <header class="site-header">
    <a class="brand" href="/" aria-label="RailLog 首页"><img src="/raillog-icon.png" alt="" /><span>RailLog 轨记</span></a>
    <nav aria-label="主导航">
      <a href="#download">下载</a>
      <a href="https://github.com/denglihong2007/RailLog" target="_blank" rel="noreferrer"><Code2 :size="19" /><span>GitHub</span></a>
    </nav>
  </header>

  <main>
    <section v-if="!downloadLanding" class="intro" aria-labelledby="page-title">
      <div class="intro-watermark" aria-hidden="true"></div>
      <div class="intro-content">
        <p class="eyebrow"><TrainFront :size="18" /> 铁路行程记录</p>
        <h1 id="page-title"><span>RailLog</span><span>轨记</span></h1>
        <p class="intro-copy">留存车票，整理足迹，把每一段铁路旅程汇成自己的出行档案。</p>
        <a class="primary-action" href="#download"><Download :size="20" />下载 RailLog<ArrowRight :size="18" /></a>
        <span class="platform-note">Windows · Android</span>
      </div>
    </section>

    <section id="download" class="download-section" aria-labelledby="download-title">
      <div class="section-heading">
        <div><p class="section-kicker">获取应用</p><h2 id="download-title">选择你的平台</h2></div>
        <p :class="['release-status', releaseState]"><CheckCircle2 v-if="releaseState === 'ready'" :size="17" />{{ releaseState === 'loading' ? '正在读取最新版本' : versionLabel }}</p>
      </div>
      <div class="download-grid">
        <article class="download-card windows-card">
          <Monitor :size="34" /><div><h3>Windows</h3><p>适用于 Windows 10 与 Windows 11</p></div>
          <div class="download-actions">
            <a :href="windowsUrl" target="_blank" rel="noreferrer"><Download :size="19" />官方下载</a>
            <a v-if="downloadLinks?.windowsDomesticDownloadUrl" class="secondary-download" :href="downloadLinks.windowsDomesticDownloadUrl" target="_blank" rel="noreferrer"><Download :size="19" />{{ downloadLinks.domesticDownloadName }}</a>
            <span v-else class="disabled-download"><Download :size="19" />国内网盘待更新</span>
          </div>
        </article>
        <article class="download-card android-card">
          <Smartphone :size="34" /><div><h3>Android</h3><p>下载 APK 安装包</p></div>
          <div class="download-actions">
            <a :href="androidUrl" target="_blank" rel="noreferrer"><Download :size="19" />官方下载</a>
            <a v-if="downloadLinks?.androidDomesticDownloadUrl" class="secondary-download" :href="downloadLinks.androidDomesticDownloadUrl" target="_blank" rel="noreferrer"><Download :size="19" />{{ downloadLinks.domesticDownloadName }}</a>
            <span v-else class="disabled-download"><Download :size="19" />国内网盘待更新</span>
          </div>
        </article>
      </div>
      <p v-if="releaseState === 'unavailable'" class="release-fallback">暂时无法读取版本信息，官方下载将前往开源发布页。</p>
    </section>

    <section class="product-band" aria-label="RailLog 功能概览">
      <div><Route :size="24" /><strong>行程档案</strong><span>车次、区间与经由线路</span></div>
      <div><TrainFront :size="24" /><strong>铁路足迹</strong><span>车站、线路与车型记录</span></div>
      <div><CheckCircle2 :size="24" /><strong>云端同步</strong><span>多设备保存个人行程</span></div>
    </section>
  </main>

  <footer>
    <div class="footer-brand"><img src="/raillog-icon.png" alt="" />RailLog 轨记</div>
    <p>GNU General Public License v3.0</p>
    <a href="https://github.com/denglihong2007/RailLog" target="_blank" rel="noreferrer">查看源代码 <ArrowRight :size="16" /></a>
  </footer>
</template>
