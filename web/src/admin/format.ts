export function formatNumber(value: number, digits = 0): string {
  if (!Number.isFinite(value)) return '—'
  return value.toLocaleString('zh-CN', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  })
}

export function formatMileage(value: number): string {
  return `${formatNumber(value, value >= 100 ? 0 : 1)} km`
}

export function formatBytes(value: number): string {
  if (!Number.isFinite(value) || value <= 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let size = value
  let index = 0
  while (size >= 1024 && index < units.length - 1) {
    size /= 1024
    index++
  }
  return `${size.toFixed(index === 0 ? 0 : 1)} ${units[index]}`
}

export function formatMoney(value: number): string {
  if (!Number.isFinite(value)) return '¥—'
  // 票价保留真实的两位小数，不能因为过了 100 元就把 .5 元舍掉。
  return `¥${value.toLocaleString('zh-CN', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })}`
}

export function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) return '—'
  const totalMinutes = Math.round(seconds / 60)
  const days = Math.floor(totalMinutes / 1440)
  const hours = Math.floor((totalMinutes % 1440) / 60)
  const minutes = totalMinutes % 60
  if (days > 0) return `${days} 天 ${hours} 小时`
  if (hours > 0) return `${hours} 小时 ${minutes} 分`
  return `${minutes} 分钟`
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return '—'
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return iso.slice(0, 10)
  return date.toLocaleDateString('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })
}

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '—'
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  return date.toLocaleString('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function dateInputValue(iso: string | null | undefined): string {
  return iso ? iso.slice(0, 10) : ''
}

export function dateTimeInputValue(iso: string | null | undefined): string {
  return iso ? iso.slice(0, 16) : ''
}

export function shortId(id: string): string {
  return id.length > 12 ? `${id.slice(0, 8)}…${id.slice(-4)}` : id
}

export function initials(name: string): string {
  const trimmed = name.trim()
  return trimmed.length > 0 ? Array.from(trimmed).slice(0, 2).join('') : '?'
}
