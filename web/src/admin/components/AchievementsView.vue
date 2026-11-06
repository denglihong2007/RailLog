<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  ChevronLeft,
  ChevronRight,
  Eye,
  LoaderCircle,
  RefreshCw,
  Search,
  Trophy,
  TriangleAlert,
} from '@lucide/vue'
import {
  api,
  ApiError,
  PAGE_SIZE,
  type AdminAchievement,
  type AdminAchievementOverview,
  type AdminAchievementUnlock,
  type AdminAchievementUnlockPage,
} from '../api'
import { formatDate, formatDateTime, formatNumber, initials } from '../format'
import SortHeader from './SortHeader.vue'
import { nextSort, sortRows, type SortDirection, type SortState, type SortValue } from '../sort'
import LevelOverviewPanel from './LevelOverviewPanel.vue'

const emit = defineEmits<{
  'open-user': [id: string]
  'open-trip': [userId: string, ticketId: number]
  'open-level': [level: number]
}>()

const categoryLabels: Record<string, string> = {
  milestones: '历程丰碑',
  extremeChallenges: '极限挑战',
  railwayCatalog: '铁道图鉴',
  touring: '巡游四方',
  funJourneys: '趣味旅程',
}

const categoryOrder = ['milestones', 'extremeChallenges', 'railwayCatalog', 'touring', 'funJourneys']

const data = ref<AdminAchievementOverview | null>(null)
const loading = ref(true)
const error = ref('')
const category = ref('')
const query = ref('')
// 成就列表一次性取全量，排序在本地完成；默认沿用接口返回的分类顺序。
const sort = ref<SortState | null>(null)

const active = ref<AdminAchievement | null>(null)
const unlocks = ref<AdminAchievementUnlockPage | null>(null)
const unlocksLoading = ref(false)
const unlocksError = ref('')
const unlockOffset = ref(0)

const categories = computed(() => {
  const seen = new Set<string>()
  for (const item of data.value?.achievements ?? []) seen.add(item.category)
  return ['', ...categoryOrder.filter((item) => seen.has(item))]
})

const filtered = computed(() => {
  const items = data.value?.achievements ?? []
  const keyword = query.value.trim().toLowerCase()
  return items.filter((item) => {
    if (category.value && item.category !== category.value) return false
    if (!keyword) return true
    return (
      item.title.toLowerCase().includes(keyword) ||
      item.description.toLowerCase().includes(keyword) ||
      item.id.toLowerCase().includes(keyword)
    )
  })
})

const unachievedCount = computed(
  () => data.value?.achievements.filter((item) => item.unlockedUserCount === 0).length ?? 0,
)

const SORT_INITIAL: Record<string, SortDirection> = { title: 'asc', category: 'asc' }

const sortGetters: Record<string, (row: AdminAchievement) => SortValue> = {
  title: (row) => row.title,
  category: (row) => categoryOrder.indexOf(row.category),
  unlocked: (row) => row.unlockedUserCount,
  percent: (row) => row.unlockedPercent,
  latest: (row) => row.latestTriggerAt,
}

const sorted = computed(() => sortRows(filtered.value, sort.value, sortGetters))
const sortKey = computed(() => sort.value?.key ?? '')
const sortDirection = computed<SortDirection>(() => sort.value?.direction ?? 'asc')

function changeSort(key: string): void {
  sort.value = nextSort(sort.value, key, SORT_INITIAL[key] ?? 'desc')
}

const unlockPageStart = computed(() =>
  unlocks.value && unlocks.value.total > 0 ? unlockOffset.value + 1 : 0,
)
const unlockPageEnd = computed(() =>
  unlocks.value ? Math.min(unlockOffset.value + PAGE_SIZE, unlocks.value.total) : 0,
)
const hasPreviousUnlocks = computed(() => unlockOffset.value > 0)
const hasNextUnlocks = computed(
  () => unlocks.value !== null && unlockOffset.value + PAGE_SIZE < unlocks.value.total,
)

function categoryLabel(value: string): string {
  return categoryLabels[value] ?? value
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    data.value = await api.achievements()
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取成就数据失败'
  } finally {
    loading.value = false
  }
}

async function loadUnlocks(): Promise<void> {
  if (!active.value) return
  unlocksLoading.value = true
  unlocksError.value = ''
  try {
    unlocks.value = await api.achievementUnlocks(
      active.value.id,
      unlockOffset.value,
      PAGE_SIZE,
    )
  } catch (exception) {
    unlocksError.value = exception instanceof ApiError ? exception.message : '读取达成记录失败'
  } finally {
    unlocksLoading.value = false
  }
}

function openUnlocks(achievement: AdminAchievement): void {
  active.value = achievement
  unlocks.value = null
  unlockOffset.value = 0
  void loadUnlocks()
}

function closeUnlocks(): void {
  active.value = null
  unlocks.value = null
}

function previousUnlocks(): void {
  if (!hasPreviousUnlocks.value) return
  unlockOffset.value = Math.max(0, unlockOffset.value - PAGE_SIZE)
  void loadUnlocks()
}

function nextUnlocks(): void {
  if (!hasNextUnlocks.value) return
  unlockOffset.value += PAGE_SIZE
  void loadUnlocks()
}

function openUser(unlock: AdminAchievementUnlock): void {
  emit('open-user', unlock.userId)
}

function openTrip(unlock: AdminAchievementUnlock): void {
  emit('open-trip', unlock.userId, unlock.ticketId)
}

onMounted(load)
</script>

<template>
  <div class="page-stack">
    <LevelOverviewPanel
      @open-level="(level) => emit('open-level', level)"
      @recompute-finished="load"
    />

    <div v-if="loading" class="state-card">
      <LoaderCircle :size="22" class="spin" />
      <span>正在读取成就达成情况…</span>
    </div>

    <div v-else-if="error" class="state-card error">
      <TriangleAlert :size="22" />
      <span>{{ error }}</span>
      <button type="button" class="button ghost" @click="load"><RefreshCw :size="16" />重试</button>
    </div>

    <template v-else-if="data">
      <section class="stat-grid" aria-label="成就概况">
        <article class="stat-card">
          <span class="stat-icon amber"><Trophy :size="20" /></span>
          <div>
            <p class="stat-label">成就总数</p>
            <strong class="stat-value">{{ formatNumber(data.achievements.length) }}</strong>
            <p class="stat-hint">包含隐藏成就</p>
          </div>
        </article>
        <article class="stat-card">
          <span class="stat-icon green"><Trophy :size="20" /></span>
          <div>
            <p class="stat-label">累计达成次数</p>
            <strong class="stat-value">{{ formatNumber(data.totalUnlocks) }}</strong>
            <p class="stat-hint">所有用户解锁记录之和</p>
          </div>
        </article>
        <article class="stat-card">
          <span class="stat-icon red"><Eye :size="20" /></span>
          <div>
            <p class="stat-label">尚无人达成</p>
            <strong class="stat-value">{{ formatNumber(unachievedCount) }}</strong>
            <p class="stat-hint">可以检查触发条件是否过于苛刻</p>
          </div>
        </article>
      </section>

      <section class="panel">
        <div class="panel-head">
          <div>
            <h2><Trophy :size="17" /> 成就达成情况</h2>
            <p>管理员可查看达成人数与具体达成记录，但不能修改成就或用户数据。</p>
          </div>
        </div>

        <div class="tab-bar">
          <button
            v-for="item in categories"
            :key="item || 'all'"
            type="button"
            :class="['tab', { active: category === item }]"
            @click="category = item"
          >
            {{ item ? categoryLabel(item) : '全部' }}
          </button>
          <button type="button" class="tab refresh" title="重新读取" @click="load">
            <RefreshCw :size="15" />
          </button>
        </div>

        <form class="search-bar" @submit.prevent>
          <span class="search-input">
            <Search :size="18" />
            <input
              v-model="query"
              type="search"
              placeholder="搜索成就名称、描述或 ID"
              autocomplete="off"
            />
          </span>
        </form>

        <div v-if="sorted.length === 0" class="empty-state">
          <span class="empty-icon"><Trophy :size="30" /></span>
          <h3>没有匹配的成就</h3>
          <p>换一个分类或关键词试试。</p>
        </div>

        <div v-else class="table-wrap">
          <table class="data-table achievements-table">
            <thead>
              <tr>
                <SortHeader label="成就" sort-key="title" :active="sortKey === 'title'" :direction="sortDirection" @sort="changeSort" />
                <SortHeader label="类别" sort-key="category" :active="sortKey === 'category'" :direction="sortDirection" @sort="changeSort" />
                <SortHeader label="达成人数" sort-key="unlocked" align="right" :active="sortKey === 'unlocked'" :direction="sortDirection" @sort="changeSort" />
                <SortHeader label="达成率" sort-key="percent" align="right" :active="sortKey === 'percent'" :direction="sortDirection" @sort="changeSort" />
                <SortHeader class="col-time" label="最近触发" sort-key="latest" :active="sortKey === 'latest'" :direction="sortDirection" @sort="changeSort" />
                <th class="col-actions">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in sorted" :key="item.id">
                <td>
                  <div class="achievement-cell">
                    <Trophy :size="17" />
                    <div>
                      <strong>
                        {{ item.title }}
                        <span v-if="item.hidden" class="pill neutral">隐藏</span>
                      </strong>
                      <p>{{ item.description }}</p>
                      <small class="sub-line">
                        {{ item.id }} · {{ formatNumber(item.experience) }} 经验
                      </small>
                    </div>
                  </div>
                </td>
                <td><span class="pill subtle">{{ categoryLabel(item.category) }}</span></td>
                <td class="col-number">{{ formatNumber(item.unlockedUserCount) }}</td>
                <td class="col-number">{{ formatNumber(item.unlockedPercent, 1) }}%</td>
                <td class="col-time muted-text">
                  {{ item.latestTriggerAt ? formatDate(item.latestTriggerAt) : '—' }}
                </td>
                <td>
                  <button
                    type="button"
                    class="button subtle small"
                    @click="openUnlocks(item)"
                  >
                    <Eye :size="15" /> 达成记录
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>

    <div v-if="active" class="modal-backdrop" @click.self="closeUnlocks">
      <div class="modal wide" role="dialog" aria-modal="true" aria-labelledby="achievement-unlocks-title">
        <header class="modal-head">
          <div>
            <h2 id="achievement-unlocks-title">
              <Trophy :size="18" /> {{ active.title }}
            </h2>
            <p>
              {{ active.description }} · 共 {{ formatNumber(active.unlockedUserCount) }} 人达成
            </p>
          </div>
          <button type="button" class="icon-button" aria-label="关闭" @click="closeUnlocks">
            <span aria-hidden="true">✕</span>
          </button>
        </header>

        <div class="modal-body">
          <div v-if="unlocksLoading" class="state-card inline">
            <LoaderCircle :size="20" class="spin" /><span>正在读取达成记录…</span>
          </div>
          <div v-else-if="unlocksError" class="state-card inline error">
            <TriangleAlert :size="20" /><span>{{ unlocksError }}</span>
            <button type="button" class="button ghost small" @click="loadUnlocks">
              <RefreshCw :size="15" /> 重试
            </button>
          </div>
          <div v-else-if="!unlocks || unlocks.items.length === 0" class="empty-state">
            <span class="empty-icon"><Trophy :size="30" /></span>
            <h3>还没有用户达成</h3>
            <p>该成就暂无达成记录。</p>
          </div>

          <template v-else>
            <div class="table-wrap">
              <table class="data-table achievements-table">
                <thead>
                  <tr>
                    <th>用户</th>
                    <th>触发行程</th>
                    <th class="col-time">时间</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="unlock in unlocks.items" :key="`${unlock.userId}:${unlock.ticketId}`">
                    <td>
                      <button
                        type="button"
                        class="user-chip-button"
                        :title="`查看 ${unlock.displayName} 的行程`"
                        @click="openUser(unlock)"
                      >
                        <span class="avatar">{{ initials(unlock.displayName) }}</span>
                        <span class="user-chip-copy">
                          <strong>{{ unlock.displayName }}</strong>
                          <small>{{ unlock.email || '未提供邮箱' }}</small>
                        </span>
                      </button>
                    </td>
                    <td>
                      <button
                        type="button"
                        class="trip-link"
                        :title="`定位并编辑行程 #${unlock.ticketId}`"
                        @click="openTrip(unlock)"
                      >
                        {{ unlock.trainNumber }}
                        <span>{{ unlock.fromStation }} → {{ unlock.toStation }}</span>
                      </button>
                      <small class="sub-line">#{{ unlock.ticketId }}</small>
                      <span v-if="unlock.deletedAt" class="pill neutral">行程已删除</span>
                    </td>
                    <td class="col-time muted-text">{{ formatDateTime(unlock.triggeredAt) }}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="pagination">
              <span class="pagination-summary">
                <Trophy :size="15" />
                第 {{ unlockPageStart }}–{{ unlockPageEnd }} 条，共 {{ formatNumber(unlocks.total) }} 条记录
              </span>
              <div class="pagination-actions">
                <button
                  type="button"
                  class="button ghost small"
                  :disabled="!hasPreviousUnlocks || unlocksLoading"
                  @click="previousUnlocks"
                >
                  <ChevronLeft :size="16" /> 上一页
                </button>
                <button
                  type="button"
                  class="button ghost small"
                  :disabled="!hasNextUnlocks || unlocksLoading"
                  @click="nextUnlocks"
                >
                  下一页 <ChevronRight :size="16" />
                </button>
              </div>
            </div>
          </template>
        </div>

        <footer class="modal-foot">
          <button type="button" class="button ghost" @click="closeUnlocks">关闭</button>
        </footer>
      </div>
    </div>
  </div>
</template>
