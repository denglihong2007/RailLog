<script setup lang="ts">
import { computed, onMounted, ref, type Component } from 'vue'
import {
  Building2,
  Clock,
  Gauge,
  LoaderCircle,
  MapPin,
  RefreshCw,
  Route,
  Sparkles,
  TrainFront,
  TriangleAlert,
  Trophy,
  Users,
  Wallet,
} from '@lucide/vue'
import {
  api,
  ApiError,
  type ElementRankingEntry,
  type StatisticsResponse,
  type TripRankingEntry,
  type UserRankingEntry,
} from '../api'
import {
  formatDuration,
  formatMileage,
  formatMoney,
  formatNumber,
  initials,
} from '../format'

type Tab = 'users' | 'trips' | 'elements'

const emit = defineEmits<{
  'open-user': [id: string]
  'open-trip': [userId: string, tripId: number]
  'open-reviews': [entityType: string, name: string]
}>()

interface UserBoard {
  key: string
  title: string
  hint: string
  icon: Component
  entries: UserRankingEntry[]
  format: (value: number) => string
}

interface TripBoard {
  key: string
  title: string
  hint: string
  icon: Component
  entries: TripRankingEntry[]
  format: (value: number) => string
}

interface ElementBoard {
  key: string
  title: string
  hint: string
  icon: Component
  entityType: string
  entries: ElementRankingEntry[]
  unit: string
}

const stats = ref<StatisticsResponse | null>(null)
const loading = ref(true)
const error = ref('')
const tab = ref<Tab>('users')

const userBoards = computed<UserBoard[]>(() => {
  const data = stats.value
  if (!data) return []
  return [
    { key: 'spending', title: '累计花费', hint: '按用户全部行程票价合计', icon: Wallet, entries: data.users.totalSpending, format: formatMoney },
    { key: 'count', title: '行程数量', hint: '按有效铁路行程条数', icon: Route, entries: data.users.tripCount, format: (value) => `${formatNumber(value)} 条` },
    { key: 'duration', title: '在途时长', hint: '按行程起止时间累计', icon: Clock, entries: data.users.durationSeconds, format: formatDuration },
    { key: 'mileage', title: '累计里程', hint: '按行程里程合计', icon: TrainFront, entries: data.users.mileageKm, format: formatMileage },
    { key: 'experience', title: '成就经验', hint: '按已解锁成就经验合计', icon: Sparkles, entries: data.users.achievementExperience, format: (value) => `${formatNumber(value)} 经验` },
  ]
})

const tripBoards = computed<TripBoard[]>(() => {
  const data = stats.value
  if (!data) return []
  return [
    { key: 'price', title: '单程票价最高', hint: '按单条行程票价', icon: Wallet, entries: data.trips.singleSpending, format: formatMoney },
    { key: 'mileage', title: '单程里程最长', hint: '按单条行程里程', icon: Route, entries: data.trips.mileageKm, format: formatMileage },
    { key: 'duration', title: '单程耗时最长', hint: '按起止时间差', icon: Clock, entries: data.trips.durationSeconds, format: formatDuration },
    { key: 'value', title: '性价比最高', hint: '每公里票价最低', icon: Sparkles, entries: data.trips.bestValueYuanPerKm, format: (value) => `¥${value.toFixed(3)}/km` },
    { key: 'luxury', title: '最奢华', hint: '每公里票价最高', icon: Wallet, entries: data.trips.luxuryYuanPerKm, format: (value) => `¥${value.toFixed(3)}/km` },
    { key: 'slow', title: '均速最慢', hint: '里程 ÷ 运行时长', icon: Gauge, entries: data.trips.slowestAverageSpeedKmh, format: (value) => `${formatNumber(value, 1)} km/h` },
    { key: 'fast', title: '均速最快', hint: '超过 360 km/h 的异常行程不参与', icon: Gauge, entries: data.trips.fastestAverageSpeedKmh, format: (value) => `${formatNumber(value, 1)} km/h` },
  ]
})

const elementBoards = computed<ElementBoard[]>(() => {
  const data = stats.value
  if (!data) return []
  return [
    { key: 'stations', title: '热门车站', hint: '按出发与到达次数，点选可查看相关评价', icon: MapPin, entityType: 'station', entries: data.elements.stations, unit: '次' },
    { key: 'routes', title: '热门线路', hint: '按经由线路出现次数，点选可查看相关评价', icon: Route, entityType: 'route', entries: data.elements.routes, unit: '次' },
    { key: 'trains', title: '热门车次', hint: '按车次出现次数，点选可查看相关评价', icon: TrainFront, entityType: 'train', entries: data.elements.trains, unit: '次' },
    { key: 'stocks', title: '热门车型', hint: '按解析出的车型统计，点选可查看相关评价', icon: Gauge, entityType: 'rollingStock', entries: data.elements.rollingStocks, unit: '次' },
    { key: 'companies', title: '值乘公司', hint: '按行程填写的值乘公司统计，点选可查看相关评价', icon: Building2, entityType: 'company', entries: data.elements.companies, unit: '次' },
  ]
})

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    stats.value = await api.leaderboards()
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取排行榜失败'
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="page-stack">
    <div class="tab-bar">
      <button type="button" :class="['tab', { active: tab === 'users' }]" @click="tab = 'users'">
        <Users :size="17" /> 用户榜
      </button>
      <button type="button" :class="['tab', { active: tab === 'trips' }]" @click="tab = 'trips'">
        <TrainFront :size="17" /> 行程榜
      </button>
      <button type="button" :class="['tab', { active: tab === 'elements' }]" @click="tab = 'elements'">
        <MapPin :size="17" /> 要素榜
      </button>
      <button type="button" class="tab refresh" :disabled="loading" @click="load">
        <RefreshCw :size="16" :class="{ spin: loading }" /> 刷新
      </button>
    </div>

    <div v-if="loading" class="state-card">
      <LoaderCircle :size="22" class="spin" /><span>正在计算排行榜…</span>
    </div>
    <div v-else-if="error" class="state-card error">
      <TriangleAlert :size="22" /><span>{{ error }}</span>
      <button type="button" class="button ghost" @click="load"><RefreshCw :size="16" />重试</button>
    </div>

    <template v-else-if="stats">
      <section v-if="tab === 'users'" class="board-grid">
        <article v-for="board in userBoards" :key="board.key" class="panel board-panel">
          <div class="panel-head compact">
            <div>
              <h2><component :is="board.icon" :size="17" /> {{ board.title }}</h2>
              <p>{{ board.hint }}</p>
            </div>
            <Trophy :size="17" class="board-trophy" />
          </div>
          <ol v-if="board.entries.length" class="rank-list">
            <li
              v-for="entry in board.entries"
              :key="entry.user.id"
              class="clickable"
              role="button"
              tabindex="0"
              :title="`查看 ${entry.user.displayName} 的行程并修正数据`"
              @click="emit('open-user', entry.user.id)"
              @keydown.enter.prevent="emit('open-user', entry.user.id)"
              @keydown.space.prevent="emit('open-user', entry.user.id)"
            >
              <span :class="['rank-badge', `rank-${entry.rank}`]">{{ entry.rank }}</span>
              <span class="avatar small">{{ initials(entry.user.displayName) }}</span>
              <span class="rank-name">{{ entry.user.displayName }}</span>
              <span class="rank-value">{{ board.format(entry.value) }}</span>
            </li>
          </ol>
          <p v-else class="empty-note">暂无数据</p>
        </article>
      </section>

      <section v-else-if="tab === 'trips'" class="board-grid">
        <article v-for="board in tripBoards" :key="board.key" class="panel board-panel">
          <div class="panel-head compact">
            <div>
              <h2><component :is="board.icon" :size="17" /> {{ board.title }}</h2>
              <p>{{ board.hint }}</p>
            </div>
            <Trophy :size="17" class="board-trophy" />
          </div>
          <ol v-if="board.entries.length" class="rank-list trips">
            <li
              v-for="entry in board.entries"
              :key="`${entry.rank}-${entry.trip.ticketId}`"
              class="clickable"
              role="button"
              tabindex="0"
              :title="`打开 ${entry.trip.trainNumber} 的行程进行修正`"
              @click="emit('open-trip', entry.user.id, entry.trip.ticketId)"
              @keydown.enter.prevent="emit('open-trip', entry.user.id, entry.trip.ticketId)"
              @keydown.space.prevent="emit('open-trip', entry.user.id, entry.trip.ticketId)"
            >
              <span :class="['rank-badge', `rank-${entry.rank}`]">{{ entry.rank }}</span>
              <span class="trip-main">
                <strong>{{ entry.trip.trainNumber }}</strong>
                <small>{{ entry.trip.fromStation }} → {{ entry.trip.toStation }} · {{ entry.user.displayName }}</small>
              </span>
              <span class="rank-value">{{ board.format(entry.value) }}</span>
            </li>
          </ol>
          <p v-else class="empty-note">暂无数据</p>
        </article>
      </section>

      <section v-else class="board-grid">
        <article v-for="board in elementBoards" :key="board.key" class="panel board-panel">
          <div class="panel-head compact">
            <div>
              <h2><component :is="board.icon" :size="17" /> {{ board.title }}</h2>
              <p>{{ board.hint }}</p>
            </div>
            <Trophy :size="17" class="board-trophy" />
          </div>
          <ol v-if="board.entries.length" class="rank-list elements">
            <li
              v-for="entry in board.entries"
              :key="entry.name"
              :class="{ clickable: entry.name }"
              :role="entry.name ? 'button' : undefined"
              :tabindex="entry.name ? 0 : undefined"
              :title="entry.name ? `查看「${entry.name}」相关的评价` : undefined"
              @click="entry.name && emit('open-reviews', board.entityType, entry.name)"
              @keydown.enter.prevent="entry.name && emit('open-reviews', board.entityType, entry.name)"
              @keydown.space.prevent="entry.name && emit('open-reviews', board.entityType, entry.name)"
            >
              <span :class="['rank-badge', `rank-${entry.rank}`]">{{ entry.rank }}</span>
              <span class="rank-name">{{ entry.name || '（未填写）' }}</span>
              <span class="rank-value">{{ formatNumber(entry.value) }} {{ board.unit }}</span>
            </li>
          </ol>
          <p v-else class="empty-note">暂无数据</p>
        </article>
      </section>

      <p class="info-note">
        <Trophy :size="16" />
        点选用户可查看其全部行程；点选行程会直接打开编辑窗口；点选要素可查看该车站、线路、车次或车型的评价。
        排行榜只统计未删除的铁路行程，修改后立即生效。
      </p>
    </template>
  </div>
</template>
