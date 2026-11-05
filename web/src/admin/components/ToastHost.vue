<script setup lang="ts">
import { CircleAlert, CircleCheck, Info, X } from '@lucide/vue'
import { dismiss, toasts } from '../toast'

const icons = {
  success: CircleCheck,
  error: CircleAlert,
  info: Info,
}
</script>

<template>
  <div class="toast-host" aria-live="polite" aria-atomic="false">
    <TransitionGroup name="toast">
      <div v-for="item in toasts" :key="item.id" :class="['toast', item.kind]">
        <component :is="icons[item.kind]" :size="19" />
        <span>{{ item.message }}</span>
        <button type="button" aria-label="关闭" @click="dismiss(item.id)">
          <X :size="15" />
        </button>
      </div>
    </TransitionGroup>
  </div>
</template>
