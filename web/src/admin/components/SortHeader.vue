<script setup lang="ts">
import { ArrowDown, ArrowUp, ChevronsUpDown } from '@lucide/vue'
import type { SortDirection } from '../sort'

const props = defineProps<{
  label: string
  sortKey: string
  active: boolean
  direction: SortDirection
  /** 数值列右对齐，和单元格内容保持一致。 */
  align?: 'left' | 'right'
}>()

defineEmits<{ sort: [key: string] }>()
</script>

<template>
  <th
    :class="['sortable-head', { 'col-number': props.align === 'right', sorted: props.active }]"
    :aria-sort="props.active ? (props.direction === 'asc' ? 'ascending' : 'descending') : 'none'"
  >
    <button type="button" class="sort-button" @click="$emit('sort', props.sortKey)">
      <span>{{ props.label }}</span>
      <ArrowUp v-if="props.active && props.direction === 'asc'" :size="12" class="sort-icon" />
      <ArrowDown v-else-if="props.active" :size="12" class="sort-icon" />
      <ChevronsUpDown v-else :size="12" class="sort-icon sort-idle" />
    </button>
  </th>
</template>
