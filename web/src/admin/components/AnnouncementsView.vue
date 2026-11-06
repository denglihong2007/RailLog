<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import {
  ArrowDown,
  ArrowUp,
  Eye,
  EyeOff,
  Inbox,
  Info,
  LoaderCircle,
  Megaphone,
  Pencil,
  Plus,
  Save,
  Trash2,
  TriangleAlert,
  X,
} from '@lucide/vue'
import { api, ApiError, type AdminAnnouncement } from '../api'
import { confirmDestructive } from '../confirm'
import { formatDateTime } from '../format'
import { toast } from '../toast'

const items = ref<AdminAnnouncement[]>([])
const loading = ref(true)
const error = ref('')
const saving = ref(false)
const reordering = ref(false)
const showEditor = ref(false)
const editingId = ref<string | null>(null)

const form = reactive({
  text: '',
  weight: 10,
  isActive: true,
  sortOrder: 0,
})

const activeCount = computed(() => items.value.filter((item) => item.isActive).length)
const canMove = computed(() => items.value.length > 1)

function resetForm(): void {
  form.text = ''
  form.weight = 10
  form.isActive = true
  form.sortOrder = items.value.length > 0
    ? Math.max(...items.value.map((item) => item.sortOrder)) + 10
    : 10
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    items.value = await api.announcements()
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取公告失败'
  } finally {
    loading.value = false
  }
}

function openCreate(): void {
  editingId.value = null
  resetForm()
  showEditor.value = true
}

function openEdit(item: AdminAnnouncement): void {
  editingId.value = item.id
  form.text = item.text
  form.weight = item.weight
  form.isActive = item.isActive
  form.sortOrder = item.sortOrder
  showEditor.value = true
}

function closeEditor(): void {
  if (saving.value) return
  showEditor.value = false
}

async function save(): Promise<void> {
  if (saving.value) return
  if (!form.text.trim()) {
    toast('公告内容不能为空', 'error')
    return
  }
  saving.value = true
  try {
    await api.saveAnnouncement({
      id: editingId.value,
      text: form.text.trim(),
      weight: form.weight,
      isActive: form.isActive,
      sortOrder: form.sortOrder,
    })
    showEditor.value = false
    await load()
    toast(editingId.value ? '公告已更新' : '公告已发布')
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '保存失败', 'error')
  } finally {
    saving.value = false
  }
}

async function toggle(item: AdminAnnouncement): Promise<void> {
  try {
    const updated = await api.saveAnnouncement({
      id: item.id,
      text: item.text,
      weight: item.weight,
      isActive: !item.isActive,
      sortOrder: item.sortOrder,
    })
    const index = items.value.findIndex((entry) => entry.id === item.id)
    if (index >= 0) items.value[index] = updated
    toast(updated.isActive ? '公告已上线' : '公告已下线', 'info')
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '操作失败', 'error')
  }
}

async function remove(item: AdminAnnouncement): Promise<void> {
  const confirmed = confirmDestructive({
    title: '删除公告',
    message: `${item.text}\n\n删除后 App 主页将不再展示该公告。`,
  })
  if (!confirmed) return
  try {
    await api.deleteAnnouncement(item.id)
    items.value = items.value.filter((entry) => entry.id !== item.id)
    toast('公告已删除')
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '删除失败', 'error')
  }
}

async function move(index: number, direction: -1 | 1): Promise<void> {
  if (reordering.value) return
  const target = index + direction
  if (target < 0 || target >= items.value.length) return
  reordering.value = true
  const next = [...items.value]
  const current = next[index]
  const swap = next[target]
  if (!current || !swap) {
    reordering.value = false
    return
  }
  next[index] = swap
  next[target] = current
  try {
    for (let position = 0; position < next.length; position += 1) {
      const entry = next[position]
      if (!entry) continue
      const sortOrder = (position + 1) * 10
      if (entry.sortOrder === sortOrder) continue
      const updated = await api.saveAnnouncement({
        id: entry.id,
        text: entry.text,
        weight: entry.weight,
        isActive: entry.isActive,
        sortOrder,
      })
      next[position] = updated
    }
    items.value = next
    toast('排序已更新', 'info')
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '排序失败', 'error')
    await load()
  } finally {
    reordering.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="page-stack">
    <section class="panel">
      <div class="panel-head">
        <div>
          <h2>系统公告</h2>
          <p>
            共 {{ items.length }} 条，其中 {{ activeCount }} 条在线。
            权重越高，在 App 主页横幅中出现的概率越大；权重为 0 时不会展示。
          </p>
        </div>
        <button type="button" class="button primary" @click="openCreate">
          <Plus :size="17" /> 新增公告
        </button>
      </div>

      <div v-if="loading" class="state-card inline">
        <LoaderCircle :size="20" class="spin" /><span>正在读取公告…</span>
      </div>
      <div v-else-if="error" class="state-card inline error">
        <TriangleAlert :size="20" /><span>{{ error }}</span>
      </div>

      <div v-else-if="items.length === 0" class="empty-state">
        <span class="empty-icon"><Inbox :size="30" /></span>
        <h3>还没有后台公告</h3>
        <p>新增第一条公告后，App 主页将使用这里的公告，不再显示内置文案。</p>
        <button type="button" class="button primary" @click="openCreate">
          <Plus :size="17" /> 新增公告
        </button>
      </div>

      <div v-else class="table-wrap">
        <table class="data-table announcements-table">
          <thead>
            <tr>
              <th class="col-order">排序</th>
              <th>公告内容</th>
              <th class="col-weight">权重</th>
              <th class="col-status">状态</th>
              <th class="col-time">更新时间</th>
              <th class="col-actions">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(item, index) in items" :key="item.id" :class="{ muted: !item.isActive }">
              <td>
                <div class="order-controls">
                  <button
                    type="button"
                    class="icon-button tiny"
                    :disabled="!canMove || index === 0 || reordering"
                    aria-label="上移"
                    @click="move(index, -1)"
                  >
                    <ArrowUp :size="14" />
                  </button>
                  <button
                    type="button"
                    class="icon-button tiny"
                    :disabled="!canMove || index === items.length - 1 || reordering"
                    aria-label="下移"
                    @click="move(index, 1)"
                  >
                    <ArrowDown :size="14" />
                  </button>
                </div>
              </td>
              <td>
                <p class="announcement-text">{{ item.text }}</p>
                <p class="announcement-preview">
                  <Megaphone :size="14" /> 主页横幅预览
                </p>
              </td>
              <td><span class="pill neutral">{{ item.weight }}</span></td>
              <td>
                <span :class="['pill', item.isActive ? 'success' : 'neutral']">
                  {{ item.isActive ? '在线' : '已下线' }}
                </span>
              </td>
              <td class="muted-text">{{ formatDateTime(item.updatedAt) }}</td>
              <td>
                <div class="row-actions">
                  <button
                    type="button"
                    class="button subtle small"
                    :disabled="reordering"
                    @click="toggle(item)"
                  >
                    <EyeOff v-if="item.isActive" :size="15" />
                    <Eye v-else :size="15" />
                    {{ item.isActive ? '下线' : '上线' }}
                  </button>
                  <button type="button" class="button subtle small" @click="openEdit(item)">
                    <Pencil :size="15" /> 编辑
                  </button>
                  <button
                    type="button"
                    class="icon-button danger"
                    title="删除公告"
                    aria-label="删除公告"
                    @click="remove(item)"
                  >
                    <Trash2 :size="16" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <p class="info-note">
      <Info :size="16" />
      公告按 App 启动时的接口响应获取，修改后用户重新打开或刷新主页即可看到。
    </p>

    <Teleport to="body">
      <div v-if="showEditor" class="modal-backdrop" @click.self="closeEditor">
        <div class="modal narrow" role="dialog" aria-modal="true" aria-labelledby="announcement-editor-title">
          <header class="modal-head">
            <div>
              <h2 id="announcement-editor-title">{{ editingId ? '编辑公告' : '新增公告' }}</h2>
              <p>公告会与合作伙伴推荐共同参与主页横幅的轮播</p>
            </div>
            <button type="button" class="icon-button" aria-label="关闭" @click="closeEditor">
              <X :size="19" />
            </button>
          </header>

          <div class="modal-body">
            <label class="field">
              <span class="field-label">公告内容 <em>*</em></span>
              <textarea
                v-model="form.text"
                rows="3"
                maxlength="256"
                placeholder="例如：线路数据库已经更新！"
              />
              <span class="field-hint">{{ form.text.length }} / 256</span>
            </label>

            <div class="field-row">
              <label class="field">
                <span class="field-label">权重</span>
                <input v-model.number="form.weight" type="number" min="0" max="1000" step="1" />
                <span class="field-hint">0 表示不在首页展示</span>
              </label>
              <label class="field">
                <span class="field-label">排序</span>
                <input v-model.number="form.sortOrder" type="number" min="0" max="9999" step="10" />
                <span class="field-hint">数字越小越靠前</span>
              </label>
            </div>

            <label class="switch-row">
              <span>
                <strong>立即上线</strong>
                <small>关闭后保留内容，但不在 App 中展示</small>
              </span>
              <input v-model="form.isActive" type="checkbox" class="switch" />
            </label>

            <div class="announcement-preview-card">
              <Megaphone :size="18" />
              <span>{{ form.text.trim() || '公告预览将在这里显示' }}</span>
            </div>
          </div>

          <footer class="modal-foot">
            <button type="button" class="button ghost" :disabled="saving" @click="closeEditor">取消</button>
            <button type="button" class="button primary" :disabled="saving" @click="save">
              <LoaderCircle v-if="saving" :size="17" class="spin" />
              <Save v-else :size="17" />
              {{ editingId ? '保存修改' : '发布公告' }}
            </button>
          </footer>
        </div>
      </div>
    </Teleport>
  </div>
</template>
