<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  ArrowRight,
  ChevronLeft,
  ChevronRight,
  Copy,
  Inbox,
  LoaderCircle,
  MessageSquareText,
  Pencil,
  RefreshCw,
  Search,
  Ticket,
  Trash2,
  TriangleAlert,
  Users,
} from '@lucide/vue'
import { api, ApiError, PAGE_SIZE, type AdminUserPage, type AdminUserSummary } from '../api'
import { confirmByTyping } from '../confirm'
import { formatDate, formatNumber, initials, shortId } from '../format'
import SortHeader from './SortHeader.vue'
import { nextSort, type SortDirection, type SortState } from '../sort'
import { toast } from '../toast'

const props = defineProps<{
  /** 从等级分布卡片跳转过来时预选的等级。 */
  initialLevel?: number | null
}>()

const emit = defineEmits<{
  'open-user': [id: string]
  'open-trip': [userId: string, ticketId: number]
  'view-reviews': [userId: string, displayName: string]
}>()

const LEVEL_COUNT = 7
const query = ref('')
const submittedQuery = ref('')
const selectedLevel = ref<number | null>(
  props.initialLevel !== null && props.initialLevel !== undefined &&
    props.initialLevel >= 0 && props.initialLevel < LEVEL_COUNT
    ? props.initialLevel
    : null,
)
const offset = ref(0)
// 服务端默认按注册时间倒序，表头状态与之保持一致。
const sort = ref<SortState>({ key: 'created', direction: 'desc' })
const data = ref<AdminUserPage | null>(null)
const loading = ref(true)
const error = ref('')
const tripQuery = ref('')
const locating = ref(false)
const editing = ref<AdminUserSummary | null>(null)
const saving = ref(false)
const deletingId = ref('')

interface EditForm {
  displayName: string
  email: string
  avatarUrl: string
  bio: string
  showEmailOnProfile: boolean
}

const editForm = ref<EditForm>({
  displayName: '',
  email: '',
  avatarUrl: '',
  bio: '',
  showEmailOnProfile: false,
})

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
    data.value = await api.users(
      submittedQuery.value,
      selectedLevel.value,
      offset.value,
      PAGE_SIZE,
      sort.value,
    )
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取用户列表失败'
  } finally {
    loading.value = false
  }
}

function search(): void {
  submittedQuery.value = query.value.trim()
  offset.value = 0
  void load()
}

function clearSearch(): void {
  query.value = ''
  submittedQuery.value = ''
  selectedLevel.value = null
  offset.value = 0
  void load()
}

function changeLevel(event: Event): void {
  const raw = (event.target as HTMLSelectElement).value
  selectedLevel.value = raw === '' ? null : Number(raw)
  offset.value = 0
  void load()
}

/** 文本列先升序（便于按拼音找名字），数值与时间列先降序（先看最高/最近）。 */
const SORT_INITIAL: Record<string, SortDirection> = { name: 'asc', email: 'asc' }

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

async function locateTrip(): Promise<void> {
  const raw = tripQuery.value.trim()
  if (!raw) return
  const ticketId = Number(raw)
  if (!/^\d+$/.test(raw) || !Number.isSafeInteger(ticketId) || ticketId <= 0) {
    toast('请输入有效的行程 ID（纯数字）', 'error')
    return
  }
  locating.value = true
  try {
    const trip = await api.trip(ticketId)
    if (trip.deletedAt) toast('该行程已被删除，仍可在编辑器中查看或恢复', 'info')
    tripQuery.value = ''
    emit('open-trip', trip.userId, trip.ticketId)
  } catch (exception) {
    toast(
      exception instanceof ApiError ? exception.message : '没有找到该行程',
      'error',
    )
  } finally {
    locating.value = false
  }
}

async function openEdit(user: AdminUserSummary): Promise<void> {
  try {
    const detail = await api.user(user.id)
    editForm.value = {
      displayName: detail.displayName,
      email: detail.email,
      avatarUrl: detail.avatarUrl ?? '',
      bio: detail.bio ?? '',
      showEmailOnProfile: detail.showEmailOnProfile ?? false,
    }
    editing.value = detail
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '读取用户信息失败', 'error')
  }
}

function closeEdit(): void {
  if (saving.value) return
  editing.value = null
}

async function saveEdit(): Promise<void> {
  if (!editing.value) return
  const form = editForm.value
  if (form.displayName.trim().length < 2) {
    toast('昵称长度至少 2 个字符', 'error')
    return
  }
  if (!form.email.includes('@')) {
    toast('请填写有效的邮箱地址', 'error')
    return
  }
  saving.value = true
  try {
    const updated = await api.updateUser(editing.value.id, {
      displayName: form.displayName.trim(),
      email: form.email.trim(),
      avatarUrl: form.avatarUrl.trim() || null,
      bio: form.bio.trim() || null,
      showEmailOnProfile: form.showEmailOnProfile,
    })
    if (data.value) {
      const index = data.value.items.findIndex((item) => item.id === updated.id)
      if (index >= 0) data.value.items[index] = { ...data.value.items[index], ...updated }
    }
    toast('用户信息已更新', 'success')
    editing.value = null
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '保存失败', 'error')
  } finally {
    saving.value = false
  }
}

async function removeUser(user: AdminUserSummary): Promise<void> {
  const confirmed = confirmByTyping({
    title: `删除用户「${user.displayName}」`,
    message: '该账户的全部行程、评价、成就与登录令牌都会被永久清除。',
    expected: user.displayName,
  })
  if (!confirmed) return
  deletingId.value = user.id
  try {
    await api.deleteUser(user.id)
    toast('用户已删除', 'info')
    await load()
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '删除失败', 'error')
  } finally {
    deletingId.value = ''
  }
}

async function copyId(id: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(id)
    toast('用户 ID 已复制', 'info')
  } catch {
    window.prompt('复制用户 ID', id)
  }
}

onMounted(load)
</script>

<template>
  <div class="page-stack">
    <section class="panel">
      <div class="panel-head">
        <div>
          <h2>用户检索</h2>
          <p>支持按昵称、邮箱模糊搜索，或输入完整用户 ID 精确查找。</p>
        </div>
      </div>

      <form class="search-bar" @submit.prevent="search">
        <span class="search-input">
          <Search :size="18" />
          <input
            v-model="query"
            type="search"
            placeholder="搜索昵称、邮箱或用户 ID"
            autocomplete="off"
          />
        </span>
        <select
          class="select"
          :value="selectedLevel ?? ''"
          aria-label="按等级筛选"
          @change="changeLevel"
        >
          <option value="">全部等级</option>
          <option v-for="level in LEVEL_COUNT" :key="level - 1" :value="level - 1">
            LV{{ level - 1 }}
          </option>
        </select>
        <button type="submit" class="button primary" :disabled="loading">
          <Search :size="16" /> 搜索
        </button>
        <button type="button" class="button ghost" :disabled="loading" @click="clearSearch">
          <RefreshCw :size="16" /> 重置
        </button>
      </form>
      <p v-if="selectedLevel !== null" class="filter-note">
        正在查看 LV{{ selectedLevel }} 的用户
        <button type="button" class="link-button" @click="clearSearch">显示全部等级</button>
      </p>

      <div class="trip-locate-bar">
        <span class="search-input compact">
          <Ticket :size="16" />
          <input
            v-model="tripQuery"
            type="text"
            inputmode="numeric"
            placeholder="按行程 ID 直接定位"
            autocomplete="off"
            @keydown.enter.prevent="locateTrip"
          />
        </span>
        <button
          type="button"
          class="button ghost"
          :disabled="locating || !tripQuery.trim()"
          @click="locateTrip"
        >
          <LoaderCircle v-if="locating" :size="16" class="spin" />
          <Ticket v-else :size="16" />
          {{ locating ? '定位中…' : '定位行程' }}
        </button>
        <span class="trip-locate-hint">找到行程所属用户并直接打开编辑器</span>
      </div>

      <div v-if="loading" class="state-card inline">
        <LoaderCircle :size="20" class="spin" /><span>正在读取用户…</span>
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
        <p>换一个昵称、邮箱或完整的用户 ID 再试一次。</p>
      </div>

      <template v-else>
        <div class="table-wrap">
          <table class="data-table users-table">
            <thead>
              <tr>
                <SortHeader label="用户" sort-key="name" :active="sort.key === 'name'" :direction="sort.direction" @sort="changeSort" />
                <SortHeader label="邮箱" sort-key="email" :active="sort.key === 'email'" :direction="sort.direction" @sort="changeSort" />
                <SortHeader label="等级" sort-key="level" align="right" :active="sort.key === 'level'" :direction="sort.direction" @sort="changeSort" />
                <SortHeader label="有效行程" sort-key="trips" align="right" :active="sort.key === 'trips'" :direction="sort.direction" @sort="changeSort" />
                <SortHeader label="已删除" sort-key="deleted" align="right" :active="sort.key === 'deleted'" :direction="sort.direction" @sort="changeSort" />
                <SortHeader label="成就经验" sort-key="experience" align="right" :active="sort.key === 'experience'" :direction="sort.direction" @sort="changeSort" />
                <SortHeader class="col-time" label="注册时间" sort-key="created" :active="sort.key === 'created'" :direction="sort.direction" @sort="changeSort" />
                <th class="col-actions">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="user in data.items" :key="user.id">
                <td>
                  <div class="user-cell">
                    <img v-if="user.avatarUrl" :src="user.avatarUrl" alt="" class="avatar image" />
                    <span v-else class="avatar">{{ initials(user.displayName) }}</span>
                    <div>
                      <strong>{{ user.displayName }}</strong>
                      <button type="button" class="id-line" :title="user.id" @click="copyId(user.id)">
                        <code>{{ shortId(user.id) }}</code>
                        <Copy :size="12" />
                      </button>
                    </div>
                  </div>
                </td>
                <td class="muted-text">{{ user.email || '—' }}</td>
                <td class="col-number"><span class="pill subtle">LV{{ user.level }}</span></td>
                <td class="col-number"><strong>{{ formatNumber(user.tripCount) }}</strong></td>
                <td class="col-number muted-text">{{ formatNumber(user.deletedTripCount) }}</td>
                <td class="col-number"><span class="pill amber">{{ formatNumber(user.achievementExperience) }}</span></td>
                <td class="muted-text">{{ formatDate(user.createdAt) }}</td>
                <td>
                  <div class="row-actions">
                    <button type="button" class="button subtle small" @click="openEdit(user)">
                      <Pencil :size="15" /> 编辑
                    </button>
                    <button type="button" class="button subtle small" @click="emit('open-user', user.id)">
                      管理行程 <ArrowRight :size="15" />
                    </button>
                    <button
                      type="button"
                      class="icon-button"
                      title="查看该用户的评价"
                      @click="emit('view-reviews', user.id, user.displayName)"
                    >
                      <MessageSquareText :size="16" />
                    </button>
                    <button
                      type="button"
                      class="icon-button danger"
                      title="删除用户"
                      :disabled="deletingId === user.id"
                      @click="removeUser(user)"
                    >
                      <LoaderCircle v-if="deletingId === user.id" :size="16" class="spin" />
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

    <div v-if="editing" class="modal-backdrop" @click.self="closeEdit">
      <div class="modal narrow" role="dialog" aria-modal="true" aria-labelledby="user-edit-title">
        <header class="modal-head">
          <div>
            <h2 id="user-edit-title">编辑用户</h2>
            <p>{{ editing.id }}</p>
          </div>
          <button type="button" class="icon-button" aria-label="关闭" :disabled="saving" @click="closeEdit">
            <span aria-hidden="true">✕</span>
          </button>
        </header>

        <form class="modal-body user-edit-form" @submit.prevent="saveEdit">
          <div class="field-grid">
            <label class="field">
              <span class="field-label">昵称 <em>*</em></span>
              <input v-model="editForm.displayName" maxlength="40" required />
            </label>
            <label class="field">
              <span class="field-label">邮箱 <em>*</em></span>
              <input v-model="editForm.email" type="email" maxlength="200" required />
            </label>
          </div>

          <label class="field">
            <span class="field-label">头像地址</span>
            <input v-model="editForm.avatarUrl" maxlength="1000" placeholder="https://…" />
          </label>

          <label class="field">
            <span class="field-label">个人简介</span>
            <textarea v-model="editForm.bio" rows="3" maxlength="300" />
          </label>

          <label class="switch-row compact-switch">
            <span>
              <strong>在公开主页展示邮箱</strong>
              <small>关闭后其他人看不到该用户的邮箱</small>
            </span>
            <input v-model="editForm.showEmailOnProfile" type="checkbox" class="switch" />
          </label>

          <p class="field-hint">修改邮箱会同时改变登录账号，请确认新邮箱可以正常接收验证邮件。</p>
        </form>

        <footer class="modal-foot">
          <button type="button" class="button ghost" :disabled="saving" @click="closeEdit">取消</button>
          <button type="button" class="button primary" :disabled="saving" @click="saveEdit">
            <LoaderCircle v-if="saving" :size="16" class="spin" />
            {{ saving ? '正在保存…' : '保存修改' }}
          </button>
        </footer>
      </div>
    </div>
  </div>
</template>
