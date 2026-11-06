<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import {
  CalendarClock,
  CloudDownload,
  CloudOff,
  Database,
  History,
  LoaderCircle,
  RefreshCw,
  Server,
  ShieldCheck,
  TriangleAlert,
} from '@lucide/vue'
import {
  api,
  ApiError,
  type AdminTimetableSyncStatus,
  type AdminTimetableUpstream,
  type AdminTimetableVersion,
} from '../api'
import { formatBytes, formatDateTime, formatNumber } from '../format'
import SortHeader from './SortHeader.vue'
import { nextSort, sortRows, type SortDirection, type SortState, type SortValue } from '../sort'
import { toast } from '../toast'

const status = ref<AdminTimetableSyncStatus | null>(null)
const loading = ref(true)
const error = ref('')
const starting = ref(false)
const upstream = ref<AdminTimetableUpstream | null>(null)
const checkingUpstream = ref(false)

let pollTimer: number | undefined

// 接口按版本号倒序返回，默认表头状态与之保持一致。
const sort = ref<SortState>({ key: 'version', direction: 'desc' })

const sortGetters: Record<string, (row: AdminTimetableVersion) => SortValue> = {
  version: (row) => row.version,
  size: (row) => row.sizeBytes,
  modified: (row) => row.modifiedAt,
}

const sortedVersions = computed(() =>
  sortRows(status.value?.versions ?? [], sort.value, sortGetters),
)
const sortKey = computed(() => sort.value.key)
const sortDirection = computed<SortDirection>(() => sort.value.direction)

function changeSort(key: string): void {
  sort.value = nextSort(sort.value, key, 'desc')
}

const scheduleLabel = computed(() => {
  if (!status.value) return ''
  const hour = String(status.value.hour).padStart(2, '0')
  const minute = String(status.value.minute).padStart(2, '0')
  return `每天 ${hour}:${minute}（${status.value.timeZone}）`
})

const triggerLabel = computed(() => {
  const trigger = status.value?.lastTrigger
  if (trigger === 'manual') return '手动触发'
  if (trigger === 'scheduled') return '定时任务'
  return '—'
})

function stopPolling(): void {
  if (pollTimer !== undefined) {
    window.clearInterval(pollTimer)
    pollTimer = undefined
  }
}

function startPolling(): void {
  if (pollTimer !== undefined) return
  pollTimer = window.setInterval(async () => {
    await load(true)
    if (!status.value?.running) stopPolling()
  }, 4000)
}

async function load(silent = false): Promise<void> {
  if (!silent) loading.value = true
  error.value = ''
  try {
    status.value = await api.timetableSyncStatus()
    if (status.value.running) startPolling()
    else stopPolling()
  } catch (exception) {
    if (!silent) {
      error.value = exception instanceof ApiError ? exception.message : '读取同步状态失败'
    }
  } finally {
    if (!silent) loading.value = false
  }
}

async function runSync(): Promise<void> {
  if (starting.value || status.value?.running) return
  starting.value = true
  try {
    await api.runTimetableSync()
    toast('已开始同步历史时刻表，页面会自动刷新进度', 'success')
    startPolling()
    window.setTimeout(() => void load(true), 800)
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '启动同步失败', 'error')
  } finally {
    starting.value = false
  }
}

async function checkUpstream(): Promise<void> {
  if (checkingUpstream.value) return
  checkingUpstream.value = true
  upstream.value = null
  try {
    const result = await api.timetableUpstream()
    upstream.value = result
    if (result.error) toast(`检查上游失败：${result.error}`, 'error')
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '检查上游失败', 'error')
  } finally {
    checkingUpstream.value = false
  }
}

onMounted(() => {
  void load()
})

onBeforeUnmount(stopPolling)
</script>

<template>
  <div class="page-stack">
    <div v-if="loading" class="state-card">
      <LoaderCircle :size="22" class="spin" />
      <span>正在读取历史时刻表同步状态…</span>
    </div>

    <div v-else-if="error" class="state-card error">
      <TriangleAlert :size="22" />
      <span>{{ error }}</span>
      <button type="button" class="button ghost" @click="load()"><RefreshCw :size="16" />重试</button>
    </div>

    <template v-else-if="status">
      <section class="panel">
        <div class="panel-head">
          <div>
            <h2><CalendarClock :size="17" /> 历史时刻表同步</h2>
            <p>
              每天从 GitHub Release 拉取该版本的历史时刻表快照，校验通过后原样保存到本地。
              已存在的版本会跳过，首次部署会补齐全部历史版本。
            </p>
          </div>
          <div class="panel-head-actions">
            <span :class="['pill', status.enabled ? 'success' : 'neutral']">
              {{ status.enabled ? '定时同步已启用' : '定时同步已停用' }}
            </span>
            <span v-if="status.running" class="pill blue">正在同步</span>
            <span :class="['pill', status.hasGitHubToken ? 'success' : 'neutral']">
              {{ status.hasGitHubToken ? 'GitHub Token 已配置' : '未配置 GitHub Token' }}
            </span>
            <button
              type="button"
              class="button ghost small"
              :disabled="checkingUpstream"
              @click="checkUpstream"
            >
              <LoaderCircle v-if="checkingUpstream" :size="15" class="spin" />
              <CloudDownload v-else :size="15" />
              {{ checkingUpstream ? '检查中…' : '检查上游更新' }}
            </button>
            <button
              type="button"
              class="button primary small"
              :disabled="starting || status.running"
              @click="runSync"
            >
              <LoaderCircle v-if="starting || status.running" :size="15" class="spin" />
              <RefreshCw v-else :size="15" />
              {{ status.running ? '同步中…' : '立即同步' }}
            </button>
          </div>
        </div>

        <div class="stat-grid">
          <article class="stat-card">
            <span class="stat-icon blue"><Database :size="20" /></span>
            <div>
              <p class="stat-label">本地版本</p>
              <strong class="stat-value">{{ formatNumber(status.totalVersions) }}</strong>
              <p class="stat-hint">每个版本一个 db 文件</p>
            </div>
          </article>
          <article class="stat-card">
            <span class="stat-icon amber"><Server :size="20" /></span>
            <div>
              <p class="stat-label">占用空间</p>
              <strong class="stat-value">{{ formatBytes(status.totalSizeBytes) }}</strong>
              <p class="stat-hint">{{ status.directory }}</p>
            </div>
          </article>
          <article class="stat-card">
            <span class="stat-icon green"><History :size="20" /></span>
            <div>
              <p class="stat-label">最新版本</p>
              <strong class="stat-value">{{ status.newestVersion ?? '—' }}</strong>
              <p class="stat-hint">最早 {{ status.oldestVersion ?? '—' }}</p>
            </div>
          </article>
          <article class="stat-card">
            <span class="stat-icon red"><CalendarClock :size="20" /></span>
            <div>
              <p class="stat-label">下次同步</p>
              <strong class="stat-value small-value">
                {{ status.enabled ? (status.nextRunAt ? formatDateTime(status.nextRunAt) : '待定') : '已停用' }}
              </strong>
              <p class="stat-hint">{{ scheduleLabel }}</p>
            </div>
          </article>
        </div>

        <div class="info-note compact">
          <ShieldCheck :size="15" />
          <span>
            仓库 {{ status.owner }}/{{ status.repository }} · 资产 {{ status.assetName }}
            <template v-if="!status.hasGitHubToken">
              · 未配置 TrainTimetables:Sync:GitHubToken 时只能读取公开仓库
            </template>
          </span>
        </div>

        <div class="sync-run-line">
          <span>上次运行：{{ status.lastFinishedAt ? formatDateTime(status.lastFinishedAt) : '尚未运行' }}</span>
          <span>触发方式：{{ triggerLabel }}</span>
          <span v-if="status.lastFinishedAt">
            结果：{{ status.lastError ? '失败' : `成功，新同步 ${status.lastSyncedCount} 个版本` }}
          </span>
        </div>

        <div v-if="status.lastError" class="state-card inline error sync-error">
          <TriangleAlert :size="18" />
          <span>{{ status.lastError }}</span>
        </div>
      </section>

      <section v-if="upstream" class="panel">
        <div class="panel-head">
          <div>
            <h2><CloudDownload :size="17" /> 上游版本检查</h2>
            <p>
              只读取 GitHub Release 列表，不下载文件。上游共
              {{ formatNumber(upstream.upstreamVersions) }} 个版本，本地
              {{ formatNumber(upstream.localVersions) }} 个。
            </p>
          </div>
          <span
            :class="['pill', upstream.missingVersions.length > 0 ? 'amber' : 'success']"
          >
            {{ upstream.missingVersions.length > 0
              ? `缺 ${formatNumber(upstream.missingVersions.length)} 个版本`
              : '已是最新' }}
          </span>
        </div>

        <div v-if="upstream.error" class="state-card inline error">
          <CloudOff :size="18" />
          <span>{{ upstream.error }}</span>
        </div>
        <div v-else-if="upstream.missingVersions.length === 0" class="empty-note">
          本地已包含上游的全部版本。
        </div>
        <div v-else class="trip-id-list">
          <span v-for="version in upstream.missingVersions" :key="version" class="trip-id-chip">
            {{ version }}
          </span>
        </div>
      </section>

      <section class="panel">
        <div class="panel-head">
          <div>
            <h2><Database :size="17" /> 本地快照</h2>
            <p>供查询侧按行程日期选择，默认按版本号从新到旧排列。</p>
          </div>
          <button type="button" class="button ghost small" :disabled="loading" @click="load()">
            <RefreshCw :size="15" /> 刷新
          </button>
        </div>

        <div v-if="status.versions.length === 0" class="empty-state">
          <span class="empty-icon"><Database :size="30" /></span>
          <h3>还没有历史时刻表</h3>
          <p>点「立即同步」开始从 GitHub Release 拉取。</p>
        </div>

        <div v-else class="table-scroll">
          <table class="data-table">
            <thead>
              <tr>
                <SortHeader label="版本" sort-key="version" :active="sortKey === 'version'" :direction="sortDirection" @sort="changeSort" />
                <SortHeader label="大小" sort-key="size" align="right" :active="sortKey === 'size'" :direction="sortDirection" @sort="changeSort" />
                <SortHeader class="col-time" label="文件时间" sort-key="modified" :active="sortKey === 'modified'" :direction="sortDirection" @sort="changeSort" />
              </tr>
            </thead>
            <tbody>
              <tr v-for="version in sortedVersions" :key="version.version">
                <td><code class="file-name">{{ version.version }}</code></td>
                <td class="col-number">{{ formatBytes(version.sizeBytes) }}</td>
                <td class="muted-text">{{ formatDateTime(version.modifiedAt) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>
