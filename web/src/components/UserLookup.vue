<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  AlertCircle,
  ArrowRight,
  AtSign,
  Award,
  CalendarDays,
  CircleUserRound,
  MapPin,
  Route,
  Search,
  TrainFront,
  WalletCards,
} from '@lucide/vue'

interface PublicUser {
  id: string
  displayName: string
  avatarUrl: string | null
  bio: string | null
  email: string | null
}

interface PublicTrip {
  ticketId: number
  createdAt: string
  trainNumber: string
  fromStation: string
  toStation: string
  departureTime: string | null
  arrivalTime: string | null
  mileageKm: number
  price: number
  isRailTrip: boolean
}

interface Achievement {
  id: string
  icon: string
  title: string
  description: string
  status: string
}

interface PublicUserDashboard {
  user: PublicUser
  trips: PublicTrip[]
  achievements: {
    totalUserCount: number
    achievements: Achievement[]
  }
}

const props = defineProps<{ apiBase: string }>()
const initialId = new URLSearchParams(window.location.search).get('id') ?? ''
const userId = ref(initialId)
const submittedId = ref('')
const dashboard = ref<PublicUserDashboard | null>(null)
const state = ref<'idle' | 'loading' | 'ready' | 'not-found' | 'error'>('idle')
const avatarFailed = ref(false)
let activeRequest = 0

const achievementIconCodepoints: Record<string, number> = {
  restaurant_outlined: 0xf316,
  airline_seat_recline_extra_outlined: 0xee5c,
  transfer_within_a_station: 0xe677,
  schedule_outlined: 0xf339,
  local_fire_department: 0xe392,
  calendar_month_outlined: 0xf051f,
  looks_one_outlined: 0xf19e,
  looks_two_outlined: 0xf1a0,
  looks_3_outlined: 0xf19a,
  palette_outlined: 0xf24f,
  train_outlined: 0xf458,
  checklist_outlined: 0xef4a,
  accessibility_new: 0xe03d,
  collections_bookmark_outlined: 0xef69,
  nightlight_outlined: 0xf214,
  airline_seat_recline_normal: 0xe06c,
  location_on_outlined: 0xf193,
  route_outlined: 0xf0658,
  connecting_airports_outlined: 0xf05cf,
  directions_boat_outlined: 0xefc2,
  engineering_outlined: 0xf022,
  swap_vert: 0xe627,
  swap_horiz: 0xe625,
  speed_outlined: 0xf3c3,
  slow_motion_video_outlined: 0xf3a4,
  directions_bike_outlined: 0xefc0,
  flash_on_outlined: 0xf080,
  language_outlined: 0xf14f,
  map_outlined: 0xf1ae,
  gps_fixed_outlined: 0xf0c9,
  u_turn_left_outlined: 0xf0689,
  device_thermostat_outlined: 0xefb8,
  bolt_outlined: 0xeedd,
  flag_outlined: 0xf07b,
  wb_sunny_outlined: 0xf4bc,
  vertical_align_bottom_outlined: 0xf47e,
  history_edu_outlined: 0xf101,
  alt_route_outlined: 0xee71,
  thunderstorm_outlined: 0xf071b,
  pin_outlined: 0xf2aa,
  bedtime_outlined: 0xeecb,
  multiple_stop_outlined: 0xf1f9,
  landscape_outlined: 0xf14e,
  explore_outlined: 0xf037,
  loop: 0xe3bb,
  auto_awesome_outlined: 0xeea9,
  work_outline: 0xe6f4,
  emoji_events_outlined: 0xf01a,
  celebration_outlined: 0xef38,
  redeem_outlined: 0xf2f4,
  luggage_outlined: 0xf1a7,
  directions_walk_outlined: 0xefd0,
  account_balance_outlined: 0xee32,
  ac_unit_outlined: 0xee29,
  filter_3_outlined: 0xf060,
  water_drop_outlined: 0xf0695,
  public_outlined: 0xf2d4,
  precision_manufacturing_outlined: 0xf2c7,
  directions_railway_outlined: 0xefca,
  format_list_numbered_outlined: 0xf0a6,
  favorite_outline: 0xe25c,
  visibility_outlined: 0xf4a1,
  currency_yen: 0xf04e2,
  timer_outlined: 0xf44a,
}

const userInitial = computed(() => dashboard.value?.user.displayName.trim().charAt(0) || '旅')
const railwayTrips = computed(() => dashboard.value?.trips.filter((trip) => trip.isRailTrip) ?? [])
const totalMileage = computed(() => railwayTrips.value.reduce((sum, trip) => sum + trip.mileageKm, 0))
const totalSpending = computed(() => railwayTrips.value.reduce((sum, trip) => sum + trip.price, 0))
const unlockedAchievements = computed(() => dashboard.value?.achievements.achievements.filter((item) => item.status === 'unlocked') ?? [])

onMounted(() => {
  document.title = '用户查询 - RailLog 轨记'
  if (initialId.trim()) void queryUser(initialId.trim())
})

function submit(): void {
  const normalized = userId.value.trim()
  if (!normalized) {
    submittedId.value = ''
    dashboard.value = null
    state.value = 'error'
    return
  }
  void queryUser(normalized)
}

async function queryUser(id: string): Promise<void> {
  const requestId = ++activeRequest
  userId.value = id
  submittedId.value = id
  dashboard.value = null
  avatarFailed.value = false
  state.value = 'loading'
  window.history.replaceState(null, '', `/?user=1&id=${encodeURIComponent(id)}`)
  try {
    const response = await fetch(`${props.apiBase}/api/users/${encodeURIComponent(id)}`)
    if (requestId !== activeRequest) return
    if (response.status === 404) {
      state.value = 'not-found'
      return
    }
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    dashboard.value = (await response.json()) as PublicUserDashboard
    state.value = 'ready'
  } catch {
    if (requestId === activeRequest) state.value = 'error'
  }
}

function tripUrl(ticketId: number): string {
  return `/trip?id=${encodeURIComponent(ticketId)}`
}

function achievementIcon(key: string): string {
  return String.fromCodePoint(achievementIconCodepoints[key] ?? 0xf01a)
}

function parseDate(value: string | null): Date | null {
  if (!value) return null
  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? null : parsed
}

function pad(value: number): string {
  return value.toString().padStart(2, '0')
}

function formatDate(value: string | null): string {
  const date = parseDate(value)
  return date ? `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` : '日期未记录'
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat('zh-CN', { maximumFractionDigits: 1 }).format(value)
}
</script>

<template>
  <section class="user-page" aria-labelledby="user-title">
    <div class="user-heading">
      <p class="user-kicker"><CircleUserRound :size="18" /> 公开用户</p>
      <h1 id="user-title">用户查询</h1>
      <p>输入用户 ID，查看公开资料、铁路足迹与成就。</p>
    </div>

    <form class="user-form" role="search" @submit.prevent="submit">
      <label for="user-id">用户 ID</label>
      <div class="user-input-row">
        <div class="user-input">
          <AtSign :size="20" aria-hidden="true" />
          <input id="user-id" v-model="userId" autocomplete="off" placeholder="输入完整用户 ID" />
        </div>
        <button type="submit" :disabled="state === 'loading'"><Search :size="19" />{{ state === 'loading' ? '查询中' : '查询' }}</button>
      </div>
    </form>

    <div v-if="state === 'idle'" class="user-empty">
      <CircleUserRound :size="38" /><strong>等待查询</strong><span>用户公开信息将在这里显示</span>
    </div>
    <div v-else-if="state === 'loading'" class="user-empty" aria-live="polite">
      <span class="loading-indicator" aria-hidden="true"></span><strong>正在读取用户信息</strong><span>{{ submittedId }}</span>
    </div>
    <div v-else-if="state === 'not-found'" class="user-empty error-state" role="status">
      <AlertCircle :size="38" /><strong>未找到该用户</strong><span>请检查用户 ID 是否完整</span>
    </div>
    <div v-else-if="state === 'error'" class="user-empty error-state" role="alert">
      <AlertCircle :size="38" /><strong>{{ submittedId ? '暂时无法读取用户信息' : '请输入用户 ID' }}</strong><span>{{ submittedId ? '请稍后重试' : '用户 ID 不能为空' }}</span>
    </div>

    <div v-else-if="dashboard" class="user-result" aria-live="polite">
      <section class="profile-panel" aria-label="用户资料">
        <img v-if="dashboard.user.avatarUrl && !avatarFailed" :src="dashboard.user.avatarUrl" alt="" @error="avatarFailed = true" />
        <span v-else class="profile-initial" aria-hidden="true">{{ userInitial }}</span>
        <div class="profile-copy">
          <h2>{{ dashboard.user.displayName }}</h2>
          <p>{{ dashboard.user.bio?.trim() || '这位用户暂未填写个人简介。' }}</p>
          <a v-if="dashboard.user.email" :href="`mailto:${dashboard.user.email}`">{{ dashboard.user.email }}</a>
          <span class="profile-id">ID {{ dashboard.user.id }}</span>
        </div>
      </section>

      <section class="user-metrics" aria-label="铁路行程汇总">
        <div><TrainFront :size="22" /><span>铁路行程</span><strong>{{ railwayTrips.length }}</strong></div>
        <div><Route :size="22" /><span>累计里程</span><strong>{{ formatNumber(totalMileage) }} km</strong></div>
        <div><WalletCards :size="22" /><span>累计票价</span><strong>¥{{ formatNumber(totalSpending) }}</strong></div>
        <div><Award :size="22" /><span>已解锁成就</span><strong>{{ unlockedAchievements.length }}</strong></div>
      </section>

      <section class="achievement-section" aria-labelledby="achievement-title">
        <div class="result-heading"><div><p>个人荣誉</p><h2 id="achievement-title">已解锁成就</h2></div><span>{{ unlockedAchievements.length }} 项</span></div>
        <p v-if="unlockedAchievements.length === 0" class="no-results">尚未解锁公开成就</p>
        <ul v-else class="achievement-list">
          <li v-for="item in unlockedAchievements" :key="item.id"><span class="material-icon" aria-hidden="true">{{ achievementIcon(item.icon) }}</span><div><strong>{{ item.title }}</strong><p>{{ item.description }}</p></div></li>
        </ul>
      </section>

      <section class="trip-list-section" aria-labelledby="trip-list-title">
        <div class="result-heading"><div><p>公开记录</p><h2 id="trip-list-title">全部行程</h2></div><span>{{ dashboard.trips.length }} 条</span></div>
        <p v-if="dashboard.trips.length === 0" class="no-results">该用户还没有公开行程</p>
        <ol v-else class="user-trip-list">
          <li v-for="trip in dashboard.trips" :key="trip.ticketId">
            <a :href="tripUrl(trip.ticketId)">
              <div class="trip-date"><CalendarDays :size="17" /><time>{{ formatDate(trip.departureTime ?? trip.createdAt) }}</time></div>
              <div class="trip-main"><strong>{{ trip.trainNumber || (trip.isRailTrip ? '铁路行程' : '其他行程') }}</strong><p><MapPin :size="15" />{{ trip.fromStation }} → {{ trip.toStation }}</p></div>
              <span class="trip-mileage">{{ trip.mileageKm > 0 ? `${formatNumber(trip.mileageKm)} km` : '里程未记录' }}</span>
              <ArrowRight :size="19" aria-hidden="true" />
            </a>
          </li>
        </ol>
      </section>
    </div>
  </section>
</template>

<style scoped>
.user-page { width:min(960px,100%); min-height:calc(100svh - 68px); margin:0 auto; padding:54px 20px 72px; }
.user-heading { margin-bottom:28px; }
.user-kicker { margin:0 0 8px; display:flex; align-items:center; gap:8px; color:var(--brand); font-weight:700; }
.user-heading h1 { margin:0; display:block; font-size:clamp(34px,6vw,52px); line-height:1.15; }
.user-heading>p:last-child { margin:12px 0 0; color:var(--muted); font-size:17px; }
.user-form { padding:20px; border:1px solid var(--line); border-radius:8px; background:var(--surface-low); }
.user-form>label { display:block; margin-bottom:8px; font-weight:700; }
.user-input-row { display:grid; grid-template-columns:minmax(0,1fr) auto; gap:10px; }
.user-input { min-width:0; min-height:50px; padding:0 14px; display:flex; align-items:center; gap:10px; border:1px solid var(--line); border-radius:7px; background:var(--surface); }
.user-input:focus-within { border-color:var(--brand); outline:2px solid color-mix(in srgb,var(--brand) 22%,transparent); }
.user-input svg { flex:0 0 auto; color:var(--muted); }
.user-input input { width:100%; min-width:0; border:0; outline:0; background:transparent; color:var(--ink); font:inherit; font-size:16px; }
.user-form button { min-width:110px; min-height:50px; padding:0 18px; display:inline-flex; align-items:center; justify-content:center; gap:8px; border:0; border-radius:7px; background:var(--brand); color:#fff; font:inherit; font-weight:700; cursor:pointer; }
.user-form button:hover:not(:disabled) { background:var(--brand-dark); }
.user-form button:disabled { opacity:.65; cursor:wait; }
.user-empty { min-height:280px; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:8px; color:var(--muted); text-align:center; }
.user-empty svg { margin-bottom:4px; color:var(--brand); }
.user-empty strong { color:var(--ink); font-size:18px; }
.loading-indicator { width:32px; height:32px; margin-bottom:8px; border:3px solid var(--line); border-top-color:var(--brand); border-radius:50%; animation:spin .8s linear infinite; }
.user-result { margin-top:22px; display:grid; gap:22px; }
.profile-panel { min-width:0; padding:22px; display:grid; grid-template-columns:82px minmax(0,1fr); gap:18px; align-items:center; border:1px solid var(--line); border-radius:8px; background:var(--surface); }
.profile-panel img,.profile-initial { width:82px; height:82px; border-radius:50%; object-fit:cover; }
.profile-initial { display:grid; place-items:center; background:var(--surface-low); color:var(--brand); font-size:30px; font-weight:750; }
.profile-copy { min-width:0; }
.profile-copy h2 { margin:0; font-size:25px; }
.profile-copy p { margin:6px 0 10px; color:var(--muted); line-height:1.6; overflow-wrap:anywhere; }
.profile-copy a { display:inline-flex; align-items:center; gap:5px; color:var(--blue); overflow-wrap:anywhere; }
.profile-id { display:block; margin-top:8px; color:var(--muted); font-size:12px; overflow-wrap:anywhere; }
.user-metrics { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); border-block:1px solid var(--line); }
.user-metrics div { min-width:0; padding:18px 16px; display:grid; grid-template-columns:auto minmax(0,1fr); gap:5px 9px; align-items:center; border-left:1px solid var(--line); }
.user-metrics div:first-child { border-left:0; }
.user-metrics svg { grid-row:1/3; color:var(--brand); }
.user-metrics span { color:var(--muted); font-size:12px; }
.user-metrics strong { overflow-wrap:anywhere; }
.achievement-section,.trip-list-section { min-width:0; }
.result-heading { margin-bottom:14px; display:flex; align-items:end; justify-content:space-between; gap:16px; }
.result-heading p { margin:0 0 3px; color:var(--brand); font-size:13px; font-weight:700; }
.result-heading h2 { margin:0; font-size:22px; }
.result-heading>span { color:var(--muted); font-size:14px; }
.achievement-list { margin:0; padding:0; display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:10px; list-style:none; }
.achievement-list li { min-width:0; padding:14px; display:grid; grid-template-columns:36px minmax(0,1fr); gap:10px; align-items:center; background:var(--surface-low); border-radius:8px; }
.achievement-list li>span { display:grid; place-items:center; color:var(--brand); font-size:23px; }
.achievement-list strong { display:block; }
.achievement-list p { margin:3px 0 0; color:var(--muted); font-size:13px; line-height:1.5; }
.user-trip-list { margin:0; padding:0; border-top:1px solid var(--line); list-style:none; }
.user-trip-list li { border-bottom:1px solid var(--line); }
.user-trip-list a { min-width:0; padding:16px 4px; display:grid; grid-template-columns:145px minmax(0,1fr) auto auto; gap:16px; align-items:center; }
.user-trip-list a:hover strong { color:var(--brand); }
.trip-date { display:flex; align-items:center; gap:7px; color:var(--muted); font-size:13px; }
.trip-main { min-width:0; }
.trip-main strong { display:block; transition:color .15s; }
.trip-main p { margin:4px 0 0; display:flex; align-items:center; gap:5px; color:var(--muted); font-size:14px; overflow-wrap:anywhere; }
.trip-mileage { color:var(--muted); font-size:14px; white-space:nowrap; }
.user-trip-list a>svg { color:var(--muted); }
.no-results { margin:0; padding:32px 16px; color:var(--muted); background:var(--surface-low); text-align:center; }
@keyframes spin { to { transform:rotate(360deg); } }
@media (max-width:760px) {
  .user-metrics { grid-template-columns:repeat(2,minmax(0,1fr)); }
  .user-metrics div:nth-child(3) { border-left:0; }
  .user-metrics div:nth-child(-n+2) { border-bottom:1px solid var(--line); }
  .user-trip-list a { grid-template-columns:minmax(0,1fr) auto; gap:8px 12px; }
  .trip-date { grid-column:1; }
  .trip-main { grid-column:1; }
  .trip-mileage { grid-column:2; grid-row:1; }
  .user-trip-list a>svg { grid-column:2; grid-row:2; justify-self:end; }
}
@media (max-width:600px) {
  .user-page { padding:36px 16px 52px; }
  .user-input-row { grid-template-columns:1fr; }
  .user-form button { width:100%; }
  .profile-panel { grid-template-columns:62px minmax(0,1fr); padding:18px; }
  .profile-panel img,.profile-initial { width:62px; height:62px; }
  .profile-copy h2 { font-size:21px; }
  .achievement-list { grid-template-columns:1fr; }
}
@media (prefers-color-scheme:dark) { .user-form button { color:#5c0a05; } }
</style>
