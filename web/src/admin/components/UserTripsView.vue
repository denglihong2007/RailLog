<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  ArrowLeft,
  Copy,
  Inbox,
  LoaderCircle,
  Pencil,
  Plus,
  RefreshCw,
  RotateCcw,
  Search,
  TrainFront,
  Trash2,
  TriangleAlert,
  UserRound,
} from '@lucide/vue'
import {
  api,
  ApiError,
  type AdminTrip,
  type AdminTripInput,
  type AdminUserSummary,
} from '../api'
import { confirmDestructive } from '../confirm'
import {
  formatDate,
  formatDateTime,
  formatMileage,
  formatMoney,
  formatNumber,
  initials,
} from '../format'
import { toast } from '../toast'
import SortHeader from './SortHeader.vue'
import { nextSort, sortRows, type SortDirection, type SortState, type SortValue } from '../sort'
import TripEditorModal from './TripEditorModal.vue'

const props = defineProps<{ userId: string; focusTripId?: number }>()
const emit = defineEmits<{ back: [] }>()

const user = ref<AdminUserSummary | null>(null)
const trips = ref<AdminTrip[]>([])
const loading = ref(true)
const error = ref('')
const includeDeleted = ref(true)
const filter = ref('')
const editorOpen = ref(false)
const editingTrip = ref<AdminTrip | null>(null)
// 默认沿用接口顺序：正常行程在前，同组内按出发时间从新到旧。
const sort = ref<SortState | null>(null)
// 从排行榜/评价管理跳过来时只自动打开一次，之后保存或刷新不再打扰。
let focusHandled = false

const activeCount = computed(() => trips.value.filter((trip) => trip.deletedAt === null).length)
const deletedCount = computed(() => trips.value.filter((trip) => trip.deletedAt !== null).length)

const filteredTrips = computed(() => {
  const needle = filter.value.trim().toLowerCase()
  if (!needle) return trips.value
  return trips.value.filter((trip) => {
    const haystack = [
      trip.trainNumber,
      trip.fromStation,
      trip.toStation,
      trip.seatType,
      trip.seatNumber,
      trip.rollingStock,
      trip.companyName,
      trip.groupName,
      trip.notes,
    ]
      .filter(Boolean)
      .join(' ')
      .toLowerCase()
    return haystack.includes(needle)
  })
})

const SORT_INITIAL: Record<string, SortDirection> = {
  status: 'asc',
  train: 'asc',
  route: 'asc',
  seat: 'asc',
}

const sortGetters: Record<string, (row: AdminTrip) => SortValue> = {
  status: (row) => (row.deletedAt === null ? 0 : 1),
  train: (row) => row.trainNumber,
  route: (row) => row.fromStation,
  mileage: (row) => row.mileageKm,
  price: (row) => row.price,
  seat: (row) => row.seatType,
  updated: (row) => row.updatedAt,
}

const sortedTrips = computed(() => sortRows(filteredTrips.value, sort.value, sortGetters))
const sortKey = computed(() => sort.value?.key ?? '')
const sortDirection = computed<SortDirection>(() => sort.value?.direction ?? 'asc')

function changeSort(key: string): void {
  sort.value = nextSort(sort.value, key, SORT_INITIAL[key] ?? 'desc')
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    const [summary, list] = await Promise.all([
      api.user(props.userId),
      api.trips(props.userId, includeDeleted.value),
    ])
    user.value = summary
    trips.value = list
    if (!focusHandled && props.focusTripId) {
      focusHandled = true
      const target = list.find((trip) => trip.ticketId === props.focusTripId)
      if (target) {
        openEdit(target)
        toast('已定位到排行榜中的行程', 'info')
      } else {
        toast('没有找到对应的行程，可能已被彻底删除', 'error')
      }
    }
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取用户行程失败'
  } finally {
    loading.value = false
  }
}

async function toggleIncludeDeleted(): Promise<void> {
  includeDeleted.value = !includeDeleted.value
  await load()
}

function openCreate(): void {
  editingTrip.value = null
  editorOpen.value = true
}

function openEdit(trip: AdminTrip): void {
  editingTrip.value = trip
  editorOpen.value = true
}

async function handleSaved(): Promise<void> {
  editorOpen.value = false
  editingTrip.value = null
  await load()
}

function toInput(trip: AdminTrip, isDeleted: boolean): AdminTripInput {
  return {
    trainNumber: trip.trainNumber,
    travelDate: trip.travelDate,
    rollingStock: trip.rollingStock,
    companyName: trip.companyName,
    fromStation: trip.fromStation,
    toStation: trip.toStation,
    departureTime: trip.departureTime,
    arrivalTime: trip.arrivalTime,
    mileageKm: trip.mileageKm,
    viaRoutes: trip.viaRoutes,
    seatType: trip.seatType,
    seatNumber: trip.seatNumber,
    price: trip.price,
    notes: trip.notes,
    groupName: trip.groupName,
    isRailTrip: trip.isRailTrip,
    isDeleted,
  }
}

async function remove(trip: AdminTrip): Promise<void> {
  const label = `${trip.trainNumber} ${trip.fromStation} → ${trip.toStation}`
  if (
    !confirmDestructive({
      title: `删除行程「${label}」？`,
      message: `行程 ID #${trip.ticketId}，删除后用户同步时将不再收到该记录。`,
      reversible: true,
      footnote: '这是软删除，之后可以在本页「已删除」中恢复。',
    })
  )
    return
  try {
    await api.deleteTrip(trip.ticketId)
    toast('行程已删除，用户同步时会移除该记录', 'info')
    await load()
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '删除失败', 'error')
  }
}

async function restore(trip: AdminTrip): Promise<void> {
  try {
    await api.updateTrip(trip.ticketId, toInput(trip, false))
    toast('行程已恢复，用户同步时会重新收到该记录')
    await load()
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '恢复失败', 'error')
  }
}

async function copyId(id: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(id)
    toast('用户 ID 已复制', 'info')
  } catch {
    window.prompt('复制用户 ID', id)
  }
}

onMounted(load)
</script>

<template>
  <div class="page-stack">
    <button type="button" class="button ghost back-button" @click="emit('back')">
      <ArrowLeft :size="17" /> 返回用户列表
    </button>

    <section class="panel user-hero">
      <div class="user-hero-main">
        <img v-if="user?.avatarUrl" :src="user.avatarUrl" alt="" class="avatar large image" />
        <span v-else class="avatar large">{{ initials(user?.displayName ?? '?') }}</span>
        <div class="user-hero-copy">
          <h2>{{ user?.displayName ?? '读取中…' }}</h2>
          <p>
            <span>{{ user?.email || '未提供邮箱' }}</span>
            <button type="button" class="id-line" :title="userId" @click="copyId(userId)">
              <code>{{ userId }}</code>
              <Copy :size="12" />
            </button>
          </p>
          <p class="user-hero-meta">
            <span><UserRound :size="14" /> 注册于 {{ formatDate(user?.createdAt) }}</span>
            <span><TrainFront :size="14" /> {{ formatNumber(user?.tripCount ?? 0) }} 条有效行程</span>
            <span v-if="user && user.achievementExperience > 0">成就经验 {{ formatNumber(user.achievementExperience) }}</span>
          </p>
        </div>
      </div>
      <div class="user-hero-actions">
        <button type="button" class="button primary" @click="openCreate">
          <Plus :size="17" /> 新增行程
        </button>
      </div>
    </section>

    <section class="panel">
      <div class="panel-head">
        <div>
          <h2>行程记录</h2>
          <p>
            当前视图共 {{ formatNumber(filteredTrips.length) }} 条（有效 {{ formatNumber(activeCount) }}，
            已删除 {{ formatNumber(deletedCount) }}）。
          </p>
        </div>
        <div class="trip-toolbar">
          <label class="switch-row compact-switch">
            <span>包含已删除</span>
            <input
              :checked="includeDeleted"
              type="checkbox"
              class="switch"
              @change="toggleIncludeDeleted"
            />
          </label>
          <span class="search-input compact">
            <Search :size="16" />
            <input v-model="filter" type="search" placeholder="筛选车次、车站、备注…" />
          </span>
          <button type="button" class="button ghost small" :disabled="loading" @click="load">
            <RefreshCw :size="15" /> 刷新
          </button>
        </div>
      </div>

      <div v-if="loading" class="state-card inline">
        <LoaderCircle :size="20" class="spin" /><span>正在读取行程…</span>
      </div>
      <div v-else-if="error" class="state-card inline error">
        <TriangleAlert :size="20" /><span>{{ error }}</span>
        <button type="button" class="button ghost small" @click="load">
          <RefreshCw :size="15" /> 重试
        </button>
      </div>
      <div v-else-if="filteredTrips.length === 0" class="empty-state">
        <span class="empty-icon"><Inbox :size="30" /></span>
        <h3>{{ filter ? '没有匹配的行程' : '这位用户还没有行程' }}</h3>
        <p>{{ filter ? '换一个关键词试试。' : '可以使用「新增行程」为用户补录。' }}</p>
      </div>

      <div v-else class="table-wrap">
        <table class="data-table trips-table">
          <thead>
            <tr>
              <SortHeader class="col-status" label="状态" sort-key="status" :active="sortKey === 'status'" :direction="sortDirection" @sort="changeSort" />
              <SortHeader label="车次 / 日期" sort-key="train" :active="sortKey === 'train'" :direction="sortDirection" @sort="changeSort" />
              <SortHeader label="区间" sort-key="route" :active="sortKey === 'route'" :direction="sortDirection" @sort="changeSort" />
              <SortHeader label="里程" sort-key="mileage" align="right" :active="sortKey === 'mileage'" :direction="sortDirection" @sort="changeSort" />
              <SortHeader label="票价" sort-key="price" align="right" :active="sortKey === 'price'" :direction="sortDirection" @sort="changeSort" />
              <SortHeader label="席位" sort-key="seat" :active="sortKey === 'seat'" :direction="sortDirection" @sort="changeSort" />
              <SortHeader class="col-time" label="更新时间" sort-key="updated" :active="sortKey === 'updated'" :direction="sortDirection" @sort="changeSort" />
              <th class="col-actions">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="trip in sortedTrips"
              :key="trip.ticketId"
              :class="{ 'row-deleted': trip.deletedAt !== null }"
            >
              <td>
                <span :class="['pill', trip.deletedAt ? 'neutral' : 'success']">
                  {{ trip.deletedAt ? '已删除' : '正常' }}
                </span>
                <span v-if="!trip.isRailTrip" class="pill subtle">非铁路</span>
              </td>
              <td>
                <strong class="train-number">{{ trip.trainNumber }}</strong>
                <small class="sub-line">{{ formatDate(trip.travelDate) }}</small>
              </td>
              <td>
                <span class="station-pair">{{ trip.fromStation }} <span>→</span> {{ trip.toStation }}</span>
                <small v-if="trip.groupName" class="sub-line">{{ trip.groupName }}</small>
              </td>
              <td class="col-number">{{ formatMileage(trip.mileageKm) }}</td>
              <td class="col-number">{{ formatMoney(trip.price) }}</td>
              <td>
                <span v-if="trip.seatType || trip.seatNumber" class="sub-line">
                  {{ [trip.seatType, trip.seatNumber].filter(Boolean).join(' · ') }}
                </span>
                <span v-else class="muted-text">—</span>
              </td>
              <td class="muted-text">{{ formatDateTime(trip.updatedAt) }}</td>
              <td>
                <div class="row-actions">
                  <button type="button" class="button subtle small" @click="openEdit(trip)">
                    <Pencil :size="15" /> 编辑
                  </button>
                  <button
                    v-if="trip.deletedAt"
                    type="button"
                    class="button subtle small"
                    @click="restore(trip)"
                  >
                    <RotateCcw :size="15" /> 恢复
                  </button>
                  <button
                    v-else
                    type="button"
                    class="icon-button danger"
                    title="删除行程"
                    aria-label="删除行程"
                    @click="remove(trip)"
                  >
                    <Trash2 :size="16" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <TripEditorModal
      v-if="editorOpen"
      :user-id="userId"
      :trip="editingTrip"
      @close="editorOpen = false"
      @saved="handleSaved"
    />
  </div>
</template>
