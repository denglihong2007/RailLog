<script setup lang="ts">
import { onMounted, ref } from 'vue'
import {
  ArrowRight,
  Copy,
  ExternalLink,
  Gauge,
  LoaderCircle,
  Megaphone,
  MessageSquareText,
  RefreshCw,
  Ticket,
  Trash2,
  TriangleAlert,
  Users,
  Wrench,
} from '@lucide/vue'
import {
  api,
  ApiError,
  type AdminDuplicateGroup,
  type AdminDuplicateTrip,
  type AdminFlaggedTrip,
  type AdminOverview,
  type AdminRecentReview,
} from '../api'
import { confirmDeleteDuplicateTrips, deleteDuplicateTrips } from '../duplicates'
import { formatDate, formatDateTime, formatMileage, formatNumber, initials } from '../format'
import { toast } from '../toast'
import DuplicateGroups from './DuplicateGroups.vue'

const emit = defineEmits<{
  navigate: [path: string]
  'open-user': [id: string]
  'open-trip': [userId: string, ticketId: number]
}>()

const data = ref<AdminOverview | null>(null)
const loading = ref(true)
const error = ref('')
const handlingGroup = ref<AdminDuplicateGroup | null>(null)
const duplicateBusy = ref(false)

async function load(silent = false): Promise<void> {
  if (!silent) loading.value = true
  error.value = ''
  try {
    data.value = await api.overview()
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取运营概况失败'
  } finally {
    if (!silent) loading.value = false
  }
}

function groupKey(group: AdminDuplicateGroup): string {
  return [
    group.userId,
    group.trainNumber,
    group.travelDate,
    group.fromStation,
    group.toStation,
  ].join(':')
}

function closeGroup(): void {
  if (duplicateBusy.value) return
  handlingGroup.value = null
}

// 删除后组内可能只剩一条（不再算重复），弹窗里要换成最新的组数据。
function syncHandlingGroup(): void {
  if (!handlingGroup.value) return
  const key = groupKey(handlingGroup.value)
  handlingGroup.value =
    data.value?.duplicateGroups.find((group) => groupKey(group) === key) ?? null
}

async function deleteDuplicateTrip(trip: AdminDuplicateTrip): Promise<void> {
  if (!handlingGroup.value) return
  if (!confirmDeleteDuplicateTrips([trip])) return
  duplicateBusy.value = true
  try {
    const result = await deleteDuplicateTrips([trip])
    if (result.failed.length > 0) toast(result.failed[0] ?? '删除失败', 'error')
    else toast('已删除该条重复行程', 'info')
    await load(true)
    syncHandlingGroup()
  } finally {
    duplicateBusy.value = false
  }
}

async function keepEarliestTrip(group: AdminDuplicateGroup): Promise<void> {
  const keep = group.trips[0]
  const removed = group.trips.slice(1)
  if (!keep) return
  if (!confirmDeleteDuplicateTrips(removed)) return
  duplicateBusy.value = true
  try {
    const result = await deleteDuplicateTrips(removed)
    if (result.failed.length > 0) {
      toast(`保留 #${keep.ticketId}，但有 ${result.failed.length} 条删除失败`, 'error')
    } else {
      toast(`已保留最早录入的 #${keep.ticketId}，删除其余 ${removed.length} 条`, 'info')
    }
    await load(true)
    syncHandlingGroup()
  } finally {
    duplicateBusy.value = false
  }
}

function formatSpeed(value: number | null): string {
  return value === null ? '—' : `${formatNumber(value, value >= 100 ? 0 : 1)} km/h`
}

function openTrip(trip: AdminFlaggedTrip): void {
  emit('open-trip', trip.userId, trip.ticketId)
}

function openReview(review: AdminRecentReview): void {
  emit(
    'navigate',
    `/reviews?entityType=${encodeURIComponent(review.entityType)}&query=${encodeURIComponent(review.entityKey)}`,
  )
}

function openFeedUser(id: string): void {
  emit('open-user', id)
}

onMounted(load)
</script>

<template>
  <div class="page-stack">
    <div v-if="loading" class="state-card">
      <LoaderCircle :size="22" class="spin" />
      <span>正在读取运营概况…</span>
    </div>

    <div v-else-if="error" class="state-card error">
      <TriangleAlert :size="22" />
      <span>{{ error }}</span>
      <button type="button" class="button ghost" @click="load()"><RefreshCw :size="16" />重试</button>
    </div>

    <template v-else-if="data">
      <section class="stat-grid" aria-label="站务数据">
        <article class="stat-card">
          <span class="stat-icon blue"><Users :size="20" /></span>
          <div>
            <p class="stat-label">用户总数</p>
            <strong class="stat-value">{{ formatNumber(data.counts.users) }}</strong>
            <p class="stat-hint">近 7 天新增 {{ formatNumber(data.counts.newUsers) }}</p>
          </div>
        </article>
        <article class="stat-card">
          <span class="stat-icon red"><Ticket :size="20" /></span>
          <div>
            <p class="stat-label">有效行程</p>
            <strong class="stat-value">{{ formatNumber(data.counts.activeTrips) }}</strong>
            <p class="stat-hint">近 7 天新增 {{ formatNumber(data.counts.newTrips) }}</p>
          </div>
        </article>
        <article class="stat-card">
          <span class="stat-icon amber"><MessageSquareText :size="20" /></span>
          <div>
            <p class="stat-label">用户评价</p>
            <strong class="stat-value">{{ formatNumber(data.counts.reviews) }}</strong>
            <p class="stat-hint">近 7 天新增 {{ formatNumber(data.counts.newReviews) }}</p>
          </div>
        </article>
        <article class="stat-card">
          <span class="stat-icon green"><Trash2 :size="20" /></span>
          <div>
            <p class="stat-label">已删除行程</p>
            <strong class="stat-value">{{ formatNumber(data.counts.deletedTrips) }}</strong>
            <p class="stat-hint">软删除记录，可在用户行程中恢复</p>
          </div>
        </article>
      </section>

      <div class="overview-columns">
        <section class="panel">
          <div class="panel-head">
            <div>
              <h2><Gauge :size="17" /> 速度异常</h2>
              <p>平均速度超过 360 km/h 的有效行程，通常是里程或起止时间填错</p>
            </div>
            <span class="pill amber">{{ formatNumber(data.overspeedTripCount) }} 条</span>
          </div>

          <div v-if="data.overspeedTrips.length" class="table-wrap">
            <table class="data-table">
              <thead>
                <tr>
                  <th>行程</th>
                  <th class="col-number">均速</th>
                  <th class="col-number">里程</th>
                  <th>用户</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="trip in data.overspeedTrips" :key="trip.ticketId">
                  <td>
                    <button
                      type="button"
                      class="trip-link"
                      :title="`定位并编辑行程 #${trip.ticketId}`"
                      @click="openTrip(trip)"
                    >
                      {{ trip.trainNumber }}
                      <span>{{ trip.fromStation }} → {{ trip.toStation }}</span>
                      <ExternalLink :size="12" />
                    </button>
                    <small class="sub-line">
                      {{ formatDate(trip.travelDate) }} · #{{ trip.ticketId }}
                    </small>
                  </td>
                  <td class="col-number">{{ formatSpeed(trip.speedKmh) }}</td>
                  <td class="col-number">{{ formatMileage(trip.mileageKm) }}</td>
                  <td>
                    <button
                      type="button"
                      class="user-chip-button"
                      :title="`查看 ${trip.displayName} 的行程`"
                      @click="emit('open-user', trip.userId)"
                    >
                      <span class="avatar">{{ initials(trip.displayName) }}</span>
                      <span class="user-chip-copy"><strong>{{ trip.displayName }}</strong></span>
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p v-else class="empty-note">没有发现速度异常行程</p>
        </section>

        <section class="panel">
          <div class="panel-head">
            <div>
              <h2><Copy :size="17" /> 疑似重复行程</h2>
              <p>
                同一用户、同一车次、同一乘车日期，且始发终到站、票价、里程都相同时录入多次，常见于重复导入。
                共 {{ formatNumber(data.duplicateGroupCount) }} 组 /
                {{ formatNumber(data.duplicateTripCount) }} 条。
              </p>
            </div>
            <button type="button" class="button ghost small" @click="emit('navigate', '/duplicates')">
              查看全部 <ArrowRight :size="15" />
            </button>
          </div>

          <ul v-if="data.duplicateGroups.length" class="overview-feed">
            <li v-for="group in data.duplicateGroups" :key="groupKey(group)">
              <span class="avatar">{{ initials(group.displayName) }}</span>
              <span class="overview-feed-main">
                <strong>{{ group.trainNumber }} · {{ formatDate(group.travelDate) }}</strong>
                <p>
                  {{ group.fromStation }} → {{ group.toStation }} · {{ group.displayName }} ·
                  {{ group.trips.length }} 条记录
                </p>
              </span>
              <button type="button" class="button subtle small" @click="handlingGroup = group">
                <Wrench :size="14" /> 处理
              </button>
            </li>
          </ul>
          <p v-else class="empty-note">没有发现重复行程</p>
        </section>
      </div>

      <div class="overview-columns">
        <section class="panel">
          <div class="panel-head">
            <div>
              <h2><MessageSquareText :size="17" /> 最新评价</h2>
              <p>点击可进入评价管理，按同一对象继续筛选</p>
            </div>
            <button type="button" class="button ghost small" @click="emit('navigate', '/reviews')">
              评价管理 <ArrowRight :size="15" />
            </button>
          </div>

          <ul v-if="data.recentReviews.length" class="overview-feed">
            <li
              v-for="review in data.recentReviews"
              :key="review.id"
              role="button"
              tabindex="0"
              class="clickable"
              @click="openReview(review)"
              @keydown.enter.prevent="openReview(review)"
              @keydown.space.prevent="openReview(review)"
            >
              <span class="avatar">{{ initials(review.displayName) }}</span>
              <span class="overview-feed-main">
                <strong>{{ review.displayName }} · {{ review.entityKey || '—' }}</strong>
                <p>{{ review.comment || '（没有填写评价内容）' }}</p>
              </span>
              <span class="overview-feed-meta">
                <span class="stars">{{ '★★★★★'.slice(0, Math.max(0, Math.min(5, review.rating))) }}</span>
                <small>{{ formatDate(review.createdAt) }}</small>
              </span>
            </li>
          </ul>
          <p v-else class="empty-note">还没有用户评价</p>
        </section>

        <section class="panel">
          <div class="panel-head">
            <div>
              <h2><Users :size="17" /> 最新用户</h2>
              <p>点击可查看该用户全部行程</p>
            </div>
            <button type="button" class="button ghost small" @click="emit('navigate', '/users')">
              用户管理 <ArrowRight :size="15" />
            </button>
          </div>

          <ul v-if="data.recentUsers.length" class="overview-feed">
            <li
              v-for="user in data.recentUsers"
              :key="user.id"
              role="button"
              tabindex="0"
              class="clickable"
              @click="openFeedUser(user.id)"
              @keydown.enter.prevent="openFeedUser(user.id)"
              @keydown.space.prevent="openFeedUser(user.id)"
            >
              <span class="avatar">{{ initials(user.displayName) }}</span>
              <span class="overview-feed-main">
                <strong>{{ user.displayName }}</strong>
                <p>{{ user.email || '未提供邮箱' }}</p>
              </span>
              <span class="overview-feed-meta">
                <small>{{ formatDateTime(user.createdAt) }}</small>
                <small>{{ formatNumber(user.tripCount) }} 条行程</small>
              </span>
            </li>
          </ul>
          <p v-else class="empty-note">暂无用户数据</p>
        </section>
      </div>

      <section class="quick-grid">
        <button type="button" class="quick-card" @click="emit('navigate', '/announcements')">
          <span class="stat-icon red"><Megaphone :size="20" /></span>
          <span>
            <strong>发布公告</strong>
            <small>{{ formatNumber(data.counts.activeAnnouncements) }} 条公告正在轮播</small>
          </span>
          <ArrowRight :size="18" />
        </button>
        <button type="button" class="quick-card" @click="emit('navigate', '/leaderboards')">
          <span class="stat-icon amber"><Gauge :size="20" /></span>
          <span><strong>纠正排行榜数据</strong><small>点选异常行程直接定位并修正</small></span>
          <ArrowRight :size="18" />
        </button>
        <button type="button" class="quick-card" @click="emit('navigate', '/users')">
          <span class="stat-icon blue"><Users :size="20" /></span>
          <span><strong>检索用户行程</strong><small>按昵称、邮箱或用户 ID 查找</small></span>
          <ArrowRight :size="18" />
        </button>
      </section>
    </template>

    <div v-if="handlingGroup" class="modal-backdrop" @click.self="closeGroup">
      <div class="modal wide" role="dialog" aria-modal="true" aria-labelledby="duplicate-handling-title">
        <header class="modal-head">
          <div>
            <h2 id="duplicate-handling-title">处理重复行程</h2>
            <p>
              {{ handlingGroup.trainNumber }} ·
              {{ handlingGroup.fromStation }} → {{ handlingGroup.toStation }} ·
              {{ formatDate(handlingGroup.travelDate) }} ·
              {{ handlingGroup.displayName }}
            </p>
          </div>
          <button type="button" class="icon-button" aria-label="关闭" :disabled="duplicateBusy" @click="closeGroup">
            <span aria-hidden="true">✕</span>
          </button>
        </header>
        <div class="modal-body">
          <DuplicateGroups
            :groups="[handlingGroup]"
            :busy="duplicateBusy"
            @delete-trip="deleteDuplicateTrip"
            @keep-earliest="keepEarliestTrip"
            @open-trip="(userId, ticketId) => emit('open-trip', userId, ticketId)"
            @open-user="(userId) => emit('open-user', userId)"
          />
        </div>
        <footer class="modal-foot">
          <button type="button" class="button ghost" :disabled="duplicateBusy" @click="closeGroup">关闭</button>
        </footer>
      </div>
    </div>
  </div>
</template>
