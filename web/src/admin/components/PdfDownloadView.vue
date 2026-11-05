<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  ChevronLeft,
  ChevronRight,
  FileKey,
  KeyRound,
  LoaderCircle,
  RefreshCw,
  Search,
  ShieldCheck,
  Ticket,
  Trash2,
  TriangleAlert,
} from '@lucide/vue'
import {
  api,
  ApiError,
  PAGE_SIZE,
  type AdminPdfRequest,
  type AdminPdfRequestPage,
  type AdminTicketPasswordStatus,
} from '../api'
import { confirmDestructive } from '../confirm'
import { formatDateTime, formatNumber } from '../format'
import SortHeader from './SortHeader.vue'
import { nextSort, type SortDirection, type SortState } from '../sort'
import { toast } from '../toast'

const sourceLabels: Record<string, string> = {
  database: '管理后台设置',
  configuration: '服务端配置文件 TicketPdf:DownloadPassword',
  none: '尚未配置',
}

const styleLabels: Record<string, string> = {
  red: '红色车票',
  blue: '蓝色车票',
}

// ---- 下载密码 ----

const status = ref<AdminTicketPasswordStatus | null>(null)
const loading = ref(true)
const error = ref('')
const password = ref('')
const confirmation = ref('')
const saving = ref(false)
const clearing = ref(false)

const hasOverride = computed(() => status.value?.source === 'database')

async function loadPassword(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    status.value = await api.ticketPasswordStatus()
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取下载密码状态失败'
  } finally {
    loading.value = false
  }
}

async function save(): Promise<void> {
  const value = password.value
  if (value.length < 4 || value.length > 128) {
    toast('密码长度应为 4 至 128 个字符', 'error')
    return
  }
  if (!/\S/.test(value)) {
    toast('密码不能只包含空白字符', 'error')
    return
  }
  if (value !== confirmation.value) {
    toast('两次输入的密码不一致', 'error')
    return
  }
  saving.value = true
  try {
    await api.setTicketPassword(value)
    password.value = ''
    confirmation.value = ''
    toast('PDF 下载密码已更新', 'success')
    await loadPassword()
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '保存失败', 'error')
  } finally {
    saving.value = false
  }
}

async function clearOverride(): Promise<void> {
  const fallback = status.value?.source === 'database'
    ? '清除后会回退到服务端配置文件中的密码。'
    : ''
  const confirmed = confirmDestructive({
    title: '清除后台设置的 PDF 下载密码',
    message: fallback || '配置文件中的密码同样不存在时，网页下载会暂时不可用。',
  })
  if (!confirmed) return
  clearing.value = true
  try {
    await api.clearTicketPassword()
    toast('已清除后台设置的下载密码', 'info')
    await loadPassword()
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '清除失败', 'error')
  } finally {
    clearing.value = false
  }
}

// ---- 下载请求 Key ----

const requests = ref<AdminPdfRequestPage | null>(null)
const requestsLoading = ref(true)
const requestsError = ref('')
const offset = ref(0)
// 服务端默认按创建时间倒序，表头状态与之保持一致。
const sort = ref<SortState>({ key: 'created', direction: 'desc' })
const query = ref('')
const submittedQuery = ref('')
const revokingId = ref('')
const cleaning = ref(false)

const pageStart = computed(() =>
  requests.value && requests.value.total > 0 ? offset.value + 1 : 0,
)
const pageEnd = computed(() =>
  requests.value ? Math.min(offset.value + PAGE_SIZE, requests.value.total) : 0,
)
const hasPrevious = computed(() => offset.value > 0)
const hasNext = computed(
  () => requests.value !== null && offset.value + PAGE_SIZE < requests.value.total,
)

async function loadRequests(silent = false): Promise<void> {
  if (!silent) requestsLoading.value = true
  requestsError.value = ''
  try {
    requests.value = await api.pdfRequests(
      submittedQuery.value,
      offset.value,
      PAGE_SIZE,
      sort.value,
    )
  } catch (exception) {
    requestsError.value = exception instanceof ApiError
      ? exception.message
      : '读取下载请求失败'
  } finally {
    if (!silent) requestsLoading.value = false
  }
}

function searchRequests(): void {
  submittedQuery.value = query.value.trim()
  offset.value = 0
  void loadRequests()
}

function resetSearch(): void {
  query.value = ''
  submittedQuery.value = ''
  offset.value = 0
  void loadRequests()
}

/** 文本列先升序，时间与状态列先降序（最近/有效优先）。 */
const SORT_INITIAL: Record<string, SortDirection> = {
  passenger: 'asc',
  status: 'asc',
}

function changeSort(key: string): void {
  sort.value = nextSort(sort.value, key, SORT_INITIAL[key] ?? 'desc')
  offset.value = 0
  void loadRequests()
}

function previous(): void {
  if (!hasPrevious.value) return
  offset.value = Math.max(0, offset.value - PAGE_SIZE)
  void loadRequests()
}

function next(): void {
  if (!hasNext.value) return
  offset.value += PAGE_SIZE
  void loadRequests()
}

function styleLabel(style: string): string {
  if (!style) return '默认样式'
  return styleLabels[style] ?? style
}

async function revoke(request: AdminPdfRequest): Promise<void> {
  const confirmed = confirmDestructive({
    title: '撤销该 PDF 下载请求',
    message: request.passenger
      ? `乘车人「${request.passenger}」的请求 Key 会立即失效。`
      : '该请求 Key 会立即失效。',
  })
  if (!confirmed) return
  revokingId.value = request.id
  try {
    await api.deletePdfRequest(request.id)
    toast('已撤销该下载请求', 'info')
    await loadRequests(true)
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '撤销失败', 'error')
  } finally {
    revokingId.value = ''
  }
}

async function cleanup(): Promise<void> {
  const confirmed = confirmDestructive({
    title: '清理过期的下载请求',
    message: '所有已过期的请求 Key 都会被永久删除。',
  })
  if (!confirmed) return
  cleaning.value = true
  try {
    const result = await api.cleanupPdfRequests()
    toast(
      result.removed > 0
        ? `已清理 ${result.removed} 条过期请求`
        : '没有需要清理的过期请求',
      'info',
    )
    await loadRequests(true)
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '清理失败', 'error')
  } finally {
    cleaning.value = false
  }
}

onMounted(() => {
  void loadPassword()
  void loadRequests()
})
</script>

<template>
  <div class="page-stack">
    <!-- 下载密码 -->
    <div v-if="loading" class="state-card">
      <LoaderCircle :size="22" class="spin" />
      <span>正在读取下载密码状态…</span>
    </div>

    <div v-else-if="error" class="state-card error">
      <TriangleAlert :size="22" />
      <span>{{ error }}</span>
      <button type="button" class="button ghost" @click="loadPassword">
        <RefreshCw :size="16" />重试
      </button>
    </div>

    <section v-else-if="status" class="panel">
      <div class="panel-head">
        <div>
          <h2><KeyRound :size="17" /> PDF 下载密码</h2>
          <p>用户在网页端下载行程 PDF 前需要输入该密码。后台只保存密码摘要，设置后无法查看原密码。</p>
        </div>
        <span :class="['pill', status.configured ? 'success' : 'neutral']">
          {{ status.configured ? '已配置' : '未配置' }}
        </span>
      </div>

      <div class="info-note compact">
        <ShieldCheck :size="15" />
        <span>
          当前来源：{{ sourceLabels[status.source] ?? status.source }}
          <template v-if="status.updatedAt">（更新于 {{ formatDateTime(status.updatedAt) }}）</template>
        </span>
      </div>

      <form class="form-section" @submit.prevent="save">
        <h3>设置新密码</h3>
        <div class="field-grid">
          <label class="field">
            <span class="field-label">新密码 <em>*</em></span>
            <input
              v-model="password"
              type="password"
              autocomplete="new-password"
              placeholder="4 至 128 个字符"
              maxlength="128"
            />
          </label>
          <label class="field">
            <span class="field-label">确认新密码 <em>*</em></span>
            <input
              v-model="confirmation"
              type="password"
              autocomplete="new-password"
              placeholder="再次输入新密码"
              maxlength="128"
            />
          </label>
        </div>
        <p class="field-hint">
          保存后立即生效，用户再次下载时需要使用新密码。若曾把密码告知他人，建议同时更换。
        </p>
        <div class="form-actions">
          <button type="submit" class="button primary" :disabled="saving">
            <LoaderCircle v-if="saving" :size="16" class="spin" />
            <KeyRound v-else :size="16" />
            {{ saving ? '正在保存…' : '保存密码' }}
          </button>
        </div>
      </form>

      <div v-if="hasOverride" class="danger-zone">
        <div class="form-actions">
          <span>
            <strong>清除后台密码</strong>
            <small class="field-hint">
              清除后回退到服务端配置文件中的下载密码；若配置文件也没有密码，网页下载会暂时不可用。
            </small>
          </span>
          <button
            type="button"
            class="button danger"
            :disabled="clearing"
            @click="clearOverride"
          >
            <LoaderCircle v-if="clearing" :size="16" class="spin" />
            <Trash2 v-else :size="16" />
            {{ clearing ? '正在清除…' : '清除后台设置' }}
          </button>
        </div>
      </div>
    </section>

    <!-- 下载请求 Key -->
    <section class="panel">
      <div class="panel-head">
        <div>
          <h2><FileKey :size="17" /> PDF 下载请求 Key</h2>
          <p>
            用户在网页端选好行程后会生成一个 24 小时有效的请求 Key，凭 Key 加下载密码兑换 PDF。
            后台只保存 Key 的摘要，无法查看原文；这里可以查看请求明细并提前撤销。
          </p>
        </div>
        <div class="panel-head-actions">
          <span v-if="requests" class="pill neutral">
            有效 {{ formatNumber(requests.activeCount) }} / 共 {{ formatNumber(requests.total) }}
          </span>
          <button
            type="button"
            class="button ghost small"
            :disabled="cleaning"
            @click="cleanup"
          >
            <LoaderCircle v-if="cleaning" :size="15" class="spin" />
            <Trash2 v-else :size="15" />
            {{ cleaning ? '清理中…' : '清理过期' }}
          </button>
        </div>
      </div>

      <form class="search-bar" @submit.prevent="searchRequests">
        <span class="search-input">
          <Search :size="18" />
          <input
            v-model="query"
            type="search"
            placeholder="搜索乘车人、证件号（掩码）或行程 ID"
            autocomplete="off"
          />
        </span>
        <button type="submit" class="button primary" :disabled="requestsLoading">
          <Search :size="16" /> 搜索
        </button>
        <button type="button" class="button ghost" :disabled="requestsLoading" @click="resetSearch">
          <RefreshCw :size="16" /> 重置
        </button>
      </form>

      <div v-if="requestsLoading" class="state-card inline">
        <LoaderCircle :size="20" class="spin" /><span>正在读取下载请求…</span>
      </div>
      <div v-else-if="requestsError" class="state-card inline error">
        <TriangleAlert :size="20" /><span>{{ requestsError }}</span>
        <button type="button" class="button ghost small" @click="loadRequests()">重试</button>
      </div>
      <div v-else-if="!requests || requests.items.length === 0" class="empty-state">
        <span class="empty-icon"><FileKey :size="30" /></span>
        <h3>还没有下载请求</h3>
        <p>用户在网页端选择行程生成 PDF 下载 Key 后，记录会出现在这里。</p>
      </div>

      <template v-else>
        <div class="table-wrap">
          <table class="data-table">
            <thead>
              <tr>
                <SortHeader label="乘车人" sort-key="passenger" :active="sort.key === 'passenger'" :direction="sort.direction" @sort="changeSort" />
                <th>关联行程</th>
                <th>车票样式</th>
                <SortHeader class="col-time" label="创建时间" sort-key="created" :active="sort.key === 'created'" :direction="sort.direction" @sort="changeSort" />
                <SortHeader class="col-time" label="过期时间" sort-key="expires" :active="sort.key === 'expires'" :direction="sort.direction" @sort="changeSort" />
                <SortHeader label="状态" sort-key="status" :active="sort.key === 'status'" :direction="sort.direction" @sort="changeSort" />
                <th class="col-actions">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="request in requests.items" :key="request.id">
                <td>
                  <strong>{{ request.passenger || '—' }}</strong>
                  <small v-if="request.maskedId" class="sub-line">{{ request.maskedId }}</small>
                </td>
                <td>
                  <div class="trip-id-list">
                    <span
                      v-for="tripId in request.tripIds"
                      :key="tripId"
                      class="trip-id-chip"
                      :title="`行程 #${tripId}`"
                    >
                      <Ticket :size="12" />#{{ tripId }}
                    </span>
                    <span v-if="request.tripIds.length === 0" class="muted-text">—</span>
                  </div>
                </td>
                <td>{{ styleLabel(request.style) }}</td>
                <td class="muted-text">{{ formatDateTime(request.createdAt) }}</td>
                <td class="muted-text">{{ formatDateTime(request.expiresAt) }}</td>
                <td>
                  <span :class="['pill', request.expired ? 'neutral' : 'success']">
                    {{ request.expired ? '已过期' : '有效' }}
                  </span>
                </td>
                <td>
                  <div class="row-actions">
                    <button
                      type="button"
                      class="icon-button danger"
                      title="撤销该下载请求"
                      aria-label="撤销该下载请求"
                      :disabled="revokingId === request.id"
                      @click="revoke(request)"
                    >
                      <LoaderCircle v-if="revokingId === request.id" :size="16" class="spin" />
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
            <FileKey :size="15" />
            第 {{ pageStart }}–{{ pageEnd }} 条，共 {{ formatNumber(requests.total) }} 条
          </span>
          <div class="pagination-actions">
            <button
              type="button"
              class="button ghost small"
              :disabled="!hasPrevious || requestsLoading"
              @click="previous"
            >
              <ChevronLeft :size="16" /> 上一页
            </button>
            <button
              type="button"
              class="button ghost small"
              :disabled="!hasNext || requestsLoading"
              @click="next"
            >
              下一页 <ChevronRight :size="16" />
            </button>
          </div>
        </div>
      </template>
    </section>
  </div>
</template>
