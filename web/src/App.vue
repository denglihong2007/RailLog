<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Apple, ArrowRight, BookOpen, CheckCircle2, Code2, Download, Laptop, Monitor, Route, Search, Smartphone, Terminal, TrainFront, TriangleAlert, UserRound } from '@lucide/vue'
import TripLookup from './components/TripLookup.vue'
import TicketPdfDownloader from './components/TicketPdfDownloader.vue'
import UserLookup from './components/UserLookup.vue'

interface LatestRelease {
  version: string
}

const fallbackReleaseUrl = 'https://github.com/denglihong2007/RailLog/releases/latest'
const storageBaseUrl = 'https://raillog.cn-nb2.rains3.com'
const githubBaseUrl = 'https://github.com/denglihong2007/RailLog/releases/download'
const microsoftStoreUrl = 'https://apps.microsoft.com/detail/9P2XGJRHLZXS'
const release = ref<LatestRelease | null>(null)
const releaseState = ref<'loading' | 'ready' | 'unavailable'>('loading')
const apiBase = (import.meta.env.VITE_API_URL ?? '').replace(/\/$/, '')
const pageParams = new URLSearchParams(window.location.search)
// API 文档已迁到独立静态站 /api-docs/。兼容旧链接：
// 带 ?api-docs=1 的地址与不带结尾斜杠的 /api-docs 都重定向过去。
if (pageParams.has('api-docs')) {
  window.location.replace(`/api-docs/${window.location.hash}`)
} else if (window.location.pathname === '/api-docs') {
  window.location.replace('/api-docs/')
}
const tripLanding = window.location.pathname.startsWith('/trip') || pageParams.has('trip')
const ticketPdfLanding = window.location.pathname.startsWith('/ticket-pdf') || pageParams.has('ticket-pdf')
const userLanding = window.location.pathname.startsWith('/user') || pageParams.has('user')
const utilityLanding = tripLanding || ticketPdfLanding || userLanding
const downloadLanding = !utilityLanding && (window.location.pathname.startsWith('/download') || pageParams.has('download'))
const releaseVersion = computed(() => release.value?.version.replace(/^v/, '') ?? '')
const assetName = (suffix: string) => `raillog-v${releaseVersion.value}-${suffix}`
// 官方下载默认走对象存储，GitHub Releases 作为备用入口保留。
const storageUrl = (suffix: string) => release.value
  ? `${storageBaseUrl}/v${releaseVersion.value}/${assetName(suffix)}`
  : fallbackReleaseUrl
const githubUrl = (suffix: string) => release.value
  ? `${githubBaseUrl}/v${releaseVersion.value}/${assetName(suffix)}`
  : fallbackReleaseUrl
const androidUrl = computed(() => storageUrl('android-arm64-v8a.apk'))
const macosUrl = computed(() => storageUrl('macos-arm64.zip'))
const linuxUrl = computed(() => storageUrl('linux-x64.tar.gz'))
const iosUrl = computed(() => storageUrl('ios.ipa'))
const versionLabel = computed(() => release.value ? `最新版本 ${release.value.version}` : 'GitHub Releases')

onMounted(async () => {
  if (utilityLanding) return
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
      <a href="/trip"><Search :size="19" /><span>行程查询</span></a>
      <a href="/user"><UserRound :size="19" /><span>用户查询</span></a>
      <a href="/api-docs/"><BookOpen :size="19" /><span>开放 API</span></a>
      <a class="download-nav" :href="utilityLanding ? '/download' : '#download'">下载</a>
      <a class="source-nav" href="https://github.com/denglihong2007/RailLog" target="_blank" rel="noreferrer" aria-label="GitHub"><Code2 :size="19" /><span>GitHub</span></a>
    </nav>
  </header>

  <main>
    <TicketPdfDownloader v-if="ticketPdfLanding" :api-base="apiBase" />
    <TripLookup v-else-if="tripLanding" :api-base="apiBase" />
    <UserLookup v-else-if="userLanding" :api-base="apiBase" />
    <template v-else>
    <section v-if="!downloadLanding" class="intro" aria-labelledby="page-title">
      <div class="intro-watermark" aria-hidden="true"></div>
      <div class="intro-content">
        <p class="eyebrow"><TrainFront :size="18" /> 铁路行程记录</p>
        <h1 id="page-title"><span>RailLog</span><span>轨记</span></h1>
        <p class="intro-copy">留存车票，整理足迹，把每一段铁路旅程汇成自己的出行档案。</p>
        <a class="primary-action" href="#download"><Download :size="20" />下载 RailLog<ArrowRight :size="18" /></a>
      </div>
    </section>

    <section id="download" class="download-section" aria-labelledby="download-title">
      <div class="upgrade-alert" role="alert">
        <TriangleAlert :size="25" aria-hidden="true" />
        <div>
          <strong>重要更新提示</strong>
          <p>如果之前使用过 1.0.0 版本，请先清除应用数据，再更新到更高版本。</p>
        </div>
      </div>
      <div class="section-heading">
        <div><p class="section-kicker">获取应用</p><h2 id="download-title">选择你的平台</h2></div>
        <p :class="['release-status', releaseState]"><CheckCircle2 v-if="releaseState === 'ready'" :size="17" />{{ releaseState === 'loading' ? '正在读取最新版本' : versionLabel }}</p>
      </div>
      <div class="download-grid">
        <article class="download-card windows-card">
          <Monitor :size="34" /><div><h3>Windows</h3><p>适用于 Windows 10 与 Windows 11</p></div>
          <div class="download-actions">
            <a :href="microsoftStoreUrl" target="_blank" rel="noopener noreferrer"><Download :size="19" />官方下载</a>
            <a class="secondary-download" :href="githubUrl('windows-x64.zip')" target="_blank" rel="noreferrer"><Code2 :size="19" />GitHub</a>
          </div>
        </article>
        <article class="download-card android-card">
          <Smartphone :size="34" /><div><h3>Android</h3><p>下载 APK 安装包</p></div>
          <div class="download-actions">
            <a :href="androidUrl" target="_blank" rel="noreferrer"><Download :size="19" />官方下载</a>
            <a class="secondary-download" :href="githubUrl('android-arm64-v8a.apk')" target="_blank" rel="noreferrer"><Code2 :size="19" />GitHub</a>
          </div>
        </article>
        <article class="download-card">
          <Apple :size="34" /><div><h3>macOS</h3><p>适用于 Apple Silicon</p></div>
          <div class="download-actions"><a :href="macosUrl" target="_blank" rel="noreferrer"><Download :size="19" />官方下载</a><a class="secondary-download" :href="githubUrl('macos-arm64.zip')" target="_blank" rel="noreferrer"><Code2 :size="19" />GitHub</a></div>
        </article>
        <article class="download-card">
          <Terminal :size="34" /><div><h3>Linux</h3><p>x64 桌面版，下载后解压运行</p></div>
          <div class="download-actions"><a :href="linuxUrl" target="_blank" rel="noreferrer"><Download :size="19" />官方下载</a><a class="secondary-download" :href="githubUrl('linux-x64.tar.gz')" target="_blank" rel="noreferrer"><Code2 :size="19" />GitHub</a></div>
        </article>
        <article class="download-card">
          <Laptop :size="34" /><div><h3>iOS</h3><p>未签名 IPA，适合开发者部署</p></div>
          <div class="download-actions"><a :href="iosUrl" target="_blank" rel="noreferrer"><Download :size="19" />官方下载</a><a class="secondary-download" :href="githubUrl('ios.ipa')" target="_blank" rel="noreferrer"><Code2 :size="19" />GitHub</a></div>
        </article>
      </div>
      <p v-if="releaseState === 'unavailable'" class="release-fallback">暂时无法读取版本信息，官方下载将前往开源发布页。</p>
    </section>

    <section class="product-band" aria-label="RailLog 功能概览">
      <div><Route :size="24" /><strong>行程档案</strong><span>车次、区间与经由线路</span></div>
      <div><TrainFront :size="24" /><strong>铁路足迹</strong><span>车站、线路与车型记录</span></div>
      <div><CheckCircle2 :size="24" /><strong>云端同步</strong><span>多设备保存个人行程</span></div>
    </section>
    </template>
  </main>

  <footer>
    <div class="footer-brand"><img src="/raillog-icon.png" alt="" />RailLog 轨记</div>
    <p>GNU General Public License v3.0</p>
    <a href="https://github.com/denglihong2007/RailLog" target="_blank" rel="noreferrer">查看源代码 <ArrowRight :size="16" /></a>
  </footer>
</template>
