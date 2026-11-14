<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  ChevronLeft,
  ChevronRight,
  Inbox,
  LoaderCircle,
  MessageSquareText,
  RefreshCw,
  Search,
  TriangleAlert,
  Users,
} from '@lucide/vue'
import {
  api,
  ApiError,
  PAGE_SIZE,
  type AdminReviewUser,
  type AdminReviewUserPage,
} from '../api'
import { formatDate, formatNumber, initials } from '../format'
import SortHeader from './SortHeader.vue'
import { nextSort, type SortDirection, type SortState } from '../sort'

const emit = defineEmits<{
  'open-user': [id: string]
  'view-reviews': [user: AdminReviewUser]
  'view-given': [user: AdminReviewUser]
  'view-received': [user: AdminReviewUser]
}>()

const query = ref('')
const submittedQuery = ref('')
const offset = ref(0)
// 服务端默认按评价数倒序，表头状态与之保持一致。
const sort = ref<SortState>({ key: 'reviews', direction: 'desc' })
const data = ref<AdminReviewUserPage | null>(null)
const loading = ref(true)
const error = ref('')

const pageStart = computed(() => (data.value && data.value.total > 0 ? offset.value + 1 : 0))
const pageEnd = computed(() =>
  data.value ? Math.min(offset.value + PAGE_SIZE, data.value.total) : 0,
)
const hasPrevious = computed(() => offset.value > 0)
const hasNext = computed(() => data.value !== null && offset.value + PAGE_SIZE < data.value.total)

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    data.value = await api.reviewUsers({
      query: submittedQuery.value,
      offset: offset.value,
      limit: PAGE_SIZE,
      sort: sort.value,
    })
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取评价用户失败'
  } finally {
    loading.value = false
  }
}

function search(): void {
  submittedQuery.value = query.value.trim()
  offset.value = 0
  void load()
}

const SORT_INITIAL: Record<string, SortDirection> = {
  user: 'asc',
}

function changeSort(key: string): void {
  sort.value = nextSort(sort.value, key, SORT_INITIAL[key] ?? 'desc')
  offset.value = 0
  void load()
}

function reset(): void {
  query.value = ''
  submittedQuery.value = ''
  offset.value = 0
  void load()
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

function rating(value: number | null): string {
  return value === null ? '—' : `${value.toFixed(1)} 星`
}

onMounted(load)
</script>

<template>
  <section class="panel">
    <div class="panel-head">
      <div>
        <h2><Users :size="17" /> 评价用户</h2>
        <p>按评价数、收到或发出的回应数排列用户，点数字可直接查看对应记录。</p>
      </div>
    </div>

    <form class="search-bar" @submit.prevent="search">
      <span class="search-input">
        <Search :size="18" />
        <input
          v-model="query"
          type="search"
          placeholder="搜索昵称或邮箱"
          autocomplete="off"
        />
      </span>
      <button type="submit" class="button primary" :disabled="loading">
        <Search :size="16" /> 搜索
      </button>
      <button type="button" class="button ghost" :disabled="loading" @click="reset">
        <RefreshCw :size="16" /> 重置
      </button>
    </form>

    <div v-if="loading" class="state-card inline">
      <LoaderCircle :size="20" class="spin" /><span>正在统计评价用户…</span>
    </div>
    <div v-else-if="error" class="state-card inline error">
      <TriangleAlert :size="20" /><span>{{ error }}</span>
      <button type="button" class="button ghost small" @click="load">
        <RefreshCw :size="15" /> 重试
      </button>
    </div>
    <div v-else-if="!data || data.items.length === 0" class="empty-state">
      <span class="empty-icon"><Inbox :size="30" /></span>
      <h3>没有找到用户</h3>
      <p>{{ submittedQuery ? '换一个昵称或邮箱试试。' : '目前还没有用户发表评价或作出回应。' }}</p>
    </div>

    <template v-else>
      <div class="table-wrap">
        <table class="data-table review-users-table">
          <thead>
            <tr>
              <SortHeader label="用户" sort-key="user" :active="sort.key === 'user'" :direction="sort.direction" @sort="changeSort" />
              <SortHeader label="评价数" sort-key="reviews" align="right" :active="sort.key === 'reviews'" :direction="sort.direction" @sort="changeSort" />
              <SortHeader label="收到回应" sort-key="received" align="right" :active="sort.key === 'received'" :direction="sort.direction" @sort="changeSort" />
              <SortHeader label="发出回应" sort-key="given" align="right" :active="sort.key === 'given'" :direction="sort.direction" @sort="changeSort" />
              <SortHeader label="平均评分" sort-key="rating" align="right" :active="sort.key === 'rating'" :direction="sort.direction" @sort="changeSort" />
              <SortHeader class="col-time" label="最近评价" sort-key="latest" :active="sort.key === 'latest'" :direction="sort.direction" @sort="changeSort" />
              <th class="col-actions">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="user in data.items" :key="user.userId">
              <td>
                <button
                  type="button"
                  class="user-chip-button"
                  :title="`查看 ${user.displayName} 的行程`"
                  @click="emit('open-user', user.userId)"
                >
                  <img v-if="user.avatarUrl" :src="user.avatarUrl" alt="" class="avatar image" />
                  <span v-else class="avatar">{{ initials(user.displayName) }}</span>
                  <span class="user-chip-copy">
                    <strong>{{ user.displayName }}</strong>
                    <small>{{ user.email || '未提供邮箱' }}</small>
                  </span>
                </button>
              </td>
              <td class="col-number">
                <button
                  type="button"
                  class="link-button count-link"
                  :disabled="user.reviewCount === 0"
                  title="查看该用户的全部评价"
                  @click="emit('view-reviews', user)"
                >
                  {{ formatNumber(user.reviewCount) }}
                </button>
              </td>
              <td class="col-number">
                <button
                  type="button"
                  class="link-button count-link"
                  :disabled="user.receivedReactionCount === 0"
                  title="查看该用户评价收到的回应"
                  @click="emit('view-received', user)"
                >
                  {{ formatNumber(user.receivedReactionCount) }}
                </button>
              </td>
              <td class="col-number">
                <button
                  type="button"
                  class="link-button count-link"
                  :disabled="user.givenReactionCount === 0"
                  title="查看该用户发出的回应"
                  @click="emit('view-given', user)"
                >
                  {{ formatNumber(user.givenReactionCount) }}
                </button>
              </td>
              <td class="col-number">{{ rating(user.averageRating) }}</td>
              <td class="muted-text col-time">
                {{ user.latestReviewAt ? formatDate(user.latestReviewAt) : '—' }}
              </td>
              <td>
                <div class="row-actions">
                  <button
                    type="button"
                    class="button subtle small"
                    :disabled="user.reviewCount === 0"
                    @click="emit('view-reviews', user)"
                  >
                    <MessageSquareText :size="15" /> 查看评价
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="pagination">
        <span class="pagination-summary">
          <Users :size="15" />
          第 {{ pageStart }}–{{ pageEnd }} 条，共 {{ formatNumber(data.total) }} 位用户
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
</template>
