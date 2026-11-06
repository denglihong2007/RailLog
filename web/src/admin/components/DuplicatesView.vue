<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  ArrowLeft,
  ChevronLeft,
  ChevronRight,
  Copy,
  LoaderCircle,
  RefreshCw,
  TriangleAlert,
  Wrench,
} from '@lucide/vue'
import {
  api,
  ApiError,
  PAGE_SIZE,
  type AdminDuplicateGroup,
  type AdminDuplicateGroupPage,
  type AdminDuplicateTrip,
} from '../api'
import {
  confirmDeleteDuplicateTrips,
  confirmResolveAllDuplicateGroups,
  deleteDuplicateTrips,
} from '../duplicates'
import { formatNumber } from '../format'
import { toast } from '../toast'
import DuplicateGroups from './DuplicateGroups.vue'

const emit = defineEmits<{
  back: []
  'open-user': [id: string]
  'open-trip': [userId: string, ticketId: number]
}>()

const data = ref<AdminDuplicateGroupPage | null>(null)
const loading = ref(true)
const error = ref('')
const offset = ref(0)
const busy = ref(false)
const resolving = ref(false)

const pageStart = computed(() => (data.value && data.value.totalGroups > 0 ? offset.value + 1 : 0))
const pageEnd = computed(() =>
  data.value ? Math.min(offset.value + PAGE_SIZE, data.value.totalGroups) : 0,
)
const hasPrevious = computed(() => offset.value > 0)
const hasNext = computed(
  () => data.value !== null && offset.value + PAGE_SIZE < data.value.totalGroups,
)

async function load(silent = false): Promise<void> {
  if (!silent) loading.value = true
  error.value = ''
  try {
    data.value = await api.duplicates(offset.value, PAGE_SIZE)
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取重复行程失败'
  } finally {
    if (!silent) loading.value = false
  }
}

function previous(): void {
  if (!hasPrevious.value) return
  offset.value = Math.max(0, offset.value - PAGE_SIZE)
  void load()
}

function next(): void {
  if (!hasNext.value) return
  offset.value += PAGE_SIZE
  void load()
}

async function deleteTrip(trip: AdminDuplicateTrip): Promise<void> {
  if (!confirmDeleteDuplicateTrips([trip])) return
  busy.value = true
  try {
    const result = await deleteDuplicateTrips([trip])
    if (result.failed.length > 0) toast(result.failed[0] ?? '删除失败', 'error')
    else toast('已删除该条重复行程', 'info')
    await load(true)
  } finally {
    busy.value = false
  }
}

async function resolveAll(): Promise<void> {
  if (!data.value) return
  if (!confirmResolveAllDuplicateGroups(data.value.totalGroups, data.value.totalTrips)) return
  resolving.value = true
  try {
    const result = await api.resolveDuplicates()
    if (result.deletedTrips === 0) {
      toast('没有需要处理的重复行程', 'info')
    } else {
      toast(
        `已处理 ${formatNumber(result.groups)} 组重复行程，保留每组最早录入的一条，` +
          `共删除 ${formatNumber(result.deletedTrips)} 条`,
        'info',
      )
    }
    offset.value = 0
    await load(true)
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '一键处理失败', 'error')
  } finally {
    resolving.value = false
  }
}

async function keepEarliest(group: AdminDuplicateGroup): Promise<void> {
  const keep = group.trips[0]
  const removed = group.trips.slice(1)
  if (!keep) return
  if (!confirmDeleteDuplicateTrips(removed)) return
  busy.value = true
  try {
    const result = await deleteDuplicateTrips(removed)
    if (result.failed.length > 0) {
      toast(`保留 #${keep.ticketId}，但有 ${result.failed.length} 条删除失败`, 'error')
    } else {
      toast(`已保留最早录入的 #${keep.ticketId}，删除其余 ${removed.length} 条`, 'info')
    }
    await load(true)
  } finally {
    busy.value = false
  }
}

onMounted(() => {
  void load()
})
</script>

<template>
  <div class="page-stack">
    <button type="button" class="button ghost back-button" @click="emit('back')">
      <ArrowLeft :size="16" /> 返回概览
    </button>

    <div v-if="loading" class="state-card">
      <LoaderCircle :size="22" class="spin" />
      <span>正在读取重复行程…</span>
    </div>

    <div v-else-if="error" class="state-card error">
      <TriangleAlert :size="22" />
      <span>{{ error }}</span>
      <button type="button" class="button ghost" @click="load()">
        <RefreshCw :size="16" />重试
      </button>
    </div>

    <section v-else-if="data" class="panel">
      <div class="panel-head">
        <div>
          <h2><Copy :size="17" /> 疑似重复行程</h2>
          <p>
            同一用户、同一车次、同一乘车日期，且始发终到站、票价、里程都相同，却存在多条有效记录，常见于重复导入。
            共 <strong>{{ formatNumber(data.totalGroups) }}</strong> 组 /
            <strong>{{ formatNumber(data.totalTrips) }}</strong> 条。
            删除为软删除，可在对应用户的「行程管理」中恢复。
          </p>
        </div>
        <div class="panel-head-actions">
          <button type="button" class="button ghost small" :disabled="loading || resolving" @click="load()">
            <RefreshCw :size="15" /> 刷新
          </button>
          <button
            type="button"
            class="button danger small"
            title="全站每组保留最早录入的一条，删除其余重复记录"
            :disabled="busy || resolving || loading || data.totalGroups === 0"
            @click="resolveAll"
          >
            <LoaderCircle v-if="resolving" :size="15" class="spin" />
            <Wrench v-else :size="15" />
            {{ resolving ? '处理中…' : '一键处理全部' }}
          </button>
        </div>
      </div>

      <div v-if="data.items.length === 0" class="empty-state">
        <span class="empty-icon"><Copy :size="30" /></span>
        <h3>没有疑似重复行程</h3>
        <p>当前所有有效行程都是唯一的。</p>
      </div>

      <template v-else>
        <DuplicateGroups
          :groups="data.items"
          :busy="busy || resolving"
          @delete-trip="deleteTrip"
          @keep-earliest="keepEarliest"
          @open-trip="(userId, ticketId) => emit('open-trip', userId, ticketId)"
          @open-user="(userId) => emit('open-user', userId)"
        />

        <div class="pagination">
          <span class="pagination-summary">
            <Copy :size="15" />
            第 {{ pageStart }}–{{ pageEnd }} 组，共 {{ formatNumber(data.totalGroups) }} 组
          </span>
          <div class="pagination-actions">
            <button type="button" class="button ghost small" :disabled="!hasPrevious || loading" @click="previous">
              <ChevronLeft :size="16" /> 上一页
            </button>
            <button type="button" class="button ghost small" :disabled="!hasNext || loading" @click="next">
              下一页 <ChevronRight :size="16" />
            </button>
          </div>
        </div>
      </template>
    </section>
  </div>
</template>
