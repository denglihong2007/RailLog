<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, type Component } from 'vue'
import {
  Award,
  CalendarClock,
  ClipboardList,
  Copy,
  Database,
  FileKey,
  LayoutDashboard,
  LogOut,
  Megaphone,
  MessageSquareText,
  ShieldCheck,
  TrainFront,
  Trophy,
  Users,
} from '@lucide/vue'
import { api, clearToken, readAdminName, readToken, storeAdminName, storeToken, type AdminSession } from './api'
import LoginView from './components/LoginView.vue'
import OverviewView from './components/OverviewView.vue'
import AnnouncementsView from './components/AnnouncementsView.vue'
import LeaderboardsView from './components/LeaderboardsView.vue'
import ReviewsView from './components/ReviewsView.vue'
import AchievementsView from './components/AchievementsView.vue'
import DuplicatesView from './components/DuplicatesView.vue'
import UsersView from './components/UsersView.vue'
import UserTripsView from './components/UserTripsView.vue'
import PdfDownloadView from './components/PdfDownloadView.vue'
import BackupView from './components/BackupView.vue'
import TimetableSyncView from './components/TimetableSyncView.vue'
import AuditLogView from './components/AuditLogView.vue'
import ToastHost from './components/ToastHost.vue'
import { toast } from './toast'

type ViewName =
  | 'overview'
  | 'announcements'
  | 'leaderboards'
  | 'reviews'
  | 'achievements'
  | 'duplicates'
  | 'users'
  | 'user-trips'
  | 'pdf-downloads'
  | 'backups'
  | 'timetable-sync'
  | 'audit-logs'

interface Route {
  view: ViewName
  userId?: string
  tripId?: number
  reviewQuery?: string
  entityType?: string
  level?: number
}

interface NavItem {
  view: ViewName
  label: string
  path: string
  icon: Component
}

interface NavGroup {
  label: string
  items: NavItem[]
}

const navGroups: NavGroup[] = [
  {
    label: '概览',
    items: [
      { view: 'overview', label: '概览', path: '/overview', icon: LayoutDashboard },
    ],
  },
  {
    label: '内容运营',
    items: [
      { view: 'announcements', label: '公告管理', path: '/announcements', icon: Megaphone },
      { view: 'leaderboards', label: '排行榜', path: '/leaderboards', icon: Trophy },
      { view: 'reviews', label: '评价管理', path: '/reviews', icon: MessageSquareText },
    ],
  },
  {
    label: '用户数据',
    items: [
      { view: 'achievements', label: '等级与成就', path: '/achievements', icon: Award },
      { view: 'duplicates', label: '重复行程', path: '/duplicates', icon: Copy },
      { view: 'users', label: '用户与行程', path: '/users', icon: Users },
    ],
  },
  {
    label: '系统运维',
    items: [
      { view: 'pdf-downloads', label: 'PDF 下载管理', path: '/pdf-downloads', icon: FileKey },
      { view: 'backups', label: '数据备份', path: '/backups', icon: Database },
      { view: 'timetable-sync', label: '时刻表同步', path: '/timetable-sync', icon: CalendarClock },
      { view: 'audit-logs', label: '操作日志', path: '/audit-logs', icon: ClipboardList },
    ],
  },
]

const titles: Record<ViewName, { title: string; subtitle: string }> = {
  overview: { title: '概览', subtitle: '站务数据、数据健康与最近动态' },
  announcements: { title: '公告管理', subtitle: '维护 App 主页轮播的系统公告' },
  leaderboards: { title: '排行榜', subtitle: '点选排行中的用户或行程，可直接定位并修正数据' },
  reviews: { title: '评价管理', subtitle: '检索、查看与删除用户评价' },
  achievements: { title: '等级与成就', subtitle: '用户等级分布与经验分界线、全站成就达成情况（成就只读）' },
  duplicates: { title: '重复行程', subtitle: '核对并清理同车次、同日期、同区间与票价的重复记录' },
  users: { title: '用户与行程', subtitle: '检索用户并管理其行程记录' },
  'user-trips': { title: '行程管理', subtitle: '编辑、新增或删除该用户的行程' },
  'pdf-downloads': { title: 'PDF 下载管理', subtitle: '管理网页端 PDF 下载密码与请求 Key' },
  backups: { title: '数据备份', subtitle: '生成、下载与清理数据库备份' },
  'timetable-sync': { title: '时刻表同步', subtitle: '查看与触发历史时刻表的每日同步' },
  'audit-logs': { title: '操作日志', subtitle: '管理员在后台执行的关键操作留痕' },
}

function parseRoute(): Route {
  const hash = window.location.hash.replace(/^#\/?/, '')
  const [path = '', search = ''] = hash.split('?')
  const params = new URLSearchParams(search)
  const parts = path.split('/').filter(Boolean)
  const first = parts[0]
  if (first === 'announcements') return { view: 'announcements' }
  if (first === 'leaderboards') return { view: 'leaderboards' }
  if (first === 'achievements') return { view: 'achievements' }
  if (first === 'duplicates') return { view: 'duplicates' }
  // 等级设置已并入「等级与成就」，旧书签直接改写为新的 hash。
  if (first === 'user-levels') {
    window.history.replaceState(null, '', '#/achievements')
    return { view: 'achievements' }
  }
  if (first === 'pdf-downloads') return { view: 'pdf-downloads' }
  if (first === 'backups') return { view: 'backups' }
  if (first === 'timetable-sync') return { view: 'timetable-sync' }
  if (first === 'audit-logs') return { view: 'audit-logs' }
  if (first === 'reviews') {
    return {
      view: 'reviews',
      reviewQuery: params.get('query') ?? '',
      entityType: params.get('entityType') ?? '',
    }
  }
  if (first === 'users' && parts[2] === 'trips' && parts[1]) {
    const tripId = Number(params.get('trip'))
    return {
      view: 'user-trips',
      userId: decodeURIComponent(parts[1]),
      tripId: Number.isInteger(tripId) && tripId > 0 ? tripId : undefined,
    }
  }
  if (first === 'users') {
    const rawLevel = params.get('level')
    const level = rawLevel === null ? undefined : Number(rawLevel)
    return {
      view: 'users',
      level: level !== undefined && Number.isInteger(level) && level >= 0 ? level : undefined,
    }
  }
  return { view: 'overview' }
}

const token = ref(readToken())
const adminName = ref(readAdminName())
const route = ref<Route>(parseRoute())
const loggingOut = ref(false)

const currentMeta = computed(() => titles[route.value.view])

function navigate(path: string): void {
  window.location.hash = `#${path}`
  route.value = parseRoute()
}

function handleHashChange(): void {
  route.value = parseRoute()
}

function handleUnauthorized(): void {
  token.value = ''
  adminName.value = ''
  clearToken()
  toast('登录已过期或没有管理员权限，请重新登录', 'error')
}

async function handleLogin(session: AdminSession): Promise<void> {
  storeToken(session.token)
  storeAdminName(session.displayName)
  token.value = session.token
  adminName.value = session.displayName
  if (!window.location.hash || window.location.hash === '#') {
    window.location.hash = '#/overview'
  }
  route.value = parseRoute()
  toast(`欢迎，${session.displayName}`)
}

async function handleLogout(): Promise<void> {
  if (loggingOut.value) return
  loggingOut.value = true
  try {
    await api.logout()
  } catch {
    // 服务端会话可能已过期，仍然清掉本地令牌。
  } finally {
    loggingOut.value = false
    token.value = ''
    adminName.value = ''
    clearToken()
    toast('已退出登录', 'info')
  }
}

onMounted(() => {
  window.addEventListener('hashchange', handleHashChange)
  window.addEventListener('admin:unauthorized', handleUnauthorized)
})

onBeforeUnmount(() => {
  window.removeEventListener('hashchange', handleHashChange)
  window.removeEventListener('admin:unauthorized', handleUnauthorized)
})
</script>

<template>
  <ToastHost />
  <LoginView v-if="!token" @logged-in="handleLogin" />

  <div v-else class="app-shell">
    <aside class="app-sidebar">
      <div class="sidebar-brand">
        <img src="/raillog-icon.png" alt="" />
        <div>
          <strong>RailLog</strong>
          <span>管理后台</span>
        </div>
      </div>

      <nav class="sidebar-nav" aria-label="后台导航">
        <div v-for="group in navGroups" :key="group.label" class="nav-group">
          <p class="nav-group-label">{{ group.label }}</p>
          <button
            v-for="item in group.items"
            :key="item.view"
            type="button"
            :class="['nav-item', { active: route.view === item.view || (item.view === 'users' && route.view === 'user-trips') }]"
            @click="navigate(item.path)"
          >
            <component :is="item.icon" :size="19" />
            <span>{{ item.label }}</span>
          </button>
        </div>
      </nav>

      <div class="sidebar-foot">
        <button type="button" class="nav-item logout" :disabled="loggingOut" @click="handleLogout">
          <LogOut :size="19" />
          <span>{{ loggingOut ? '正在退出…' : '退出登录' }}</span>
        </button>
        <p class="sidebar-note"><ShieldCheck :size="14" /> 仅限授权管理员使用</p>
      </div>
    </aside>

    <div class="app-main">
      <header class="topbar">
        <div>
          <p class="topbar-eyebrow"><TrainFront :size="15" /> RailLog Admin</p>
          <h1>{{ currentMeta.title }}</h1>
          <p class="topbar-subtitle">{{ currentMeta.subtitle }}</p>
        </div>
        <div class="topbar-side">
          <span class="admin-chip"><ShieldCheck :size="15" /> {{ adminName || '管理员' }}</span>
        </div>
      </header>

      <main class="page">
        <OverviewView
          v-if="route.view === 'overview'"
          @navigate="navigate"
          @open-user="(id) => navigate(`/users/${id}/trips`)"
          @open-trip="(userId, tripId) => navigate(`/users/${userId}/trips?trip=${tripId}`)"
        />
        <AnnouncementsView v-else-if="route.view === 'announcements'" />
        <LeaderboardsView
          v-else-if="route.view === 'leaderboards'"
          @open-user="(id) => navigate(`/users/${id}/trips`)"
          @open-trip="(userId, tripId) => navigate(`/users/${userId}/trips?trip=${tripId}`)"
          @open-reviews="(type, name) => navigate(`/reviews?entityType=${encodeURIComponent(type)}&query=${encodeURIComponent(name)}`)"
        />
        <ReviewsView
          v-else-if="route.view === 'reviews'"
          :initial-query="route.reviewQuery"
          :initial-entity-type="route.entityType"
          @open-user="(id) => navigate(`/users/${id}/trips`)"
          @open-trip="(userId, tripId) => navigate(`/users/${userId}/trips?trip=${tripId}`)"
        />
        <AchievementsView
          v-else-if="route.view === 'achievements'"
          @open-user="(id) => navigate(`/users/${id}/trips`)"
          @open-trip="(userId, tripId) => navigate(`/users/${userId}/trips?trip=${tripId}`)"
          @open-level="(level) => navigate(`/users?level=${level}`)"
        />
        <DuplicatesView
          v-else-if="route.view === 'duplicates'"
          @back="navigate('/overview')"
          @open-user="(id) => navigate(`/users/${id}/trips`)"
          @open-trip="(userId, tripId) => navigate(`/users/${userId}/trips?trip=${tripId}`)"
        />
        <UsersView
          v-else-if="route.view === 'users'"
          :key="`level:${route.level ?? ''}`"
          :initial-level="route.level ?? null"
          @open-user="(id) => navigate(`/users/${id}/trips`)"
          @open-trip="(userId, tripId) => navigate(`/users/${userId}/trips?trip=${tripId}`)"
        />
        <UserTripsView
          v-else-if="route.view === 'user-trips' && route.userId"
          :key="`${route.userId}:${route.tripId ?? ''}`"
          :user-id="route.userId"
          :focus-trip-id="route.tripId"
          @back="navigate('/users')"
        />
        <PdfDownloadView v-else-if="route.view === 'pdf-downloads'" />
        <BackupView v-else-if="route.view === 'backups'" />
        <TimetableSyncView v-else-if="route.view === 'timetable-sync'" />
        <AuditLogView v-else-if="route.view === 'audit-logs'" />
      </main>
    </div>
  </div>
</template>
