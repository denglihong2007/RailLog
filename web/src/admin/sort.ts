/**
 * 后台表格排序的共用约定。
 *
 * 分页由服务端完成，所以分页表格的排序键直接传给接口（见 `SortState` 的
 * `key` 与 `direction`）；只有一次性取全量的表格才在本地调用 `sortRows`。
 * 两处的方向语义保持一致：同列再次点击切换方向，空值永远排在最后。
 */

export type SortDirection = 'asc' | 'desc'

export interface SortState {
  key: string
  direction: SortDirection
}

export type SortValue = string | number | null | undefined

/** 点击表头时的下一个状态：换列用该列的初始方向，同列则翻转方向。 */
export function nextSort(
  current: SortState | null,
  key: string,
  initial: SortDirection = 'asc',
): SortState {
  if (!current || current.key !== key) return { key, direction: initial }
  return { key, direction: current.direction === 'asc' ? 'desc' : 'asc' }
}

function isEmpty(value: SortValue): boolean {
  return value === null || value === undefined || value === ''
}

function compareValues(left: Exclude<SortValue, null | undefined>, right: Exclude<SortValue, null | undefined>): number {
  if (typeof left === 'number' && typeof right === 'number') return left - right
  return String(left).localeCompare(String(right), 'zh-CN', { numeric: true })
}

/** 本地排序；未指定排序状态时保留原顺序，空值无论升降序都排在最后。 */
export function sortRows<T>(
  rows: readonly T[],
  state: SortState | null,
  getters: Record<string, (row: T) => SortValue>,
): T[] {
  if (!state) return [...rows]
  const getter = getters[state.key]
  if (!getter) return [...rows]
  const factor = state.direction === 'asc' ? 1 : -1
  return [...rows].sort((left, right) => {
    const a = getter(left)
    const b = getter(right)
    const aEmpty = isEmpty(a)
    const bEmpty = isEmpty(b)
    if (aEmpty || bEmpty) {
      if (aEmpty && bEmpty) return 0
      return aEmpty ? 1 : -1
    }
    return compareValues(a as string | number, b as string | number) * factor
  })
}
