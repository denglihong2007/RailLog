<script setup lang="ts">
import { ExternalLink, Pencil, Trash2 } from '@lucide/vue'
import type { AdminDuplicateGroup, AdminDuplicateTrip } from '../api'
import { formatDate, formatDateTime, formatMileage, formatMoney, initials } from '../format'

defineProps<{
  groups: AdminDuplicateGroup[]
  busy?: boolean
}>()

const emit = defineEmits<{
  'delete-trip': [trip: AdminDuplicateTrip]
  'keep-earliest': [group: AdminDuplicateGroup]
  'open-trip': [userId: string, ticketId: number]
  'open-user': [userId: string]
}>()

function groupKey(group: AdminDuplicateGroup): string {
  return [
    group.userId,
    group.trainNumber,
    group.travelDate,
    group.fromStation,
    group.toStation,
  ].join(':')
}

function timeRange(trip: AdminDuplicateTrip): string {
  const departure = trip.departureTime ? formatDateTime(trip.departureTime) : '—'
  const arrival = trip.arrivalTime ? formatDateTime(trip.arrivalTime) : '—'
  return `${departure} → ${arrival}`
}
</script>

<template>
  <div class="duplicate-groups">
    <article v-for="group in groups" :key="groupKey(group)" class="duplicate-group">
      <header class="duplicate-head">
        <div class="duplicate-head-main">
          <strong>{{ group.trainNumber }}</strong>
          <span class="muted-text">{{ group.fromStation }} → {{ group.toStation }}</span>
          <span class="muted-text">{{ formatDate(group.travelDate) }}</span>
          <span class="muted-text" title="最早录入记录的里程与票价">
            {{ formatMileage(group.mileageKm) }} · {{ formatMoney(group.price) }}
          </span>
          <button
            type="button"
            class="user-chip-button"
            :title="`查看 ${group.displayName} 的行程`"
            @click="emit('open-user', group.userId)"
          >
            <span class="avatar small">{{ initials(group.displayName) }}</span>
            <span class="user-chip-copy"><strong>{{ group.displayName }}</strong></span>
          </button>
        </div>
        <div class="duplicate-head-actions">
          <span class="pill amber">{{ group.trips.length }} 条</span>
          <button
            type="button"
            class="button subtle small"
            :disabled="busy"
            title="保留最早录入的一条，删除同组其余记录"
            @click="emit('keep-earliest', group)"
          >
            保留最早录入
          </button>
        </div>
      </header>

      <div class="table-wrap">
        <table class="data-table duplicate-table">
          <thead>
            <tr>
              <th>行程</th>
              <th>发车 → 到达</th>
              <th class="col-number">里程</th>
              <th class="col-number">票价</th>
              <th class="col-time">录入时间</th>
              <th class="col-actions">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(trip, index) in group.trips" :key="trip.ticketId">
              <td>
                <button
                  type="button"
                  class="trip-link"
                  :title="`定位并编辑行程 #${trip.ticketId}`"
                  @click="emit('open-trip', group.userId, trip.ticketId)"
                >
                  {{ trip.fromStation }} → {{ trip.toStation }}
                  <ExternalLink :size="12" />
                </button>
                <small class="sub-line">
                  #{{ trip.ticketId }}
                  <template v-if="trip.rollingStock"> · {{ trip.rollingStock }}</template>
                  <template v-if="trip.seatType"> · {{ trip.seatType }} {{ trip.seatNumber }}</template>
                </small>
              </td>
              <td class="muted-text">{{ timeRange(trip) }}</td>
              <td class="col-number">{{ formatMileage(trip.mileageKm) }}</td>
              <td class="col-number">{{ formatMoney(trip.price) }}</td>
              <td class="col-time muted-text">
                {{ formatDateTime(trip.createdAt) }}
                <span v-if="index === 0" class="pill subtle">最早</span>
              </td>
              <td>
                <div class="row-actions">
                  <button
                    type="button"
                    class="button subtle small"
                    @click="emit('open-trip', group.userId, trip.ticketId)"
                  >
                    <Pencil :size="15" /> 编辑
                  </button>
                  <button
                    type="button"
                    class="icon-button danger"
                    title="删除这条重复行程"
                    :disabled="busy"
                    @click="emit('delete-trip', trip)"
                  >
                    <Trash2 :size="16" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </article>
  </div>
</template>
