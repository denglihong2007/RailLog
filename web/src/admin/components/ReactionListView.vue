<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import {
  ChevronLeft,
  ChevronRight,
  Eye,
  Inbox,
  LoaderCircle,
  MessageSquareText,
  RefreshCw,
  Search,
  Trash2,
  TriangleAlert,
} from '@lucide/vue'
import { api, ApiError, PAGE_SIZE, type AdminReaction, type AdminReactionPage } from '../api'
import { confirmDestructive } from '../confirm'
import { formatDate, formatDateTime, formatNumber, initials } from '../format'
import SortHeader from './SortHeader.vue'
import ReviewReactionList from './ReviewReactionList.vue'
import { nextSort, type SortDirection, type SortState } from '../sort'
import { toast } from '../toast'

const props = withDefaults(
  defineProps<{
    reactorId?: string
    reactorName?: string
    authorId?: string
    authorName?: string
  }>(),
  { reactorId: '', reactorName: '', authorId: '', authorName: '' },
)

const emit = defineEmits<{
  'open-user': [id: string]
  'clear-reactor': []
  'clear-author': []
}>()

const emojiOptions = ['👍', '❤️', '😂', '😮', '😢', '🎉', '🥵', '🤔', '❔']

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

const query = ref('')
const submittedQuery = ref('')
const emoji = ref('')
const entityType = ref('')
const offset = ref(0)
const sort = ref<SortState>({ key: 'created', direction: 'desc' })
const data = ref<AdminReactionPage | null>(null)
const loading = ref(true)
const error = ref('')
const detail = ref<AdminReaction | null>(null)
const deletingKey = ref('')

const hasUserFilter = computed(() => props.reactorId.length > 0 || props.authorId.length > 0)
const pageStart = computed(() => (data.value && data.value.total > 0 ? offset.value + 1 : 0))
const pageEnd = computed(() =>
  data.value ? Math.min(offset.value + PAGE_SIZE, data.value.total) : 0,
)
const hasPrevious = computed(() => offset.value > 0)
const hasNext = computed(() => data.value !== null && offset.value + PAGE_SIZE < data.value.total)

function rowKey(item: AdminReaction): string {
  return `${item.reviewId}:${item.userId}`
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    data.value = await api.reactions({
      query: submittedQuery.value,
      emoji: emoji.value,
      entityType: entityType.value,
      reactorId: props.reactorId,
      authorId: props.authorId,
      offset: offset.value,
      limit: PAGE_SIZE,
      sort: sort.value,
    })
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取回应失败'
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

const SORT_INITIAL: Record<string, SortDirection> = {
  user: 'asc',
  author: 'asc',
  entity: 'asc',
  emoji: 'asc',
}

function changeSort(key: string): void {
  sort.value = nextSort(sort.value, key, SORT_INITIAL[key] ?? 'desc')
  offset.value = 0
  void load()
}

function reset(): void {
  query.value = ''
  submittedQuery.value = ''
  emoji.value = ''
  entityType.value = ''
  offset.value = 0
  if (hasUserFilter.value) {
    emit('clear-reactor')
    emit('clear-author')
  }
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

async function remove(item: AdminReaction): Promise<void> {
  const confirmed = confirmDestructive({
    title: `删除 ${item.displayName} 的回应`,
    message: `将从「${item.reviewAuthorName}」的评价上移除表情 ${item.emoji}。`,
    footnote: '评价作者的「收到回应」类成就会立即重算。此操作无法撤销。',
  })
  if (!confirmed) return

  const key = rowKey(item)
  deletingKey.value = key
  try {
    await api.deleteReviewReaction(item.reviewId, item.userId)
    toast('回应已删除', 'info')
    if (detail.value && detail.value.reviewId === item.reviewId) detail.value = null
    await load()
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '删除回应失败', 'error')
  } finally {
    deletingKey.value = ''
  }
}

function handleReactionsChanged(): void {
  void load()
}

watch(
  () => [props.reactorId, props.authorId] as const,
  () => {
    offset.value = 0
    void load()
  },
)

onMounted(load)
</script>

<template>
  <section class="panel">
    <div class="panel-head">
      <div>
        <h2><MessageSquareText :size="17" /> 回应列表</h2>
        <p>按回应者、表情与关键词检索用户对评价的表情回应，可逐条删除。</p>
      </div>
    </div>

    <p v-if="hasUserFilter" class="filter-note">
      <template v-if="props.reactorId">
        回应者：{{ props.reactorName || props.reactorId }}
      </template>
      <template v-if="props.reactorId && props.authorId"> · </template>
      <template v-if="props.authorId">
        评价作者：{{ props.authorName || props.authorId }}
      </template>
      <button type="button" class="link-button" @click="emit('clear-reactor'); emit('clear-author')">
        清除用户筛选
      </button>
    </p>

    <form class="search-bar" @submit.prevent="search">
      <span class="search-input">
        <Search :size="18" />
        <input
          v-model="query"
          type="search"
          placeholder="搜索回应者、评价作者、评价内容或实体"
          autocomplete="off"
        />
      </span>
      <select v-model="emoji" class="select" aria-label="按表情筛选" @change="changeFilter">
        <option value="">全部表情</option>
        <option v-for="option in emojiOptions" :key="option" :value="option">
          {{ option }}
        </option>
      </select>
      <select v-model="entityType" class="select" aria-label="按实体筛选" @change="changeFilter">
        <option value="">全部实体</option>
        <option value="station">车站</option>
        <option value="train">车次</option>
        <option value="company">承运单位</option>
        <option value="rollingStock">车型</option>
        <option value="route">线路</option>
      </select>
      <button type="submit" class="button primary" :disabled="loading">
        <Search :size="16" /> 搜索
      </button>
      <button type="button" class="button ghost" :disabled="loading" @click="reset">
        <RefreshCw :size="16" /> 重置
      </button>
    </form>

    <div v-if="loading" class="state-card inline">
      <LoaderCircle :size="20" class="spin" /><span>正在读取回应…</span>
    </div>
    <div v-else-if="error" class="state-card inline error">
      <TriangleAlert :size="20" /><span>{{ error }}</span>
      <button type="button" class="button ghost small" @click="load">
        <RefreshCw :size="15" /> 重试
      </button>
    </div>
    <div v-else-if="!data || data.items.length === 0" class="empty-state">
      <span class="empty-icon"><Inbox :size="30" /></span>
      <h3>没有找到回应</h3>
      <p>{{ submittedQuery || emoji || entityType || hasUserFilter ? '换一个关键词或筛选条件试试。' : '目前还没有用户对评价作出回应。' }}</p>
    </div>

    <template v-else>
      <div class="table-wrap">
        <table class="data-table reactions-table">
          <thead>
            <tr>
              <SortHeader class="col-time" label="时间" sort-key="created" :active="sort.key === 'created'" :direction="sort.direction" @sort="changeSort" />
              <SortHeader label="回应者" sort-key="user" :active="sort.key === 'user'" :direction="sort.direction" @sort="changeSort" />
              <SortHeader class="col-emoji" label="表情" sort-key="emoji" :active="sort.key === 'emoji'" :direction="sort.direction" @sort="changeSort" />
              <th>被回应的评价</th>
              <SortHeader label="评价作者" sort-key="author" :active="sort.key === 'author'" :direction="sort.direction" @sort="changeSort" />
              <th class="col-actions">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="item in data.items" :key="rowKey(item)">
              <td class="muted-text col-time">{{ formatDate(item.createdAt) }}</td>
              <td>
                <button
                  type="button"
                  class="user-chip-button"
                  :title="`查看 ${item.displayName} 的行程`"
                  @click="emit('open-user', item.userId)"
                >
                  <img v-if="item.avatarUrl" :src="item.avatarUrl" alt="" class="avatar image" />
                  <span v-else class="avatar">{{ initials(item.displayName) }}</span>
                  <span class="user-chip-copy">
                    <strong>{{ item.displayName }}</strong>
                    <small>{{ item.email || '未提供邮箱' }}</small>
                  </span>
                </button>
              </td>
              <td class="col-emoji"><span class="reaction-emoji">{{ item.emoji }}</span></td>
              <td>
                <span class="pill subtle">{{ entityTypeLabel(item.entityType) }}</span>
                <div class="entity-key" :title="item.entityKey">{{ item.entityKey || '—' }}</div>
                <small class="sub-line">{{ reviewTypeLabel(item.reviewType) }} · {{ item.reviewRating }} 星</small>
                <p class="review-comment reaction-review-comment">{{ item.reviewComment }}</p>
                <span class="muted-text sub-line">发表于 {{ formatDate(item.reviewCreatedAt) }}</span>
              </td>
              <td>
                <button
                  type="button"
                  class="user-chip-button"
                  :title="`查看 ${item.reviewAuthorName} 的行程`"
                  @click="emit('open-user', item.reviewAuthorId)"
                >
                  <span class="avatar">{{ initials(item.reviewAuthorName) }}</span>
                  <span class="user-chip-copy">
                    <strong>{{ item.reviewAuthorName }}</strong>
                    <small>{{ item.reviewAuthorEmail || '未提供邮箱' }}</small>
                  </span>
                </button>
              </td>
              <td>
                <div class="row-actions">
                  <button type="button" class="button subtle small" @click="detail = item">
                    <Eye :size="15" /> 详情
                  </button>
                  <button
                    type="button"
                    class="icon-button danger"
                    title="删除回应"
                    :disabled="deletingKey === rowKey(item)"
                    @click="remove(item)"
                  >
                    <LoaderCircle v-if="deletingKey === rowKey(item)" :size="16" class="spin" />
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
          第 {{ pageStart }}–{{ pageEnd }} 条，共 {{ formatNumber(data.total) }} 条回应
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
      <div class="modal narrow" role="dialog" aria-modal="true" aria-labelledby="reaction-detail-title">
        <header class="modal-head">
          <div>
            <h2 id="reaction-detail-title">回应详情</h2>
            <p>评价 #{{ detail.reviewId }} · {{ formatDateTime(detail.createdAt) }}</p>
          </div>
          <button type="button" class="icon-button" aria-label="关闭" @click="detail = null">
            <span aria-hidden="true">✕</span>
          </button>
        </header>
        <div class="modal-body">
          <section class="form-section">
            <div class="review-detail-meta">
              <div>
                <span class="field-label">回应者</span>
                <button type="button" class="user-chip-button" @click="emit('open-user', detail.userId)">
                  <img v-if="detail.avatarUrl" :src="detail.avatarUrl" alt="" class="avatar image" />
                  <span v-else class="avatar">{{ initials(detail.displayName) }}</span>
                  <span class="user-chip-copy">
                    <strong>{{ detail.displayName }}</strong>
                    <small>{{ detail.email || '未提供邮箱' }}</small>
                  </span>
                </button>
              </div>
              <div>
                <span class="field-label">表情回应</span>
                <p class="detail-value reaction-emoji-large">{{ detail.emoji }}</p>
                <small class="sub-line">{{ formatDateTime(detail.createdAt) }}</small>
              </div>
              <div>
                <span class="field-label">评价作者</span>
                <button type="button" class="user-chip-button" @click="emit('open-user', detail.reviewAuthorId)">
                  <span class="avatar">{{ initials(detail.reviewAuthorName) }}</span>
                  <span class="user-chip-copy">
                    <strong>{{ detail.reviewAuthorName }}</strong>
                    <small>{{ detail.reviewAuthorEmail || '未提供邮箱' }}</small>
                  </span>
                </button>
              </div>
            </div>
          </section>

          <section class="form-section">
            <span class="field-label">被回应的评价</span>
            <p class="detail-value">
              {{ entityTypeLabel(detail.entityType) }} · {{ detail.entityKey }}
            </p>
            <small class="sub-line">
              {{ reviewTypeLabel(detail.reviewType) }} · {{ detail.reviewRating }} 星 · 发表于
              {{ formatDateTime(detail.reviewCreatedAt) }}
            </small>
            <p class="review-detail-comment">{{ detail.reviewComment }}</p>
          </section>

          <ReviewReactionList :review-id="detail.reviewId" @changed="handleReactionsChanged" />
        </div>
        <footer class="modal-foot">
          <button type="button" class="button ghost" @click="detail = null">关闭</button>
        </footer>
      </div>
    </div>
  </section>
</template>
