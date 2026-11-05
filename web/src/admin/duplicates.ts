import { api, ApiError, type AdminDuplicateTrip } from './api'
import { confirmDestructive } from './confirm'

function describe(trip: AdminDuplicateTrip): string {
  return `#${trip.ticketId} ${trip.fromStation} → ${trip.toStation}`
}

export function confirmDeleteDuplicateTrips(trips: AdminDuplicateTrip[]): boolean {
  if (trips.length === 0) return false
  const lines = trips.map((trip) => `· ${describe(trip)}`).join('\n')
  return confirmDestructive({
    title: `删除以下 ${trips.length} 条行程？`,
    message: lines,
    reversible: true,
    footnote: '删除是软删除，之后可以在对应用户的「行程管理」中恢复。',
  })
}

/**
 * 逐条软删除。重复组里的记录通常只有两三条，串行请求足够；
 * 这样单条失败也不会影响其余记录。
 */
export async function deleteDuplicateTrips(
  trips: AdminDuplicateTrip[],
): Promise<{ deleted: number; failed: string[] }> {
  let deleted = 0
  const failed: string[] = []
  for (const trip of trips) {
    try {
      await api.deleteTrip(trip.ticketId)
      deleted += 1
    } catch (exception) {
      const message = exception instanceof ApiError ? exception.message : '删除失败'
      failed.push(`#${trip.ticketId}：${message}`)
    }
  }
  return { deleted, failed }
}
