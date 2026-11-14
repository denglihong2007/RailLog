<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import {
  ChevronLeft,
  ChevronRight,
  ExternalLink,
  Eye,
  Inbox,
  LoaderCircle,
  MessageSquareText,
  RefreshCw,
  Search,
  Trash2,
  TriangleAlert,
  UserRound,
} from '@lucide/vue'
import { api, ApiError, PAGE_SIZE, type AdminReview, type AdminReviewPage } from '../api'
import { confirmDestructive } from '../confirm'
import { formatDate, formatDateTime, formatNumber, initials } from '../format'
import SortHeader from './SortHeader.vue'
import ReviewReactionList from './ReviewReactionList.vue'
import { nextSort, type SortDirection, type SortState } from '../sort'
import { toast } from '../toast'

const props = withDefaults(
  defineProps<{
    initialQuery?: string
    initialEntityType?: string
    userId?: string
    userName?: string
  }>(),
  { initialQuery: '', initialEntityType: '', userId: '', userName: '' },
)

const emit = defineEmits<{
  'open-user': [id: string]
  'open-trip': [userId: string, ticketId: number]
  'view-author': [userId: string, displayName: string]
  'clear-author': []
}>()

const entityTypeLabels: Record<string, string> = {
  station: '车站',
  train: '车次',
  company: '承运单位',
  rollingstock: '车型',
  route: '线路',
}

const reviewTypeLabels: Record<string, string> = {
  station: '车站服务',
  transfer: '换乘接驳',
  company: '承运单位服务',
  meal: '餐饮服务',
  route: '乘坐体验（线路）',
  rollingStock: '乘坐体验（车型）',
  train: '乘坐体验（车次）',
}

function entityTypeLabel(type: string): string {
  return entityTypeLabels[type.toLowerCase()] ?? type
}

function reviewTypeLabel(type: string): string {
  return reviewTypeLabels[type] ?? type
}

const query = ref(props.initialQuery)
const submittedQuery = ref(props.initialQuery.trim())
const entityType = ref(props.initialEntityType)
const reviewType = ref('')
const offset = ref(0)
// 服务端默认按创建时间倒序，表头状态与之保持一致。
const sort = ref<SortState>({ key: 'created', direction: 'desc' })
const data = ref<AdminReviewPage | null>(null)
const loading = ref(true)
const error = ref('')
const detail = ref<AdminReview | null>(null)
const deletingId = ref<number | null>(null)

const hasAuthorFilter = computed(() => props.userId.length > 0)
const authorLabel = computed(() => props.userName || props.userId || '该用户')
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
    data.value = await api.reviews({
      query: submittedQuery.value,
      entityType: entityType.value,
      reviewType: reviewType.value,
      userId: props.userId,
      offset: offset.value,
      limit: PAGE_SIZE,
      sort: sort.value,
    })
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取评价失败'
  } finally {
    loading.value = false
  }
}

function search(): void {
  submittedQuery.value = query.value.trim()
  offset.value = 0
  void load()
}

function changeFilter(): void {
  offset.value = 0
  void load()
}

/** 文本列先升序，评分、回应与时间列先降序（先看高分、热门与最新）。 */
const SORT_INITIAL: Record<string, SortDirection> = {
  user: 'asc',
  entity: 'asc',
}

function changeSort(key: string): void {
  sort.value = nextSort(sort.value, key, SORT_INITIAL[key] ?? 'desc')
  offset.value = 0
  void load()
}

function reset(): void {
  query.value = ''
  submittedQuery.value = ''
  entityType.value = ''
  reviewType.value = ''
  offset.value = 0
  if (hasAuthorFilter.value) emit('clear-author')
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

function openDetail(review: AdminReview): void {
  detail.value = review
}

function handleReactionsChanged(count: number): void {
  if (!detail.value) return
  detail.value.reactionCount = count
  const row = data.value?.items.find((item) => item.id === detail.value?.id)
  if (row) row.reactionCount = count
}

async function remove(review: AdminReview): Promise<void> {
  const preview = review.comment.length > 80 ? `${review.comment.slice(0, 80)}…` : review.comment
  const confirmed = confirmDestructive({
    title: '删除这条评价',
    message: `${preview}\n\n评价及其收到的回应都会被永久删除，作者的评价类成就会立即重算。`,
  })
  if (!confirmed) return
  deletingId.value = review.id
  try {
    await api.deleteReview(review.id)
    toast('评价已删除', 'info')
    detail.value = null
    if (data.value && data.value.items.length === 1 && offset.value > 0) {
      offset.value = Math.max(0, offset.value - PAGE_SIZE)
    }
    await load()
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '删除失败', 'error')
  } finally {
    deletingId.value = null
  }
}

function stars(rating: number): string {
  return '★★★★★'.slice(0, Math.max(0, Math.min(5, rating)))
}

watch(
  () => [props.initialQuery, props.initialEntityType, props.userId] as const,
  ([nextQuery, nextType, nextUserId], previous) => {
    const userIdChanged = previous !== undefined && previous[2] !== nextUserId
    query.value = nextQuery
    submittedQuery.value = nextQuery.trim()
    entityType.value = nextType
    offset.value = 0
    if (userIdChanged) reviewType.value = ''
    void load()
  },
)

onMounted(load)
</script>

<template>
  <section class="panel">
    <div class="panel-head">
      <div>
        <h2><MessageSquareText :size="17" /> 评价列表</h2>
        <p>检索、查看并删除用户评价。删除会连带清除该评价收到的回应，并触发作者成就重算。</p>
      </div>
    </div>

    <p v-if="hasAuthorFilter" class="filter-note">
      正在查看「{{ authorLabel }}」的全部评价
      <button type="button" class="link-button" @click="emit('clear-author')">
        显示全部作者
      </button>
    </p>

    <form class="search-bar" @submit.prevent="search">
      <span class="search-input">
        <Search :size="18" />
        <input
          v-model="query"
          type="search"
          placeholder="搜索评价内容、实体、昵称、邮箱或车次"
          autocomplete="off"
        />
      </span>
      <select v-model="entityType" class="select" @change="changeFilter">
        <option value="">全部实体</option>
        <option value="station">车站</option>
        <option value="train">车次</option>
        <option value="company">承运单位</option>
        <option value="rollingStock">车型</option>
        <option value="route">线路</option>
      </select>
      <select v-model="reviewType" class="select" @change="changeFilter">
        <option value="">全部类型</option>
        <option value="station">车站服务</option>
        <option value="transfer">换乘接驳</option>
        <option value="company">承运单位服务</option>
        <option value="route">乘坐体验（线路）</option>
        <option value="rollingStock">乘坐体验（车型）</option>
        <option value="train">乘坐体验（车次）</option>
        <option value="meal">餐饮服务</option>
      </select>
      <button type="submit" class="button primary" :disabled="loading">
        <Search :size="16" /> 搜索
      </button>
      <button type="button" class="button ghost" :disabled="loading" @click="reset">
        <RefreshCw :size="16" /> 重置
      </button>
    </form>

    <div v-if="loading" class="state-card inline">
      <LoaderCircle :size="20" class="spin" /><span>正在读取评价…</span>
    </div>
    <div v-else-if="error" class="state-card inline error">
      <TriangleAlert :size="20" /><span>{{ error }}</span>
      <button type="button" class="button ghost small" @click="load">
        <RefreshCw :size="15" /> 重试
      </button>
    </div>
    <div v-else-if="!data || data.items.length === 0" class="empty-state">
      <span class="empty-icon"><Inbox :size="30" /></span>
      <h3>没有找到评价</h3>
      <p>{{ submittedQuery || entityType || reviewType || hasAuthorFilter ? '换一个关键词或筛选条件试试。' : '目前还没有用户发表评价。' }}</p>
    </div>

    <template v-else>
      <div class="table-wrap">
        <table class="data-table reviews-table">
          <thead>
            <tr>
              <SortHeader class="col-time" label="时间" sort-key="created" :active="sort.key === 'created'" :direction="sort.direction" @sort="changeSort" />
              <SortHeader label="用户" sort-key="user" :active="sort.key === 'user'" :direction="sort.direction" @sort="changeSort" />
              <SortHeader label="评价对象" sort-key="entity" :active="sort.key === 'entity'" :direction="sort.direction" @sort="changeSort" />
              <SortHeader class="col-rating" label="评分" sort-key="rating" :active="sort.key === 'rating'" :direction="sort.direction" @sort="changeSort" />
              <th>评价内容</th>
              <th class="col-time">关联行程</th>
              <SortHeader label="回应" sort-key="reactions" align="right" :active="sort.key === 'reactions'" :direction="sort.direction" @sort="changeSort" />
              <th class="col-actions">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="review in data.items" :key="review.id">
              <td class="muted-text col-time">{{ formatDate(review.createdAt) }}</td>
              <td>
                <button
                  type="button"
                  class="user-chip-button"
                  :title="`查看 ${review.displayName} 的行程`"
                  @click="emit('open-user', review.userId)"
                >
                  <img v-if="review.avatarUrl" :src="review.avatarUrl" alt="" class="avatar image" />
                  <span v-else class="avatar">{{ initials(review.displayName) }}</span>
                  <span class="user-chip-copy">
                    <strong>{{ review.displayName }}</strong>
                    <small>{{ review.email || '未提供邮箱' }}</small>
                  </span>
                </button>
                <button
                  type="button"
                  class="link-button author-reviews-link"
                  @click="emit('view-author', review.userId, review.displayName)"
                >
                  该作者的全部评价
                </button>
              </td>
              <td>
                <span class="pill subtle">{{ entityTypeLabel(review.entityType) }}</span>
                <div class="entity-key" :title="review.entityKey">{{ review.entityKey || '—' }}</div>
                <small class="sub-line">{{ reviewTypeLabel(review.reviewType) }}</small>
              </td>
              <td class="col-rating">
                <span class="stars" :aria-label="`${review.rating} 星`">{{ stars(review.rating) }}</span>
              </td>
              <td>
                <p class="review-comment">{{ review.comment }}</p>
              </td>
              <td class="col-time">
                <template v-if="review.trip">
                  <button
                    type="button"
                    class="trip-link"
                    :title="`定位并编辑行程 #${review.trip.ticketId}`"
                    @click="emit('open-trip', review.userId, review.trip.ticketId)"
                  >
                    {{ review.trip.trainNumber }}
                    <span>{{ review.trip.fromStation }} → {{ review.trip.toStation }}</span>
                    <ExternalLink :size="12" />
                  </button>
                  <span v-if="review.trip.deletedAt" class="pill neutral">行程已删除</span>
                </template>
                <span v-else class="muted-text">—</span>
              </td>
              <td class="col-number">
                <button
                  type="button"
                  class="reaction-count-button"
                  title="查看这条评价的全部回应"
                  @click="openDetail(review)"
                >
                  <MessageSquareText :size="14" />
                  {{ formatNumber(review.reactionCount) }}
                </button>
              </td>
              <td>
                <div class="row-actions">
                  <button type="button" class="button subtle small" @click="openDetail(review)">
                    <Eye :size="15" /> 详情
                  </button>
                  <button
                    type="button"
                    class="icon-button danger"
                    title="删除评价"
                    :disabled="deletingId === review.id"
                    @click="remove(review)"
                  >
                    <LoaderCircle v-if="deletingId === review.id" :size="16" class="spin" />
                    <Trash2 v-else :size="16" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="pagination">
        <span class="pagination-summary">
          <MessageSquareText :size="15" />
          第 {{ pageStart }}–{{ pageEnd }} 条，共 {{ formatNumber(data.total) }} 条评价
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

    <div v-if="detail" class="modal-backdrop" @click.self="detail = null">
      <div class="modal narrow" role="dialog" aria-modal="true" aria-labelledby="review-detail-title">
        <header class="modal-head">
          <div>
            <h2 id="review-detail-title">评价详情</h2>
            <p>#{{ detail.id }} · {{ formatDateTime(detail.createdAt) }}</p>
          </div>
          <button type="button" class="icon-button" aria-label="关闭" @click="detail = null">
            <span aria-hidden="true">✕</span>
          </button>
        </header>
        <div class="modal-body">
          <section class="form-section">
            <div class="review-detail-meta">
              <div>
                <span class="field-label">评价用户</span>
                <button type="button" class="user-chip-button" @click="emit('open-user', detail.userId)">
                  <img v-if="detail.avatarUrl" :src="detail.avatarUrl" alt="" class="avatar image" />
                  <span v-else class="avatar">{{ initials(detail.displayName) }}</span>
                  <span class="user-chip-copy">
                    <strong>{{ detail.displayName }}</strong>
                    <small>{{ detail.email || '未提供邮箱' }}</small>
                  </span>
                </button>
                <button
                  type="button"
                  class="link-button"
                  @click="emit('view-author', detail.userId, detail.displayName)"
                >
                  查看该作者的全部评价
                </button>
              </div>
              <div>
                <span class="field-label">评价对象</span>
                <p class="detail-value">
                  {{ entityTypeLabel(detail.entityType) }} · {{ detail.entityKey }}
                </p>
                <small class="sub-line">{{ reviewTypeLabel(detail.reviewType) }}</small>
              </div>
              <div>
                <span class="field-label">评分</span>
                <p class="detail-value stars">{{ stars(detail.rating) }}</p>
                <small class="sub-line">收到 {{ formatNumber(detail.reactionCount) }} 个回应</small>
              </div>
            </div>
          </section>

          <section class="form-section">
            <span class="field-label">评价内容</span>
            <p class="review-detail-comment">{{ detail.comment }}</p>
            <p v-if="detail.routeFromStation || detail.routeToStation" class="sub-line">
              区间：{{ detail.routeFromStation || '—' }} → {{ detail.routeToStation || '—' }}
            </p>
            <p v-if="detail.dish" class="sub-line">餐食：{{ detail.dish }}</p>
            <p v-if="detail.price !== null" class="sub-line">价格：¥{{ detail.price.toFixed(2) }}</p>
          </section>

          <section v-if="detail.trip" class="form-section">
            <span class="field-label">关联行程</span>
            <button
              type="button"
              class="trip-link"
              @click="emit('open-trip', detail.userId, detail.trip.ticketId)"
            >
              <strong>{{ detail.trip.trainNumber }}</strong>
              {{ detail.trip.fromStation }} → {{ detail.trip.toStation }}
              · {{ formatDate(detail.trip.travelDate) }}
              <ExternalLink :size="12" />
            </button>
            <span v-if="detail.trip.deletedAt" class="pill neutral">行程已删除</span>
          </section>

          <ReviewReactionList :review-id="detail.id" @changed="handleReactionsChanged" />
        </div>
        <footer class="modal-foot split">
          <span class="modal-foot-note">
            <UserRound :size="14" /> 删除评价会影响作者的评价类成就
          </span>
          <div class="modal-foot-actions">
            <button type="button" class="button ghost" @click="detail = null">关闭</button>
            <button
              type="button"
              class="button danger"
              :disabled="deletingId === detail.id"
              @click="remove(detail)"
            >
              <LoaderCircle v-if="deletingId === detail.id" :size="16" class="spin" />
              <Trash2 v-else :size="16" />
              删除评价
            </button>
          </div>
        </footer>
      </div>
    </div>
  </section>
</template>
