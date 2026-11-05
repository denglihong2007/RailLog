<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  Archive,
  Database,
  Download,
  HardDriveDownload,
  LoaderCircle,
  RefreshCw,
  ShieldCheck,
  Trash2,
  TriangleAlert,
} from '@lucide/vue'
import { api, ApiError, type AdminBackupFile, type AdminBackupOverview } from '../api'
import { confirmByTyping } from '../confirm'
import { formatBytes, formatDateTime, formatNumber } from '../format'
import SortHeader from './SortHeader.vue'
import { nextSort, sortRows, type SortDirection, type SortState, type SortValue } from '../sort'
import { toast } from '../toast'

const data = ref<AdminBackupOverview | null>(null)
const loading = ref(true)
const error = ref('')
const downloading = ref(false)
const downloadingName = ref('')
const deletingName = ref('')

// 默认与服务端一致：最新的备份排在前面。
const sort = ref<SortState>({ key: 'created', direction: 'desc' })

const SORT_INITIAL: Record<string, SortDirection> = { name: 'asc' }

const sortGetters: Record<string, (row: AdminBackupFile) => SortValue> = {
  name: (row) => row.name,
  size: (row) => row.sizeBytes,
  created: (row) => row.createdAt,
}

const sortedItems = computed(() =>
  sortRows(data.value?.items ?? [], sort.value, sortGetters),
)
const sortKey = computed(() => sort.value.key)
const sortDirection = computed<SortDirection>(() => sort.value.direction)

function changeSort(key: string): void {
  sort.value = nextSort(sort.value, key, SORT_INITIAL[key] ?? 'desc')
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    data.value = await api.backups()
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取备份状态失败'
  } finally {
    loading.value = false
  }
}

async function downloadNow(): Promise<void> {
  if (downloading.value) return
  downloading.value = true
  try {
    await api.downloadBackup()
    toast('备份已生成并开始下载', 'success')
    await load()
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '生成备份失败', 'error')
  } finally {
    downloading.value = false
  }
}

async function downloadFile(name: string): Promise<void> {
  if (downloadingName.value) return
  downloadingName.value = name
  try {
    await api.downloadBackupFile(name)
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '下载失败', 'error')
  } finally {
    downloadingName.value = ''
  }
}

async function deleteFile(name: string): Promise<void> {
  if (deletingName.value) return
  const confirmed = confirmByTyping({
    title: '删除备份文件',
    message: `备份「${name}」会从服务器永久移除，之后只能从其他副本恢复。`,
    expected: name,
  })
  if (!confirmed) return
  deletingName.value = name
  try {
    await api.deleteBackup(name)
    toast('备份文件已删除', 'info')
    await load()
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '删除失败', 'error')
  } finally {
    deletingName.value = ''
  }
}

onMounted(load)
</script>

<template>
  <div class="page-stack">
    <div v-if="loading" class="state-card">
      <LoaderCircle :size="22" class="spin" />
      <span>正在读取备份状态…</span>
    </div>

    <div v-else-if="error" class="state-card error">
      <TriangleAlert :size="22" />
      <span>{{ error }}</span>
      <button type="button" class="button ghost" @click="load"><RefreshCw :size="16" />重试</button>
    </div>

    <template v-else-if="data">
      <section class="panel">
        <div class="panel-head">
          <div>
            <h2><Database :size="17" /> 数据库备份</h2>
            <p>
              服务端用 SQLite 在线备份接口生成一致性快照。定时备份只保留最近几份，
              随时可以在这里生成一份最新的快照直接下载。
            </p>
          </div>
          <div class="panel-head-actions">
            <span :class="['pill', data.enabled ? 'success' : 'neutral']">
              {{ data.enabled ? '定时备份已启用' : '定时备份已停用' }}
            </span>
            <button
              type="button"
              class="button primary"
              :disabled="downloading"
              @click="downloadNow"
            >
              <LoaderCircle v-if="downloading" :size="16" class="spin" />
              <HardDriveDownload v-else :size="16" />
              {{ downloading ? '正在生成…' : '生成并下载最新备份' }}
            </button>
          </div>
        </div>

        <div class="stat-grid backup-facts">
          <article class="stat-card">
            <span class="stat-icon blue"><Archive :size="20" /></span>
            <div>
              <p class="stat-label">已保留备份</p>
              <strong class="stat-value">{{ formatNumber(data.items.length) }}</strong>
              <p class="stat-hint">最多保留最近 {{ data.keepCount }} 份</p>
            </div>
          </article>
          <article class="stat-card">
            <span class="stat-icon amber"><RefreshCw :size="20" /></span>
            <div>
              <p class="stat-label">备份间隔</p>
              <strong class="stat-value">每 {{ data.intervalDays }} 天</strong>
              <p class="stat-hint">启动时检查是否到期</p>
            </div>
          </article>
          <article class="stat-card">
            <span class="stat-icon green"><ShieldCheck :size="20" /></span>
            <div>
              <p class="stat-label">备份目录</p>
              <strong class="stat-value mono-path">{{ data.directory }}</strong>
              <p class="stat-hint">可在 DatabaseBackup:Directory 中调整</p>
            </div>
          </article>
        </div>

        <div class="info-note compact">
          <ShieldCheck :size="15" />
          <span>
            备份包含用户、行程、评价、成就与系统设置的全部数据，请妥善保管，
            不要通过公开渠道分享。
          </span>
        </div>
      </section>

      <section class="panel">
        <div class="panel-head">
          <div>
            <h2><Archive :size="17" /> 现有备份</h2>
            <p>定时任务生成的快照，默认按时间从新到旧排列。</p>
          </div>
          <button type="button" class="button ghost small" :disabled="loading" @click="load">
            <RefreshCw :size="15" /> 刷新
          </button>
        </div>

        <div v-if="data.items.length === 0" class="empty-state">
          <span class="empty-icon"><Archive :size="30" /></span>
          <h3>还没有定时备份</h3>
          <p>服务端启动后会在到达备份间隔时自动生成第一份快照。</p>
        </div>

        <div v-else class="table-wrap">
          <table class="data-table">
            <thead>
              <tr>
                <SortHeader label="文件名" sort-key="name" :active="sortKey === 'name'" :direction="sortDirection" @sort="changeSort" />
                <SortHeader label="大小" sort-key="size" align="right" :active="sortKey === 'size'" :direction="sortDirection" @sort="changeSort" />
                <SortHeader class="col-time" label="生成时间" sort-key="created" :active="sortKey === 'created'" :direction="sortDirection" @sort="changeSort" />
                <th class="col-actions">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="file in sortedItems" :key="file.name">
                <td><code class="file-name">{{ file.name }}</code></td>
                <td class="col-number">{{ formatBytes(file.sizeBytes) }}</td>
                <td class="muted-text">{{ formatDateTime(file.createdAt) }}</td>
                <td>
                  <div class="row-actions">
                    <button
                      type="button"
                      class="button ghost small"
                      :disabled="downloadingName !== '' || deletingName !== ''"
                      @click="downloadFile(file.name)"
                    >
                      <LoaderCircle
                        v-if="downloadingName === file.name"
                        :size="15"
                        class="spin"
                      />
                      <Download v-else :size="15" />
                      {{ downloadingName === file.name ? '下载中…' : '下载' }}
                    </button>
                    <button
                      type="button"
                      class="icon-button danger"
                      title="删除备份"
                      :disabled="downloadingName !== '' || deletingName !== ''"
                      @click="deleteFile(file.name)"
                    >
                      <LoaderCircle
                        v-if="deletingName === file.name"
                        :size="16"
                        class="spin"
                      />
                      <Trash2 v-else :size="16" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>
