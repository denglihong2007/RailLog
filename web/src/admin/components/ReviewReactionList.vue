<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { Inbox, LoaderCircle, RefreshCw, Trash2, TriangleAlert } from '@lucide/vue'
import { api, ApiError, type AdminReviewReaction } from '../api'
import { confirmDestructive } from '../confirm'
import { formatDateTime, initials } from '../format'
import { toast } from '../toast'

const props = defineProps<{ reviewId: number }>()

const emit = defineEmits<{
  changed: [count: number]
}>()

const items = ref<AdminReviewReaction[]>([])
const loading = ref(true)
const error = ref('')
const deletingKey = ref('')

const countLabel = computed(() => `${items.value.length} 个回应`)

function itemKey(item: AdminReviewReaction): string {
  return `${item.reviewId}:${item.userId}`
}

async function load(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    items.value = await api.reviewReactions(props.reviewId)
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '读取回应失败'
  } finally {
    loading.value = false
  }
}

async function remove(item: AdminReviewReaction): Promise<void> {
  const confirmed = confirmDestructive({
    title: `删除 ${item.displayName} 的回应`,
    message: `将从这条评价上移除表情 ${item.emoji}。`,
    footnote: '评价作者的「收到回应」类成就会立即重算。此操作无法撤销。',
  })
  if (!confirmed) return

  const key = itemKey(item)
  deletingKey.value = key
  try {
    await api.deleteReviewReaction(item.reviewId, item.userId)
    items.value = items.value.filter((entry) => itemKey(entry) !== key)
    toast('回应已删除', 'info')
    emit('changed', items.value.length)
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '删除回应失败', 'error')
  } finally {
    deletingKey.value = ''
  }
}

watch(() => props.reviewId, load)
onMounted(load)
</script>

<template>
  <section class="reaction-list-section">
    <div class="reaction-list-head">
      <span class="field-label">收到的回应</span>
      <span class="reaction-list-meta">
        {{ countLabel }}
        <button type="button" class="link-button" :disabled="loading" @click="load">
          <RefreshCw :size="13" :class="{ spin: loading }" /> 刷新
        </button>
      </span>
    </div>

    <div v-if="loading" class="state-card inline">
      <LoaderCircle :size="18" class="spin" /><span>正在读取回应…</span>
    </div>
    <div v-else-if="error" class="state-card inline error">
      <TriangleAlert :size="18" /><span>{{ error }}</span>
      <button type="button" class="button ghost small" @click="load">
        <RefreshCw :size="14" /> 重试
      </button>
    </div>
    <div v-else-if="items.length === 0" class="reaction-empty">
      <Inbox :size="18" />
      <span>这条评价还没有收到回应。</span>
    </div>

    <ul v-else class="reaction-list">
      <li v-for="item in items" :key="itemKey(item)">
        <span class="reaction-emoji" :title="item.emoji">{{ item.emoji }}</span>
        <img v-if="item.avatarUrl" :src="item.avatarUrl" alt="" class="avatar small image" />
        <span v-else class="avatar small">{{ initials(item.displayName) }}</span>
        <span class="reaction-user">
          <strong>{{ item.displayName }}</strong>
          <small>{{ item.email || '未提供邮箱' }}</small>
        </span>
        <span class="muted-text reaction-time">{{ formatDateTime(item.createdAt) }}</span>
        <button
          type="button"
          class="icon-button danger"
          title="删除该回应"
          :disabled="deletingKey === itemKey(item)"
          @click="remove(item)"
        >
          <LoaderCircle
            v-if="deletingKey === itemKey(item)"
            :size="15"
            class="spin"
          />
          <Trash2 v-else :size="15" />
        </button>
      </li>
    </ul>
  </section>
</template>
