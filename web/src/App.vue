<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  Apple,
  ArrowRight,
  Award,
  BookOpen,
  CalendarClock,
  ChartColumn,
  CheckCircle2,
  CirclePlay,
  CloudUpload,
  Code2,
  Download,
  FileSpreadsheet,
  HeartHandshake,
  Laptop,
  Map,
  Monitor,
  Route,
  Search,
  Smartphone,
  Sparkles,
  Terminal,
  Ticket,
  TrainFront,
  UserRound,
  Users,
} from '@lucide/vue'
import TripLookup from './components/TripLookup.vue'
import TicketPdfDownloader from './components/TicketPdfDownloader.vue'
import UserLookup from './components/UserLookup.vue'

interface LatestRelease {
  version: string
}

const fallbackReleaseUrl = 'https://github.com/denglihong2007/RailLog/releases/latest'
const storageBaseUrl = 'https://raillog.cn-nb2.rains3.com'
const githubBaseUrl = 'https://github.com/denglihong2007/RailLog/releases/download'
const githubRepoUrl = 'https://github.com/denglihong2007/RailLog'
const microsoftStoreUrl = 'https://apps.microsoft.com/detail/9P2XGJRHLZXS'
const afdianUrl = 'https://afdian.com/a/CRSim'
const bilibiliUrl = 'https://space.bilibili.com/436826066'
const qqGroupUrl = 'https://qm.qq.com/q/pm5xqNdoE8'
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

const features = [
  {
    icon: Route,
    title: '行程档案',
    description: '记录车次、上下车站、乘车日期、席别、座位、票价与经由线路，备注也一并留存，把每一次出行都整理成可检索的档案。',
    tags: ['车次与经由', '席别票价', '行程备注'],
  },
  {
    icon: FileSpreadsheet,
    title: '多种方式导入',
    description: '支持 12306 账号、电子发票、邮箱购票通知、Excel 表格，以及车票照片识别，历史行程不必再一条条手动补录。',
    tags: ['12306', '电子发票', '邮箱', '车票识别'],
  },
  {
    icon: Map,
    title: '铁路足迹地图',
    description: '在地图上绘制乘过的车次与经由线路，按线路区分着色，走过的车站与区间一目了然。',
    tags: ['全国地图', '线路着色', '车站足迹'],
  },
  {
    icon: ChartColumn,
    title: '数据统计',
    description: '按里程、车站、车次、车型与时间维度汇总你的出行数据，还有全站排行榜，看看自己走过多少路。',
    tags: ['里程统计', '车型分布', '排行榜'],
  },
  {
    icon: Award,
    title: '成就与等级',
    description: '乘车记录会自动解锁各类成就并累积经验，等级与解锁记录都会保留，把每一次里程碑都记下来。',
    tags: ['自动解锁', '经验升级', '解锁记录'],
  },
  {
    icon: CalendarClock,
    title: '历史时刻表',
    description: '按历史时刻表批量补全到点、经由与里程，并清理重复行程，让早年录入的数据也能对得上当时的运行图。',
    tags: ['补全经由', '里程校准', '去重整理'],
  },
  {
    icon: Ticket,
    title: '火车票生成器',
    description: '把行程还原成票面样式的 PDF 火车票，可在线生成下载，也可以导出空白手账模板，做成自己的旅行纪念。',
    tags: ['PDF 车票', '在线下载', '手账模板'],
  },
  {
    icon: CloudUpload,
    title: '云端同步',
    description: '登录账户后，行程会在多台设备之间同步，换手机、换电脑都不必担心数据丢失。',
    tags: ['多端同步', '账户安全'],
  },
  {
    icon: Sparkles,
    title: '线路与车站评价',
    description: '对乘过的线路、到过的车站与坐过的车型发表评价，也能翻看其他旅客留下的记录。',
    tags: ['线路评价', '车站评价', '车型评价'],
  },
]

const ecosystem = [
  {
    icon: Search,
    title: '行程查询',
    description: '把行程分享给朋友，对方打开链接即可查看完整车次、经由与席位信息。',
    href: '/trip',
    label: '打开行程查询',
  },
  {
    icon: UserRound,
    title: '用户主页',
    description: '按用户 ID 查看公开主页、足迹与成就，认识更多同好。',
    href: '/user',
    label: '打开用户查询',
  },
  {
    icon: BookOpen,
    title: '开放 API',
    description: '完整的 REST 接口文档，可以自己写脚本或工具接入 RailLog 数据。',
    href: '/api-docs/',
    label: '阅读 API 文档',
  },
]

const community = [
  {
    icon: Code2,
    title: 'GitHub 开源',
    description: '源代码、Issue 与全部版本发布都在 GitHub，基于 GPL-3.0 开源。',
    href: githubRepoUrl,
    label: '查看仓库',
  },
  {
    icon: HeartHandshake,
    title: '爱发电',
    description: '如果 RailLog 对你有帮助，欢迎在爱发电支持项目的开发与维护。',
    href: afdianUrl,
    label: '前往支持',
    highlight: true,
  },
  {
    icon: CirclePlay,
    title: 'Bilibili',
    description: '关注 RailLog 的相关视频与开发动态。',
    href: bilibiliUrl,
    label: '前往关注',
  },
  {
    icon: Users,
    title: 'QQ 交流群',
    description: '群号 972024237，和其他旅客一起交流使用心得与建议。',
    href: qqGroupUrl,
    label: '加入群聊',
  },
]

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
      <a :href="utilityLanding || downloadLanding ? '/#features' : '#features'"><Sparkles :size="19" /><span>功能</span></a>
      <a href="/trip"><Search :size="19" /><span>行程查询</span></a>
      <a href="/user"><UserRound :size="19" /><span>用户查询</span></a>
      <a href="/api-docs/"><BookOpen :size="19" /><span>开放 API</span></a>
      <a class="download-nav" :href="utilityLanding ? '/download' : '#download'">下载</a>
      <a class="source-nav" :href="githubRepoUrl" target="_blank" rel="noreferrer" aria-label="GitHub"><Code2 :size="19" /><span>GitHub</span></a>
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
        <div class="intro-actions">
          <a class="primary-action" href="#download"><Download :size="20" />下载 RailLog<ArrowRight :size="18" /></a>
          <a class="secondary-action" href="#features">了解功能<ArrowRight :size="18" /></a>
        </div>
        <ul class="intro-highlights">
          <li><CheckCircle2 :size="16" />多平台客户端</li>
          <li><CheckCircle2 :size="16" />云端同步</li>
          <li><CheckCircle2 :size="16" />开源免费</li>
        </ul>
      </div>
    </section>

    <section v-if="!downloadLanding" id="features" class="features-section" aria-labelledby="features-title">
      <div class="section-heading">
        <div><p class="section-kicker">功能一览</p><h2 id="features-title">从录入到足迹，一站整理</h2></div>
        <p class="section-note">覆盖记录、导入、统计与分享的完整流程</p>
      </div>
      <div class="feature-grid">
        <article v-for="feature in features" :key="feature.title" class="feature-card">
          <span class="feature-icon"><component :is="feature.icon" :size="24" /></span>
          <h3>{{ feature.title }}</h3>
          <p>{{ feature.description }}</p>
          <div class="feature-tags">
            <span v-for="tag in feature.tags" :key="tag">{{ tag }}</span>
          </div>
        </article>
      </div>
    </section>

    <section v-if="!downloadLanding" class="ecosystem-section" aria-labelledby="ecosystem-title">
      <div class="section-heading">
        <div><p class="section-kicker">开放生态</p><h2 id="ecosystem-title">把数据带出应用之外</h2></div>
      </div>
      <div class="ecosystem-grid">
        <a v-for="item in ecosystem" :key="item.title" class="ecosystem-card" :href="item.href">
          <span class="feature-icon"><component :is="item.icon" :size="22" /></span>
          <div>
            <h3>{{ item.title }}</h3>
            <p>{{ item.description }}</p>
          </div>
          <span class="ecosystem-link">{{ item.label }}<ArrowRight :size="16" /></span>
        </a>
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

    <section v-if="!downloadLanding" id="community" class="community-section" aria-labelledby="community-title">
      <div class="section-heading">
        <div><p class="section-kicker">社群与支持</p><h2 id="community-title">开源，也需要你的支持</h2></div>
        <p class="section-note">RailLog 基于 GPL-3.0 开源，欢迎参与和反馈</p>
      </div>
      <div class="community-grid">
        <a
          v-for="item in community"
          :key="item.title"
          :class="['community-card', { highlight: item.highlight }]"
          :href="item.href"
          target="_blank"
          rel="noreferrer"
        >
          <span class="community-icon"><component :is="item.icon" :size="26" /></span>
          <div class="community-body">
            <h3>{{ item.title }}</h3>
            <p>{{ item.description }}</p>
          </div>
          <span class="community-link">{{ item.label }}<ArrowRight :size="16" /></span>
        </a>
      </div>
    </section>
    </template>
  </main>

  <footer>
    <div class="footer-brand"><img src="/raillog-icon.png" alt="" />RailLog 轨记</div>
    <p>GNU General Public License v3.0</p>
    <nav class="footer-links" aria-label="页脚导航">
      <a :href="githubRepoUrl" target="_blank" rel="noreferrer">源代码 <ArrowRight :size="16" /></a>
      <a :href="afdianUrl" target="_blank" rel="noreferrer">爱发电 <ArrowRight :size="16" /></a>
      <a :href="bilibiliUrl" target="_blank" rel="noreferrer">Bilibili <ArrowRight :size="16" /></a>
    </nav>
  </footer>
</template>
