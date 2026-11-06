<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import {
  CheckCircle2,
  Info,
  LoaderCircle,
  Medal,
  RefreshCw,
  RotateCcw,
  Save,
  TriangleAlert,
  Users,
} from '@lucide/vue'
import {
  api,
  ApiError,
  type AdminUserLevelConfig,
  type AdminUserLevelStat,
} from '../api'
import { confirmDestructive } from '../confirm'
import { formatDateTime, formatNumber } from '../format'
import { toast } from '../toast'

const emit = defineEmits<{
  /** 点选某个等级，跳到「用户与行程」查看该等级的用户。 */
  (event: 'open-level', level: number): void
  /** 全站成就重算结束，成就列表需要重新读取。 */
  (event: 'recompute-finished'): void
}>()

const config = ref<AdminUserLevelConfig | null>(null)
const thresholds = ref<number[]>([])
const loading = ref(true)
const error = ref('')
const saving = ref(false)
const resetting = ref(false)
const polling = ref(false)

let pollTimer: number | undefined

const savedThresholds = computed(() => config.value?.thresholds ?? [])
const levels = computed(() => config.value?.levels ?? [])
const maxUserCount = computed(() =>
  Math.max(1, ...levels.value.map((stat) => stat.userCount)),
)
const recomputing = computed(
  () =>
    Boolean(config.value?.recompute.running) ||
    Boolean(config.value?.recompute.pending),
)

const edited = computed(() => {
  const saved = savedThresholds.value
  return (
    saved.length !== thresholds.value.length ||
    saved.some((value, index) => value !== thresholds.value[index])
  )
})

/**
 * 拉取到新配置时默认用服务端门槛覆盖草稿；后台轮询刷新人数时若管理员
 * 正在编辑，则保留草稿，避免每几秒把输入框改回去。
 */
function applyConfig(next: AdminUserLevelConfig, preserveDraft = false): void {
  const keepDraft = preserveDraft && edited.value
  config.value = next
  if (!keepDraft) thresholds.value = [...next.thresholds]
  syncPolling()
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    applyConfig(await api.userLevels())
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取等级数据失败'
  } finally {
    loading.value = false
  }
}

/**
 * 分界线保存后服务端会重算全站成就，等级人数在此之后才准确。
 * 重算期间每 4 秒刷新一次，结束后再取一次最终数字。
 */
function syncPolling(): void {
  if (recomputing.value) {
    if (pollTimer === undefined) {
      pollTimer = window.setInterval(() => void pollRecompute(), 4000)
    }
    return
  }
  if (pollTimer !== undefined) {
    window.clearInterval(pollTimer)
    pollTimer = undefined
  }
}

async function pollRecompute(): Promise<void> {
  if (polling.value) return
  polling.value = true
  try {
    const wasRunning = recomputing.value
    const next = await api.userLevels()
    applyConfig(next, true)
    if (wasRunning && !recomputing.value) {
      emit('recompute-finished')
      toast(next.recompute.lastError
        ? '全站成就重算失败，等级人数可能不是最新'
        : '全站成就重算已完成，等级人数已更新', next.recompute.lastError ? 'error' : 'success')
    }
  } catch {
    // 轮询失败不打断页面，下一轮再试。
  } finally {
    polling.value = false
  }
}

// 分布按已保存的分界线统计，所以区间说明也取保存值，避免编辑时数字对不上人数。
function rangeLabel(level: number): string {
  const values = savedThresholds.value
  if (values.length < 2) return ''
  if (level === 0) return `0 ≤ XP < ${formatNumber(values[1] ?? 0)}`
  const minimum = values[level] ?? 0
  if (level === values.length - 1) return `≥ ${formatNumber(minimum)} XP`
  return `${formatNumber(minimum)} ≤ XP < ${formatNumber(values[level + 1] ?? minimum)}`
}

function barWidth(stat: AdminUserLevelStat): number {
  if (stat.userCount === 0) return 0
  return Math.max(2, Math.round((stat.userCount / maxUserCount.value) * 100))
}

function validate(): string | null {
  const values = thresholds.value
  if (values.length < 2) return '等级分界线数据不完整'
  if (values[0] !== 0) return 'LV0 的门槛必须为 0'
  for (let level = 1; level < values.length; level++) {
    const current = values[level] ?? 0
    const previous = values[level - 1] ?? 0
    if (!Number.isInteger(current) || current <= 0) {
      return `LV${level} 的门槛必须是大于 0 的整数`
    }
    if (current <= previous) {
      return `LV${level} 的门槛必须高于 LV${level - 1}`
    }
  }
  if ((values[values.length - 1] ?? 0) > 1_000_000) {
    return '等级门槛不能超过 1000000'
  }
  return null
}

async function save(): Promise<void> {
  const problem = validate()
  if (problem) {
    toast(problem, 'error')
    return
  }
  saving.value = true
  try {
    applyConfig(await api.saveUserLevels(thresholds.value.map((value) => Math.trunc(value))))
    toast(
      recomputing.value ? '等级分界线已保存，后台正在重算全站成就' : '等级分界线已保存（与之前一致，无需重算）',
      'success',
    )
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '保存失败', 'error')
  } finally {
    saving.value = false
  }
}

async function resetDefaults(): Promise<void> {
  const defaults = config.value?.defaults ?? []
  if (defaults.length === 0) return
  const confirmed = confirmDestructive({
    title: '恢复默认等级分界线',
    message: defaults
      .map((value, level) => `LV${level}：${formatNumber(value)} XP`)
      .join('\n'),
  })
  if (!confirmed) return
  resetting.value = true
  try {
    applyConfig(await api.saveUserLevels(defaults))
    toast('已恢复默认等级分界线', 'info')
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '恢复默认值失败', 'error')
  } finally {
    resetting.value = false
  }
}

onMounted(load)
onBeforeUnmount(() => {
  if (pollTimer !== undefined) window.clearInterval(pollTimer)
})
</script>

<template>
  <div v-if="loading" class="state-card">
    <LoaderCircle :size="22" class="spin" />
    <span>正在读取等级数据…</span>
  </div>

  <div v-else-if="error" class="state-card error">
    <TriangleAlert :size="22" />
    <span>{{ error }}</span>
    <button type="button" class="button ghost" @click="load"><RefreshCw :size="16" />重试</button>
  </div>

  <section v-else-if="config" class="panel">
    <div class="panel-head">
      <div>
        <h2><Medal :size="17" /> 用户等级</h2>
        <p>
          等级按用户已解锁成就的经验总和计算，共 {{ formatNumber(config.totalUsers) }} 位注册用户。
          下方人数按当前已保存的分界线统计；调整门槛后用户经验不会直接变化，
          但「达到 N 级」类成就会按新门槛重算，因此经验与等级仍需等待后台重算完成。
          点选任一等级可查看该等级的用户。
        </p>
      </div>
      <div class="panel-head-actions">
        <span v-if="edited" class="pill amber">有未保存的修改</span>
        <span v-else class="pill success">已保存</span>
      </div>
    </div>

    <div class="level-preview">
      <button
        v-for="stat in levels"
        :key="stat.level"
        type="button"
        class="level-card level-card-link"
        :title="`查看 LV${stat.level} 的用户`"
        @click="emit('open-level', stat.level)"
      >
        <div class="level-card-head">
          <span class="level-badge">LV{{ stat.level }}</span>
          <span class="level-range">{{ rangeLabel(stat.level) }}</span>
        </div>
        <strong class="level-count">{{ formatNumber(stat.userCount) }} 人</strong>
        <div class="level-bar">
          <span :style="{ width: `${barWidth(stat)}%` }"></span>
        </div>
        <span class="level-percent">
          占全部用户 {{ formatNumber(stat.percent, 1) }}%
          <Users :size="13" class="level-card-action" />
        </span>
      </button>
    </div>

    <div
      v-if="recomputing"
      class="info-note compact recompute-note"
      role="status"
      aria-live="polite"
    >
      <LoaderCircle :size="15" class="spin" />
      <span>
        正在后台重算全站成就{{ config.recompute.pending ? '（还有一次修改待处理）' : '' }}，
        等级人数会自动刷新，期间页面显示的是重算前的数字。
        <template v-if="config.recompute.lastStartedAt">
          本轮开始于 {{ formatDateTime(config.recompute.lastStartedAt) }}。
        </template>
      </span>
    </div>
    <div v-else-if="config.recompute.lastError" class="info-note compact recompute-note error">
      <TriangleAlert :size="15" />
      <span>
        上次全站成就重算失败：{{ config.recompute.lastError }}。等级人数可能不是最新，
        可再次保存分界线重试。
      </span>
    </div>
    <div v-else-if="config.recompute.lastFinishedAt" class="info-note compact">
      <CheckCircle2 :size="15" />
      <span>
        全站成就重算已完成（{{ formatDateTime(config.recompute.lastFinishedAt) }}）。
      </span>
    </div>

    <form class="form-section" @submit.prevent="save">
      <h3>经验门槛</h3>
      <div class="level-input-grid">
        <label class="field">
          <span class="field-label">LV0 <em>*</em></span>
          <input :value="0" type="number" disabled />
          <small class="field-hint">固定为 0</small>
        </label>
        <label
          v-for="level in thresholds.length - 1"
          :key="level"
          class="field"
        >
          <span class="field-label">LV{{ level }} <em>*</em></span>
          <input
            v-model.number="thresholds[level]"
            type="number"
            min="1"
            max="1000000"
            step="1"
            inputmode="numeric"
            required
          />
          <small class="field-hint">达到该经验值升至 LV{{ level }}</small>
        </label>
      </div>

      <div class="info-note compact">
        <Info :size="15" />
        <span>
          「达到 3/5/6 级」等成就按这里的门槛计算。保存后服务端会在后台重算全站成就，
          用户已获得的经验与成就可能随之变化；耗时随用户数与行程数增长，用户较多时可能需要较长时间。
          <template v-if="config.updatedAt">
            上次修改：{{ formatDateTime(config.updatedAt) }}。
          </template>
        </span>
      </div>

      <div class="form-actions">
        <button type="submit" class="button primary" :disabled="saving || resetting">
          <LoaderCircle v-if="saving" :size="16" class="spin" />
          <Save v-else :size="16" />
          {{ saving ? '正在保存…' : '保存分界线' }}
        </button>
        <button
          type="button"
          class="button ghost"
          :disabled="saving || resetting"
          @click="resetDefaults"
        >
          <LoaderCircle v-if="resetting" :size="16" class="spin" />
          <RotateCcw v-else :size="16" />
          {{ resetting ? '正在恢复…' : '恢复默认值' }}
        </button>
      </div>
    </form>
  </section>
</template>
