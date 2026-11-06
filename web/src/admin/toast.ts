import { reactive } from 'vue'

export type ToastKind = 'success' | 'error' | 'info'

export interface ToastItem {
  id: number
  message: string
  kind: ToastKind
}

export const toasts = reactive<ToastItem[]>([])
let nextId = 1

export function toast(message: string, kind: ToastKind = 'success'): void {
  const id = nextId++
  toasts.push({ id, message, kind })
  window.setTimeout(() => dismiss(id), kind === 'error' ? 6000 : 3500)
}

export function dismiss(id: number): void {
  const index = toasts.findIndex((item) => item.id === id)
  if (index >= 0) toasts.splice(index, 1)
}
