<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import {
  BellRing,
  Check,
  LoaderCircle,
  Search,
  Send,
  TriangleAlert,
  UserPlus,
  Users,
  X,
} from '@lucide/vue'
import { api, ApiError, type AdminUserSummary } from '../api'
import { confirmDestructive } from '../confirm'
import { initials } from '../format'
import { toast } from '../toast'

const MESSAGE_LIMIT = 1000

const message = ref('')
const allUsers = ref(true)
const recipients = ref<AdminUserSummary[]>([])
const search = ref('')
const results = ref<AdminUserSummary[]>([])
const searching = ref(false)
const searchError = ref('')
const sending = ref(false)

let searchTimer: number | undefined
let searchSequence = 0

const trimmedMessage = computed(() => message.value.trim())
const selectedIds = computed(() => new Set(recipients.value.map((user) => user.id)))
const visibleResults = computed(() =>
  results.value.filter((user) => !selectedIds.value.has(user.id)),
)
const canSend = computed(
  () =>
    trimmedMessage.value.length > 0 &&
    (allUsers.value || recipients.value.length > 0) &&
    !sending.value,
)

watch(search, (value) => {
  window.clearTimeout(searchTimer)
  const query = value.trim()
  if (!query) {
    results.value = []
    searchError.value = ''
    searching.value = false
    return
  }
  searchTimer = window.setTimeout(() => void runSearch(query), 300)
})

async function runSearch(query: string): Promise<void> {
  const sequence = ++searchSequence
  searching.value = true
  searchError.value = ''
  try {
    const page = await api.users(query, null, 0, 20)
    if (sequence !== searchSequence) return
    results.value = page.items
  } catch (exception) {
    if (sequence !== searchSequence) return
    results.value = []
    searchError.value =
      exception instanceof ApiError ? exception.message : '搜索用户失败'
  } finally {
    if (sequence === searchSequence) searching.value = false
  }
}

function addRecipient(user: AdminUserSummary): void {
  if (selectedIds.value.has(user.id)) return
  recipients.value = [...recipients.value, user]
}

function removeRecipient(userId: string): void {
  recipients.value = recipients.value.filter((user) => user.id !== userId)
}

async function send(): Promise<void> {
  if (!canSend.value) return
  const text = trimmedMessage.value
  const scope = allUsers.value ? '全部用户' : `${recipients.value.length} 位用户`
  const confirmed = confirmDestructive({
    title: '发送系统通知',
    message: `将向${scope}发送以下通知：\n\n${text}`,
    footnote: '通知发出后无法撤回。',
  })
  if (!confirmed) return

  sending.value = true
  try {
    const result = await api.sendNotification(
      text,
      allUsers.value,
      recipients.value.map((user) => user.id),
    )
    toast(`通知已发送给 ${result.recipientCount} 位用户`)
    message.value = ''
    recipients.value = []
    search.value = ''
    results.value = []
  } catch (exception) {
    toast(exception instanceof ApiError ? exception.message : '发送失败', 'error')
  } finally {
    sending.value = false
  }
}

onBeforeUnmount(() => {
  window.clearTimeout(searchTimer)
})
</script>

<template>
  <div class="page-stack">
    <section class="panel notification-compose">
      <div class="panel-head">
        <div>
          <h2>发送系统通知</h2>
          <p>
            通知会出现在每位目标用户的 App 通知收件箱中，只支持纯文字，不附带跳转操作。
          </p>
        </div>
      </div>

      <label class="field">
        <span class="field-label">通知内容 <em>*</em></span>
        <textarea
          v-model="message"
          rows="5"
          :maxlength="MESSAGE_LIMIT"
          placeholder="例如：系统将于今晚 23:00 进行维护，期间可能无法同步行程。"
        />
        <span class="field-hint">{{ message.length }} / {{ MESSAGE_LIMIT }}</span>
      </label>

      <div class="field">
        <span class="field-label">接收范围</span>
        <div class="recipient-modes">
          <button
            type="button"
            :class="['button', 'ghost', { selected: allUsers }]"
            @click="allUsers = true"
          >
            <Users :size="16" /> 全部用户
          </button>
          <button
            type="button"
            :class="['button', 'ghost', { selected: !allUsers }]"
            @click="allUsers = false"
          >
            <UserPlus :size="16" /> 指定用户
          </button>
        </div>
      </div>

      <div v-if="!allUsers" class="field">
        <span class="field-label">选择用户</span>
        <span class="search-input">
          <Search :size="18" />
          <input
            v-model="search"
            type="search"
            placeholder="搜索昵称、邮箱或用户 ID"
            autocomplete="off"
          />
        </span>
        <div v-if="searching" class="notification-search-state">
          <LoaderCircle :size="16" class="spin" /><span>正在搜索用户…</span>
        </div>
        <div v-else-if="searchError" class="notification-search-state error">
          <TriangleAlert :size="16" /><span>{{ searchError }}</span>
        </div>
        <div v-else-if="visibleResults.length > 0" class="recipient-results">
          <button
            v-for="user in visibleResults"
            :key="user.id"
            type="button"
            class="recipient-option"
            @click="addRecipient(user)"
          >
            <span class="avatar small">{{ initials(user.displayName) }}</span>
            <span class="recipient-copy">
              <strong>{{ user.displayName }}</strong>
              <small>{{ user.email || user.id }}</small>
            </span>
            <UserPlus :size="16" />
          </button>
        </div>
        <p v-else-if="search.trim()" class="field-hint">没有找到匹配的用户。</p>

        <div v-if="recipients.length > 0" class="recipient-chips">
          <span v-for="user in recipients" :key="user.id" class="recipient-chip">
            {{ user.displayName }}
            <button
              type="button"
              :aria-label="`移除 ${user.displayName}`"
              @click="removeRecipient(user.id)"
            >
              <X :size="13" />
            </button>
          </span>
        </div>
        <span v-else class="field-hint">尚未选择用户，至少选择一位后才能发送。</span>
      </div>

      <div class="announcement-preview-card">
        <BellRing :size="18" />
        <span>{{ trimmedMessage || '通知预览将在这里显示' }}</span>
      </div>

      <div class="notification-actions">
        <span class="field-hint">
          {{
            allUsers
              ? '将发送给全部已注册用户'
              : `将发送给已选择的 ${recipients.length} 位用户`
          }}
        </span>
        <button
          type="button"
          class="button primary"
          :disabled="!canSend"
          @click="send"
        >
          <LoaderCircle v-if="sending" :size="17" class="spin" />
          <Send v-else :size="17" />
          {{ sending ? '正在发送…' : '发送通知' }}
        </button>
      </div>
    </section>

    <p class="info-note">
      <Check :size="16" />
      通知写入用户收件箱后立即生效，无需等待。用户可以在 App 通知页逐条阅读并标记已读。
    </p>
  </div>
</template>
