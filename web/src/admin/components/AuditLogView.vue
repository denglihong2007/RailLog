<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  ChevronLeft,
  ChevronRight,
  ClipboardList,
  LoaderCircle,
  RefreshCw,
  Search,
  TriangleAlert,
} from '@lucide/vue'
import { api, ApiError, PAGE_SIZE, type AdminAuditPage } from '../api'
import { formatDateTime, formatNumber } from '../format'
import SortHeader from './SortHeader.vue'
import { nextSort, type SortDirection, type SortState } from '../sort'

const actionLabels: Record<string, string> = {
  'announcement.save': '保存公告',
  'announcement.delete': '删除公告',
  'user.update': '修改用户资料',
  'user.delete': '删除用户',
  'trip.create': '新增行程',
  'trip.update': '修改行程',
  'trip.delete': '删除行程',
  'review.delete': '删除评价',
  'ticket-password.set': '设置 PDF 下载密码',
  'ticket-password.clear': '清除 PDF 下载密码',
  'pdf-request.revoke': '撤销 PDF 请求 Key',
  'pdf-request.cleanup': '清理过期 PDF 请求',
  'user-levels.save': '保存等级分界线',
  'backup.download': '下载现场备份',
  'backup.download-file': '下载历史备份',
  'backup.delete': '删除备份文件',
  'timetable-sync.run': '手动同步历史时刻表',
}

const query = ref('')
const submittedQuery = ref('')
const offset = ref(0)
// 服务端默认按时间倒序，表头状态与之保持一致。
const sort = ref<SortState>({ key: 'created', direction: 'desc' })
const data = ref<AdminAuditPage | null>(null)
const loading = ref(true)
const error = ref('')

const pageStart = computed(() =>
  data.value && data.value.total > 0 ? offset.value + 1 : 0,
)
const pageEnd = computed(() =>
  data.value ? Math.min(offset.value + PAGE_SIZE, data.value.total) : 0,
)
const hasPrevious = computed(() => offset.value > 0)
const hasNext = computed(
  () => data.value !== null && offset.value + PAGE_SIZE < data.value.total,
)

function actionLabel(action: string): string {
  return actionLabels[action] ?? action
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    data.value = await api.auditLogs(submittedQuery.value, offset.value, PAGE_SIZE, sort.value)
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取操作日志失败'
  } finally {
    loading.value = false
  }
}

function search(): void {
  submittedQuery.value = query.value.trim()
  offset.value = 0
  void load()
}

function reset(): void {
  query.value = ''
  submittedQuery.value = ''
  offset.value = 0
  void load()
}

/** 文本列先升序，时间列先降序（先看最近的操作）。 */
const SORT_INITIAL: Record<string, SortDirection> = { admin: 'asc', action: 'asc' }

function changeSort(key: string): void {
  sort.value = nextSort(sort.value, key, SORT_INITIAL[key] ?? 'desc')
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

onMounted(load)
</script>

<template>
  <div class="page-stack">
    <section class="panel">
      <div class="panel-head">
        <div>
          <h2><ClipboardList :size="17" /> 操作日志</h2>
          <p>
            记录管理员在后台执行的关键操作。日志只追加、不在后台删除；
            操作人名称按执行时快照保存，改名后历史记录保持不变。
          </p>
        </div>
      </div>

      <form class="search-bar" @submit.prevent="search">
        <span class="search-input">
          <Search :size="18" />
          <input
            v-model="query"
            type="search"
            placeholder="搜索操作、操作人、对象或说明"
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
        <LoaderCircle :size="20" class="spin" /><span>正在读取操作日志…</span>
      </div>
      <div v-else-if="error" class="state-card inline error">
        <TriangleAlert :size="20" /><span>{{ error }}</span>
        <button type="button" class="button ghost small" @click="load">
          <RefreshCw :size="15" /> 重试
        </button>
      </div>
      <div v-else-if="!data || data.items.length === 0" class="empty-state">
        <span class="empty-icon"><ClipboardList :size="30" /></span>
        <h3>{{ submittedQuery ? '没有匹配的操作记录' : '还没有操作记录' }}</h3>
        <p>{{ submittedQuery ? '换一个关键词再试一次。' : '管理员执行删除、修改或配置操作后会记录在这里。' }}</p>
      </div>

      <template v-else>
        <div class="table-wrap">
          <table class="data-table audit-table">
            <thead>
              <tr>
                <SortHeader class="col-time" label="时间" sort-key="created" :active="sort.key === 'created'" :direction="sort.direction" @sort="changeSort" />
                <SortHeader label="操作人" sort-key="admin" :active="sort.key === 'admin'" :direction="sort.direction" @sort="changeSort" />
                <SortHeader label="操作" sort-key="action" :active="sort.key === 'action'" :direction="sort.direction" @sort="changeSort" />
                <th>对象</th>
                <th>说明</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="entry in data.items" :key="entry.id">
                <td class="col-time muted-text">{{ formatDateTime(entry.createdAt) }}</td>
                <td>
                  <strong>{{ entry.adminName }}</strong>
                  <small class="sub-line">{{ entry.adminUserId }}</small>
                </td>
                <td><span class="pill subtle">{{ actionLabel(entry.action) }}</span></td>
                <td>
                  <code v-if="entry.target" class="file-name">{{ entry.target }}</code>
                  <span v-else class="muted-text">—</span>
                </td>
                <td class="muted-text">{{ entry.detail || '—' }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="pagination">
          <span class="pagination-summary">
            <ClipboardList :size="15" />
            第 {{ pageStart }}–{{ pageEnd }} 条，共 {{ formatNumber(data.total) }} 条记录
          </span>
          <div class="pagination-actions">
            <button
              type="button"
              class="button ghost small"
              :disabled="!hasPrevious || loading"
              @click="previous"
            >
              <ChevronLeft :size="16" /> 上一页
            </button>
            <button
              type="button"
              class="button ghost small"
              :disabled="!hasNext || loading"
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
