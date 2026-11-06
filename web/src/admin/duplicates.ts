import { api, ApiError, type AdminDuplicateTrip } from './api'
import { confirmDestructive } from './confirm'

function describe(trip: AdminDuplicateTrip): string {
  return `#${trip.ticketId} ${trip.fromStation} → ${trip.toStation}`
}

/** 全站一键处理：每组保留最早录入的一条，删除其余记录。 */
export function confirmResolveAllDuplicateGroups(groups: number, trips: number): boolean {
  if (groups <= 0) return false
  const removable = Math.max(0, trips - groups)
  return confirmDestructive({
    title: `一键处理全部 ${groups} 组重复行程？`,
    message: `将扫描全站所有疑似重复行程（不只是当前页），每组保留录入时间最早的一条，共删除其余 ${removable} 条记录。`,
    reversible: true,
    footnote: '删除是软删除，之后可以在对应用户的「行程管理」中恢复。',
  })
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
