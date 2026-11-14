<script setup lang="ts">
import { ref, watch } from 'vue'
import { MessageSquareReply, MessageSquareText, Users } from '@lucide/vue'
import type { AdminReviewUser } from '../api'
import ReviewListView from './ReviewListView.vue'
import ReactionListView from './ReactionListView.vue'
import ReviewUserListView from './ReviewUserListView.vue'

type Tab = 'reviews' | 'reactions' | 'users'

const props = withDefaults(
  defineProps<{
    initialQuery?: string
    initialEntityType?: string
    initialUserId?: string
    initialUserName?: string
    initialTab?: Tab
  }>(),
  {
    initialQuery: '',
    initialEntityType: '',
    initialUserId: '',
    initialUserName: '',
    initialTab: 'reviews',
  },
)

const emit = defineEmits<{
  'open-user': [id: string]
  'open-trip': [userId: string, ticketId: number]
  navigate: [path: string]
}>()

const tab = ref<Tab>(props.initialTab)
const reviewAuthor = ref({
  id: props.initialUserId,
  name: props.initialUserName,
})
const reactionFilter = ref({
  reactorId: '',
  reactorName: '',
  authorId: '',
  authorName: '',
})

function viewAuthor(userId: string, displayName: string): void {
  reviewAuthor.value = { id: userId, name: displayName }
  tab.value = 'reviews'
  emit(
    'navigate',
    `/reviews?userId=${encodeURIComponent(userId)}&userName=${encodeURIComponent(displayName)}`,
  )
}

function clearReviewAuthor(): void {
  reviewAuthor.value = { id: '', name: '' }
  emit('navigate', '/reviews')
}

function viewUserReviews(user: AdminReviewUser): void {
  viewAuthor(user.userId, user.displayName)
}

function viewGivenReactions(user: AdminReviewUser): void {
  reactionFilter.value = {
    reactorId: user.userId,
    reactorName: user.displayName,
    authorId: '',
    authorName: '',
  }
  tab.value = 'reactions'
}

function viewReceivedReactions(user: AdminReviewUser): void {
  reactionFilter.value = {
    reactorId: '',
    reactorName: '',
    authorId: user.userId,
    authorName: user.displayName,
  }
  tab.value = 'reactions'
}

function clearReactor(): void {
  reactionFilter.value = {
    ...reactionFilter.value,
    reactorId: '',
    reactorName: '',
  }
}

function clearReactionAuthor(): void {
  reactionFilter.value = {
    ...reactionFilter.value,
    authorId: '',
    authorName: '',
  }
}

watch(
  () => [props.initialTab, props.initialUserId, props.initialUserName] as const,
  ([nextTab, nextUserId, nextUserName]) => {
    tab.value = nextTab
    reviewAuthor.value = { id: nextUserId, name: nextUserName }
  },
)
</script>

<template>
  <div class="page-stack">
    <div class="tab-bar">
      <button
        type="button"
        :class="['tab', { active: tab === 'reviews' }]"
        @click="tab = 'reviews'"
      >
        <MessageSquareText :size="16" /> 评价
      </button>
      <button
        type="button"
        :class="['tab', { active: tab === 'reactions' }]"
        @click="tab = 'reactions'"
      >
        <MessageSquareReply :size="16" /> 回应
      </button>
      <button
        type="button"
        :class="['tab', { active: tab === 'users' }]"
        @click="tab = 'users'"
      >
        <Users :size="16" /> 评价用户
      </button>
    </div>

    <ReviewListView
      v-if="tab === 'reviews'"
      :initial-query="props.initialQuery"
      :initial-entity-type="props.initialEntityType"
      :user-id="reviewAuthor.id"
      :user-name="reviewAuthor.name"
      @open-user="(id) => emit('open-user', id)"
      @open-trip="(userId, ticketId) => emit('open-trip', userId, ticketId)"
      @view-author="viewAuthor"
      @clear-author="clearReviewAuthor"
    />

    <ReactionListView
      v-else-if="tab === 'reactions'"
      :reactor-id="reactionFilter.reactorId"
      :reactor-name="reactionFilter.reactorName"
      :author-id="reactionFilter.authorId"
      :author-name="reactionFilter.authorName"
      @open-user="(id) => emit('open-user', id)"
      @clear-reactor="clearReactor"
      @clear-author="clearReactionAuthor"
    />

    <ReviewUserListView
      v-else
      @open-user="(id) => emit('open-user', id)"
      @view-reviews="viewUserReviews"
      @view-given="viewGivenReactions"
      @view-received="viewReceivedReactions"
    />
  </div>
</template>
