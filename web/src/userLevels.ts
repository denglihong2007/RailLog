import { readonly, ref } from 'vue'

/**
 * 公开网站共享的用户等级分界线。
 *
 * 等级门槛可以在管理后台调整，官网不能继续写死一份副本，否则后台改了分界线、
 * 官网徽章仍按旧值显示。这里在首次使用时从公开接口拉取，失败时回退到内置默认值。
 */
const DEFAULT_THRESHOLDS = [0, 1, 50, 125, 250, 450, 800]

const thresholds = ref<number[]>([...DEFAULT_THRESHOLDS])
let request: Promise<void> | null = null
let loaded = false

export const userLevelThresholds = readonly(thresholds)

function applyThresholds(value: unknown): void {
  if (!Array.isArray(value) || value.length < 2) return
  const parsed = value.map((item) => Number(item))
  if (parsed.some((item) => !Number.isInteger(item) || item < 0)) return
  if (parsed[0] !== 0) return
  if (parsed.some((item, index) => index > 0 && item <= (parsed[index - 1] ?? 0))) return
  thresholds.value = parsed
}

/** 拉取一次分界线；成功前返回的 Promise 供调用方按需等待。 */
export function ensureUserLevels(apiBase: string): Promise<void> {
  if (loaded) return Promise.resolve()
  if (request) return request
  request = (async () => {
    try {
      const response = await fetch(`${apiBase}/api/user-levels`)
      if (!response.ok) return
      const body = (await response.json()) as { thresholds?: unknown }
      applyThresholds(body.thresholds)
      loaded = true
    } catch {
      // 网络不可用时保留内置默认值，不影响页面其余内容。
    } finally {
      request = null
    }
  })()
  return request
}

export function userLevelForExperience(experience: number): number {
  const values = thresholds.value
  for (let level = values.length - 1; level > 0; level--) {
    if (experience >= (values[level] ?? 0)) return level
  }
  return 0
}
