<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  AlertCircle,
  ArrowRight,
  CircleUserRound,
  Info,
  MapPin,
  Navigation,
  NotebookText,
  ReceiptText,
  Route,
  Search,
  TrainFront,
} from '@lucide/vue'

interface PublicUser {
  id: string
  displayName: string
  avatarUrl: string | null
  bio: string | null
}

interface PublicTrip {
  ticketId: number
  createdAt: string
  trainNumber: string
  rollingStock: string | null
  companyName: string | null
  fromStation: string
  toStation: string
  departureTime: string | null
  arrivalTime: string | null
  mileageKm: number
  viaRoutes: string
  seatType: string | null
  seatNumber: string | null
  price: number
  notes: string | null
  isRailTrip: boolean
}

interface TripDetailsResponse {
  user: PublicUser
  trip: PublicTrip
}

interface ViaRouteSegment {
  routeName: string
  fromStation: string
  toStation: string
  mileageKm: number
}

const props = defineProps<{ apiBase: string }>()
const initialId = new URLSearchParams(window.location.search).get('id') ?? ''
const tripId = ref(initialId)
const submittedId = ref('')
const details = ref<TripDetailsResponse | null>(null)
const state = ref<'idle' | 'loading' | 'ready' | 'not-found' | 'error'>('idle')
const avatarFailed = ref(false)
let activeRequest = 0

const trip = computed(() => details.value?.trip ?? null)
const departureTime = computed(() => trip.value ? parseDate(trip.value.departureTime ?? trip.value.createdAt) : null)
const arrivalTime = computed(() => parseDate(trip.value?.arrivalTime))
const durationMs = computed(() => {
  if (!departureTime.value || !arrivalTime.value) return null
  const value = arrivalTime.value.getTime() - departureTime.value.getTime()
  return value > 0 ? value : null
})
const averageSpeed = computed(() => {
  if (!trip.value || trip.value.mileageKm <= 0 || !durationMs.value) return null
  return trip.value.mileageKm / (durationMs.value / 3_600_000)
})
const averagePrice = computed(() => {
  if (!trip.value || trip.value.mileageKm <= 0) return null
  return trip.value.price / trip.value.mileageKm
})
const viaRoutes = computed(() => parseViaRoutes(trip.value?.viaRoutes))
const ownerInitial = computed(() => details.value?.user.displayName.trim().charAt(0) || '旅')

onMounted(() => {
  document.title = '行程查询 - RailLog 轨记'
  if (/^[1-9]\d*$/.test(initialId)) void queryTrip(initialId)
})

function submit(): void {
  const normalized = tripId.value.trim()
  if (!/^[1-9]\d*$/.test(normalized)) {
    submittedId.value = normalized
    details.value = null
    state.value = 'error'
    return
  }
  void queryTrip(normalized)
}

async function queryTrip(id: string): Promise<void> {
  const requestId = ++activeRequest
  tripId.value = id
  submittedId.value = id
  details.value = null
  avatarFailed.value = false
  state.value = 'loading'
  window.history.replaceState(null, '', `/?trip=1&id=${encodeURIComponent(id)}`)
  try {
    const response = await fetch(`${props.apiBase}/api/trips/${encodeURIComponent(id)}`)
    if (requestId !== activeRequest) return
    if (response.status === 404) {
      state.value = 'not-found'
      return
    }
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    details.value = (await response.json()) as TripDetailsResponse
    state.value = 'ready'
  } catch {
    if (requestId === activeRequest) state.value = 'error'
  }
}

function parseDate(value: string | null | undefined): Date | null {
  if (!value) return null
  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? null : parsed
}

function parseViaRoutes(value: string | null | undefined): ViaRouteSegment[] {
  if (!value) return []
  try {
    const parsed = JSON.parse(value) as unknown
    if (!Array.isArray(parsed)) return []
    return parsed.flatMap((item) => {
      if (!item || typeof item !== 'object') return []
      const row = item as Record<string, unknown>
      const routeName = typeof row.routeName === 'string' ? row.routeName : ''
      const fromStation = typeof row.fromStation === 'string' ? row.fromStation : ''
      const toStation = typeof row.toStation === 'string' ? row.toStation : ''
      const mileageKm = typeof row.mileageKm === 'number' ? row.mileageKm : 0
      return routeName ? [{ routeName, fromStation, toStation, mileageKm }] : []
    })
  } catch {
    return []
  }
}

function optionalText(value: string | null | undefined): string {
  return value?.trim() || '未记录'
}

function pad(value: number): string {
  return value.toString().padStart(2, '0')
}

function formatDate(value: Date | null): string {
  return value ? `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())}` : '未记录'
}

function formatDateTime(value: Date | null): string {
  return value ? `${formatDate(value)} ${pad(value.getHours())}:${pad(value.getMinutes())}:${pad(value.getSeconds())}` : '未记录'
}

function formatTicketTime(value: Date | null): string {
  return value ? `${pad(value.getMonth() + 1)}-${pad(value.getDate())} ${pad(value.getHours())}:${pad(value.getMinutes())}` : '--:--'
}

function formatDuration(milliseconds: number | null): string {
  if (!milliseconds) return '未记录'
  const minutes = Math.floor(milliseconds / 60_000)
  const hours = Math.floor(minutes / 60)
  const remainder = minutes % 60
  if (hours === 0) return `${remainder}分`
  return remainder === 0 ? `${hours}时` : `${hours}时${remainder}分`
}

function formatNumber(value: number): string {
  return Number.isInteger(value) ? value.toString() : value.toFixed(1)
}
</script>

<template>
  <section class="lookup-page" aria-labelledby="lookup-title">
    <div class="lookup-heading">
      <p class="lookup-kicker"><Search :size="18" /> 公开行程</p>
      <h1 id="lookup-title">行程查询</h1>
      <p>输入行程 ID，查看行程记录及其归属。</p>
    </div>

    <form class="lookup-form" role="search" @submit.prevent="submit">
      <label for="trip-id">行程 ID</label>
      <div class="lookup-input-row">
        <div class="lookup-input">
          <Search :size="20" aria-hidden="true" />
          <input id="trip-id" v-model="tripId" inputmode="numeric" autocomplete="off" placeholder="例如：123" aria-describedby="trip-id-help" />
        </div>
        <button type="submit" :disabled="state === 'loading'">
          <Search :size="19" />{{ state === 'loading' ? '查询中' : '查询' }}
        </button>
      </div>
      <span id="trip-id-help">行程 ID 可在 RailLog App 的行程详情中查看</span>
    </form>

    <div v-if="state === 'idle'" class="lookup-empty">
      <TrainFront :size="38" />
      <strong>等待查询</strong>
      <span>查询结果将在这里显示</span>
    </div>
    <div v-else-if="state === 'loading'" class="lookup-empty" aria-live="polite">
      <span class="loading-indicator" aria-hidden="true"></span>
      <strong>正在读取行程</strong>
      <span>行程 #{{ submittedId }}</span>
    </div>
    <div v-else-if="state === 'not-found'" class="lookup-empty error-state" role="status">
      <AlertCircle :size="38" />
      <strong>未找到这条行程记录</strong>
      <span>请检查行程 ID 是否正确</span>
    </div>
    <div v-else-if="state === 'error'" class="lookup-empty error-state" role="alert">
      <AlertCircle :size="38" />
      <strong>{{ submittedId && !/^[1-9]\d*$/.test(submittedId) ? '请输入有效的行程 ID' : '暂时无法读取行程' }}</strong>
      <span>{{ submittedId && !/^[1-9]\d*$/.test(submittedId) ? '行程 ID 应为正整数' : '请稍后重试' }}</span>
    </div>

    <div v-else-if="details && trip" class="trip-result" aria-live="polite">
      <a class="owner-panel" :href="`/user?id=${encodeURIComponent(details.user.id)}`" aria-label="查看行程归属用户">
        <img v-if="details.user.avatarUrl && !avatarFailed" :src="details.user.avatarUrl" alt="" @error="avatarFailed = true" />
        <span v-else class="owner-initial" aria-hidden="true">{{ ownerInitial }}</span>
        <div>
          <span>行程归属</span>
          <strong>{{ details.user.displayName }}</strong>
          <p>{{ optionalText(details.user.bio) }}</p>
        </div>
        <CircleUserRound :size="24" aria-hidden="true" />
      </a>

      <article class="ticket-panel">
        <header>
          <TrainFront :size="24" />
          <strong>{{ optionalText(trip.trainNumber) }}</strong>
          <div><span>#{{ trip.ticketId }}</span><time>{{ formatDate(departureTime) }}</time></div>
        </header>
        <div class="ticket-route">
          <div><strong>{{ trip.fromStation }}</strong><time>{{ formatTicketTime(departureTime) }}</time></div>
          <div class="route-arrow"><ArrowRight :size="25" /><span>{{ formatDuration(durationMs) }}</span></div>
          <div class="arrival"><strong>{{ trip.toStation }}</strong><time>{{ formatTicketTime(arrivalTime) }}</time></div>
        </div>
      </article>

      <div class="detail-sections">
        <section class="detail-section">
          <h2><Info :size="19" />基础信息</h2>
          <dl>
            <div><dt>行程类型</dt><dd>{{ trip.isRailTrip ? '铁路行程' : '非铁路行程' }}</dd></div>
            <div><dt>录入时间</dt><dd>{{ formatDateTime(parseDate(trip.createdAt)) }}</dd></div>
            <div><dt>出发时间</dt><dd>{{ formatDateTime(departureTime) }}</dd></div>
            <div><dt>到达时间</dt><dd>{{ formatDateTime(arrivalTime) }}</dd></div>
          </dl>
        </section>

        <section class="detail-section">
          <h2><Navigation :size="19" />运行信息</h2>
          <dl>
            <div><dt>车型</dt><dd>{{ optionalText(trip.rollingStock) }}</dd></div>
            <div><dt>承运单位</dt><dd>{{ optionalText(trip.companyName) }}</dd></div>
            <div><dt>里程</dt><dd>{{ trip.mileageKm > 0 ? `${formatNumber(trip.mileageKm)} km` : '未记录' }}</dd></div>
            <div><dt>乘坐时长</dt><dd>{{ formatDuration(durationMs) }}</dd></div>
            <div><dt>均速</dt><dd>{{ averageSpeed === null ? '未记录' : `${formatNumber(averageSpeed)} km/h` }}</dd></div>
          </dl>
        </section>

        <section class="detail-section">
          <h2><ReceiptText :size="19" />票务信息</h2>
          <dl>
            <div><dt>席别</dt><dd>{{ optionalText(trip.seatType) }}</dd></div>
            <div><dt>座位号</dt><dd>{{ optionalText(trip.seatNumber) }}</dd></div>
            <div><dt>票价</dt><dd>¥{{ trip.price.toFixed(2) }}</dd></div>
            <div><dt>平均价格</dt><dd>{{ averagePrice === null ? '未记录' : `${averagePrice.toFixed(2)} 元/km` }}</dd></div>
          </dl>
        </section>

        <section class="detail-section route-section">
          <h2><Route :size="19" />经由线路 · {{ viaRoutes.length }} 段</h2>
          <p v-if="viaRoutes.length === 0" class="missing-value">未记录</p>
          <ol v-else class="route-list">
            <li v-for="(segment, index) in viaRoutes" :key="`${index}-${segment.routeName}`">
              <span>{{ index + 1 }}</span>
              <div><strong>{{ segment.routeName }}</strong><p><MapPin :size="15" />{{ segment.fromStation }} → {{ segment.toStation }}</p></div>
              <em v-if="segment.mileageKm > 0">{{ formatNumber(segment.mileageKm) }} km</em>
            </li>
          </ol>
        </section>

        <section class="detail-section notes-section">
          <h2><NotebookText :size="19" />备注</h2>
          <p>{{ optionalText(trip.notes) }}</p>
        </section>
      </div>
    </div>
  </section>
</template>

<style scoped>
.lookup-page { width:min(860px,100%); min-height:calc(100svh - 68px); margin:0 auto; padding:54px 20px 72px; }
.lookup-heading { margin-bottom:28px; }
.lookup-kicker { margin:0 0 8px; display:flex; align-items:center; gap:8px; color:var(--brand); font-weight:700; }
.lookup-heading h1 { margin:0; display:block; font-size:clamp(34px,6vw,52px); line-height:1.15; }
.lookup-heading>p:last-child { margin:12px 0 0; color:var(--muted); font-size:17px; }
.lookup-form { padding:20px; border:1px solid var(--line); border-radius:8px; background:var(--surface-low); }
.lookup-form>label { display:block; margin-bottom:8px; font-weight:700; }
.lookup-input-row { display:grid; grid-template-columns:minmax(0,1fr) auto; gap:10px; }
.lookup-input { min-width:0; min-height:50px; padding:0 14px; display:flex; align-items:center; gap:10px; border:1px solid var(--line); border-radius:7px; background:var(--surface); }
.lookup-input:focus-within { border-color:var(--brand); outline:2px solid color-mix(in srgb,var(--brand) 22%,transparent); }
.lookup-input svg { flex:0 0 auto; color:var(--muted); }
.lookup-input input { width:100%; min-width:0; border:0; outline:0; background:transparent; color:var(--ink); font:inherit; font-size:17px; }
.lookup-form button { min-width:110px; min-height:50px; padding:0 18px; display:inline-flex; align-items:center; justify-content:center; gap:8px; border:0; border-radius:7px; background:var(--brand); color:#fff; font:inherit; font-weight:700; cursor:pointer; }
.lookup-form button:hover:not(:disabled) { background:var(--brand-dark); }
.lookup-form button:disabled { opacity:.65; cursor:wait; }
.lookup-form>span { display:block; margin-top:8px; color:var(--muted); font-size:13px; }
.lookup-empty { min-height:280px; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:8px; color:var(--muted); text-align:center; }
.lookup-empty svg { margin-bottom:4px; color:var(--brand); }
.lookup-empty strong { color:var(--ink); font-size:18px; }
.error-state svg { color:var(--brand); }
.loading-indicator { width:32px; height:32px; margin-bottom:8px; border:3px solid var(--line); border-top-color:var(--brand); border-radius:50%; animation:spin .8s linear infinite; }
.trip-result { margin-top:22px; display:grid; gap:14px; }
.owner-panel { min-width:0; padding:14px 16px; display:grid; grid-template-columns:48px minmax(0,1fr) auto; gap:13px; align-items:center; border:1px solid var(--line); border-radius:8px; background:var(--surface); }
.owner-panel:hover { border-color:color-mix(in srgb,var(--brand) 55%,var(--line)); background:var(--surface-low); }
.owner-panel img,.owner-initial { width:48px; height:48px; border-radius:50%; object-fit:cover; }
.owner-initial { display:grid; place-items:center; background:var(--surface-low); color:var(--brand); font-size:20px; font-weight:750; }
.owner-panel div>span { color:var(--muted); font-size:12px; }
.owner-panel strong { display:block; margin-top:1px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.owner-panel p { margin:3px 0 0; color:var(--muted); font-size:14px; overflow-wrap:anywhere; }
.owner-panel>svg { color:var(--muted); }
.ticket-panel { overflow:hidden; border:1px solid var(--line); border-radius:8px; background:var(--surface); }
.ticket-panel header { min-width:0; padding:11px 16px; display:grid; grid-template-columns:auto minmax(0,1fr) auto; align-items:center; gap:9px; background:color-mix(in srgb,var(--brand) 13%,var(--surface)); }
.ticket-panel header>strong { overflow:hidden; font-size:21px; text-overflow:ellipsis; white-space:nowrap; }
.ticket-panel header>div { display:grid; justify-items:end; font-size:13px; }
.ticket-panel header time { color:var(--muted); }
.ticket-route { min-width:0; padding:20px 18px; display:grid; grid-template-columns:minmax(0,1fr) auto minmax(0,1fr); align-items:center; gap:14px; }
.ticket-route>div:not(.route-arrow) { min-width:0; display:grid; gap:5px; }
.ticket-route strong { overflow:hidden; font-size:18px; text-overflow:ellipsis; white-space:nowrap; }
.ticket-route time { color:var(--muted); font-size:14px; }
.ticket-route .arrival { justify-items:end; text-align:right; }
.route-arrow { display:grid; justify-items:center; gap:3px; color:var(--muted); }
.route-arrow span { font-size:12px; white-space:nowrap; }
.detail-sections { display:grid; gap:12px; }
.detail-section { padding:18px; border-radius:8px; background:var(--surface-low); }
.detail-section h2 { margin:0 0 16px; display:flex; align-items:center; gap:8px; font-size:16px; }
.detail-section h2 svg { color:var(--brand); }
.detail-section dl { margin:0; display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:18px 24px; }
.detail-section dl div { min-width:0; }
.detail-section dt { margin-bottom:4px; color:var(--muted); font-size:13px; }
.detail-section dd { margin:0; overflow-wrap:anywhere; }
.route-list { margin:0; padding:0; list-style:none; }
.route-list li { min-width:0; padding:12px 0; display:grid; grid-template-columns:30px minmax(0,1fr) auto; gap:10px; align-items:start; border-top:1px solid var(--line); }
.route-list li:first-child { padding-top:0; border-top:0; }
.route-list li:last-child { padding-bottom:0; }
.route-list li>span { color:var(--brand); font-weight:750; text-align:center; }
.route-list strong { overflow-wrap:anywhere; }
.route-list p { margin:4px 0 0; display:flex; align-items:center; gap:4px; color:var(--muted); font-size:14px; overflow-wrap:anywhere; }
.route-list em { font-style:normal; white-space:nowrap; }
.missing-value,.notes-section>p { margin:0; overflow-wrap:anywhere; }
@keyframes spin { to { transform:rotate(360deg); } }
@media (max-width:600px) {
  .lookup-page { padding:36px 16px 52px; }
  .lookup-input-row { grid-template-columns:1fr; }
  .lookup-form button { width:100%; }
  .detail-section dl { grid-template-columns:1fr; gap:16px; }
  .ticket-route { padding:18px 14px; gap:8px; }
  .ticket-route strong { font-size:16px; }
  .owner-panel { grid-template-columns:44px minmax(0,1fr); }
  .owner-panel img,.owner-initial { width:44px; height:44px; }
  .owner-panel>svg { display:none; }
  .route-list li { grid-template-columns:28px minmax(0,1fr); }
  .route-list em { grid-column:2; color:var(--muted); font-size:13px; }
}
@media (prefers-color-scheme:dark) {
  .lookup-form button { color:#5c0a05; }
}
</style>
