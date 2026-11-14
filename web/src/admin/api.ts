import type { SortState } from './sort'

const API_BASE = (import.meta.env.VITE_API_URL ?? '').replace(/\/$/, '')
const TOKEN_KEY = 'raillog.admin.token'
const NAME_KEY = 'raillog.admin.name'

/** 后台所有分页列表统一每页 30 条。 */
export const PAGE_SIZE = 30

/**
 * 分页列表的排序参数。排序键由服务端白名单校验，未知键会退回默认排序，
 * 所以这里只需要原样透传，不必在前端再维护一份列名表。
 */
function withSort(params: URLSearchParams, sort: SortState | null): URLSearchParams {
  if (sort) {
    params.set('sort', sort.key)
    params.set('order', sort.direction)
  }
  return params
}

export class ApiError extends Error {
  status: number

  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

export interface AdminSession {
  token: string
  expiresAt: string
  userId: string
  displayName: string
}

export interface AdminAnnouncement {
  id: string
  text: string
  weight: number
  isActive: boolean
  sortOrder: number
  createdAt: string
  updatedAt: string
}

export interface AnnouncementInput {
  id?: string | null
  text: string
  weight: number
  isActive: boolean
  sortOrder: number
}

export interface AdminUserSummary {
  id: string
  email: string
  displayName: string
  avatarUrl: string | null
  createdAt: string
  tripCount: number
  deletedTripCount: number
  achievementExperience: number
  level: number
  bio?: string | null
  showEmailOnProfile?: boolean
}

export interface AdminUserUpdateInput {
  displayName: string
  email: string
  avatarUrl: string | null
  bio: string | null
  showEmailOnProfile: boolean
}

export interface AdminUserPage {
  items: AdminUserSummary[]
  total: number
}

export interface AdminTrip {
  ticketId: number
  userId: string
  clientId: string
  createdAt: string
  trainNumber: string
  travelDate: string
  rollingStock: string | null
  companyName: string | null
  fromStation: string
  toStation: string
  departureTime: string | null
  arrivalTime: string | null
  mileageKm: number
  viaRoutes: string
  seatType: string | null
  seatNumber: string | null
  price: number
  notes: string | null
  groupName: string | null
  isRailTrip: boolean
  updatedAt: string
  deletedAt: string | null
  syncVersion: number
}

export interface AdminTripInput {
  trainNumber: string
  travelDate: string
  rollingStock: string | null
  companyName: string | null
  fromStation: string
  toStation: string
  departureTime: string | null
  arrivalTime: string | null
  mileageKm: number
  viaRoutes: string
  seatType: string | null
  seatNumber: string | null
  price: number
  notes: string | null
  groupName: string | null
  isRailTrip: boolean
  isDeleted: boolean
}

export interface PublicUser {
  id: string
  displayName: string
  avatarUrl: string | null
  bio: string | null
  email: string | null
  achievementExperience: number
}

export interface PublicTripSummary {
  ticketId: number
  createdAt: string
  trainNumber: string
  fromStation: string
  toStation: string
  departureTime: string | null
  arrivalTime: string | null
  mileageKm: number
  seatType: string | null
  seatNumber: string | null
  price: number
  isRailTrip: boolean
}

export interface UserRankingEntry {
  rank: number
  user: PublicUser
  value: number
}

export interface TripRankingEntry {
  rank: number
  user: PublicUser
  trip: PublicTripSummary
  value: number
}

export interface ElementRankingEntry {
  rank: number
  name: string
  value: number
}

export interface UserLeaderboards {
  totalSpending: UserRankingEntry[]
  tripCount: UserRankingEntry[]
  durationSeconds: UserRankingEntry[]
  mileageKm: UserRankingEntry[]
  achievementExperience: UserRankingEntry[]
}

export interface TripLeaderboards {
  singleSpending: TripRankingEntry[]
  mileageKm: TripRankingEntry[]
  durationSeconds: TripRankingEntry[]
  bestValueYuanPerKm: TripRankingEntry[]
  luxuryYuanPerKm: TripRankingEntry[]
  slowestAverageSpeedKmh: TripRankingEntry[]
  fastestAverageSpeedKmh: TripRankingEntry[]
}

export interface ElementLeaderboards {
  stations: ElementRankingEntry[]
  routes: ElementRankingEntry[]
  trains: ElementRankingEntry[]
  rollingStocks: ElementRankingEntry[]
  companies: ElementRankingEntry[]
}

export interface SitePeriodStatistics {
  tripCount: number
  mileageKm: number
  durationSeconds: number
  spending: number
}

export interface SiteStatistics {
  total: number
  thisYear: number
  thisMonth: number
  thisWeek: number
  totalMetrics: SitePeriodStatistics
  thisYearMetrics: SitePeriodStatistics
  thisMonthMetrics: SitePeriodStatistics
  thisWeekMetrics: SitePeriodStatistics
}

export interface StatisticsResponse {
  site: SiteStatistics
  users: UserLeaderboards
  trips: TripLeaderboards
  elements: ElementLeaderboards
}

export interface AdminReviewTrip {
  ticketId: number
  trainNumber: string
  travelDate: string
  fromStation: string
  toStation: string
  deletedAt: string | null
}

export interface AdminReview {
  id: number
  entityType: string
  entityKey: string
  reviewType: string
  userId: string
  displayName: string
  email: string | null
  avatarUrl: string | null
  rating: number
  comment: string
  tripId: number | null
  secondTripId: number | null
  routeFromStation: string | null
  routeToStation: string | null
  dish: string | null
  price: number | null
  createdAt: string
  reactionCount: number
  trip: AdminReviewTrip | null
}

export interface AdminReviewPage {
  items: AdminReview[]
  total: number
}

export interface AdminReviewReaction {
  reviewId: number
  userId: string
  displayName: string
  email: string | null
  avatarUrl: string | null
  emoji: string
  createdAt: string
}

export interface AdminReaction {
  reviewId: number
  entityType: string
  entityKey: string
  reviewType: string
  reviewRating: number
  reviewComment: string
  reviewCreatedAt: string
  reviewAuthorId: string
  reviewAuthorName: string
  reviewAuthorEmail: string | null
  userId: string
  displayName: string
  email: string | null
  avatarUrl: string | null
  emoji: string
  createdAt: string
}

export interface AdminReactionPage {
  total: number
  items: AdminReaction[]
}

export interface AdminReviewUser {
  userId: string
  displayName: string
  email: string | null
  avatarUrl: string | null
  reviewCount: number
  receivedReactionCount: number
  givenReactionCount: number
  averageRating: number | null
  latestReviewAt: string | null
}

export interface AdminReviewUserPage {
  total: number
  items: AdminReviewUser[]
}

export interface AdminOverviewCounts {
  users: number
  newUsers: number
  activeTrips: number
  newTrips: number
  deletedTrips: number
  reviews: number
  newReviews: number
  activeAnnouncements: number
}

export interface AdminFlaggedTrip {
  ticketId: number
  userId: string
  displayName: string
  trainNumber: string
  fromStation: string
  toStation: string
  travelDate: string
  mileageKm: number
  speedKmh: number | null
}

export interface AdminRecentReview {
  id: number
  userId: string
  displayName: string
  entityType: string
  entityKey: string
  reviewType: string
  rating: number
  comment: string
  createdAt: string
}

export interface AdminRecentUser {
  id: string
  displayName: string
  email: string | null
  createdAt: string
  tripCount: number
}

export interface AdminDuplicateTrip {
  ticketId: number
  fromStation: string
  toStation: string
  departureTime: string | null
  arrivalTime: string | null
  mileageKm: number
  price: number
  rollingStock: string | null
  seatType: string | null
  seatNumber: string | null
  createdAt: string
}

export interface AdminDuplicateGroup {
  userId: string
  displayName: string
  trainNumber: string
  travelDate: string
  fromStation: string
  toStation: string
  mileageKm: number
  price: number
  trips: AdminDuplicateTrip[]
}

export interface AdminDuplicateGroupPage {
  totalGroups: number
  totalTrips: number
  items: AdminDuplicateGroup[]
}

export interface AdminDuplicateResolveResult {
  groups: number
  deletedTrips: number
  affectedUsers: number
}

export interface AdminOverview {
  counts: AdminOverviewCounts
  overspeedTripCount: number
  overspeedTrips: AdminFlaggedTrip[]
  duplicateTripCount: number
  duplicateGroupCount: number
  duplicateGroups: AdminDuplicateGroup[]
  recentReviews: AdminRecentReview[]
  recentUsers: AdminRecentUser[]
}

export interface AdminAchievement {
  id: string
  category: string
  icon: string
  title: string
  description: string
  experience: number
  hidden: boolean
  unlockedUserCount: number
  unlockedPercent: number
  latestTriggerAt: string | null
}

export interface AdminAchievementOverview {
  totalUsers: number
  totalUnlocks: number
  achievements: AdminAchievement[]
}

export interface AdminAchievementUnlock {
  userId: string
  displayName: string
  email: string | null
  ticketId: number
  trainNumber: string
  fromStation: string
  toStation: string
  triggeredAt: string
  deletedAt: string | null
}

export interface AdminAchievementUnlockPage {
  achievementId: string
  total: number
  items: AdminAchievementUnlock[]
}

export interface AdminTicketPasswordStatus {
  configured: boolean
  source: 'database' | 'configuration' | 'none'
  updatedAt: string | null
}

export interface AdminPdfRequest {
  id: string
  createdAt: string
  expiresAt: string
  expired: boolean
  style: string
  passenger: string
  maskedId: string
  tripIds: number[]
}

export interface AdminPdfRequestPage {
  total: number
  activeCount: number
  items: AdminPdfRequest[]
}

export interface AdminUserLevelStat {
  level: number
  minimumExperience: number
  userCount: number
  percent: number
}

export interface AdminAchievementRecomputeStatus {
  running: boolean
  pending: boolean
  lastStartedAt: string | null
  lastFinishedAt: string | null
  lastError: string | null
}

export interface AdminUserLevelConfig {
  thresholds: number[]
  defaults: number[]
  updatedAt: string | null
  totalUsers: number
  levels: AdminUserLevelStat[]
  recompute: AdminAchievementRecomputeStatus
}

export interface AdminAuditEntry {
  id: number
  adminUserId: string
  adminName: string
  action: string
  target: string | null
  detail: string | null
  createdAt: string
}

export interface AdminAuditPage {
  total: number
  items: AdminAuditEntry[]
}

export interface AdminBackupFile {
  name: string
  sizeBytes: number
  createdAt: string
}

export interface AdminBackupOverview {
  enabled: boolean
  directory: string
  intervalDays: number
  keepCount: number
  items: AdminBackupFile[]
  encrypted: boolean
}

export interface AdminTimetableVersion {
  version: string
  sizeBytes: number
  modifiedAt: string
}

export interface AdminTimetableSyncStatus {
  enabled: boolean
  running: boolean
  hasGitHubToken: boolean
  owner: string
  repository: string
  assetName: string
  hour: number
  minute: number
  timeZone: string
  directory: string
  totalVersions: number
  totalSizeBytes: number
  newestVersion: string | null
  oldestVersion: string | null
  lastStartedAt: string | null
  lastFinishedAt: string | null
  nextRunAt: string | null
  lastError: string | null
  lastSyncedCount: number
  lastMissingCount: number
  lastTrigger: string | null
  versions: AdminTimetableVersion[]
}

export interface AdminTimetableUpstream {
  repository: string
  localVersions: number
  upstreamVersions: number
  missingVersions: string[]
  error: string | null
}

export function readToken(): string {
  try {
    return localStorage.getItem(TOKEN_KEY) ?? ''
  } catch {
    return ''
  }
}

export function storeToken(token: string): void {
  try {
    localStorage.setItem(TOKEN_KEY, token)
  } catch {
    // 隐私模式下写不进去也不影响当前会话。
  }
}

export function readAdminName(): string {
  try {
    return localStorage.getItem(NAME_KEY) ?? ''
  } catch {
    return ''
  }
}

export function storeAdminName(name: string): void {
  try {
    localStorage.setItem(NAME_KEY, name)
  } catch {
    // 隐私模式下写不进去也不影响当前会话。
  }
}

export function clearToken(): void {
  try {
    localStorage.removeItem(TOKEN_KEY)
    localStorage.removeItem(NAME_KEY)
  } catch {
    // ignore
  }
}

async function request<T>(path: string, init: RequestInit = {}, authorized = true): Promise<T> {
  const headers = new Headers(init.headers)
  if (init.body !== undefined) headers.set('Content-Type', 'application/json')
  if (authorized) {
    const token = readToken()
    if (token) headers.set('Authorization', `Bearer ${token}`)
  }
  let response: Response
  try {
    response = await fetch(`${API_BASE}${path}`, { ...init, headers })
  } catch {
    throw new ApiError(0, '无法连接服务器，请检查网络')
  }
  if (response.status === 401 && authorized) {
    clearToken()
    window.dispatchEvent(new CustomEvent('admin:unauthorized'))
  }
  if (!response.ok) throw new ApiError(response.status, await readErrorMessage(response))
  if (response.status === 204) return undefined as T
  return (await response.json()) as T
}

async function readErrorMessage(response: Response): Promise<string> {
  let message = `请求失败（HTTP ${response.status}）`
  try {
    const body = (await response.json()) as {
      message?: string
      title?: string
      errors?: Record<string, string[]>
    }
    if (body.message) message = body.message
    else if (body.errors) {
      const first = Object.values(body.errors).flat().find(Boolean)
      if (first) message = first
    } else if (body.title) message = body.title
  } catch {
    // 非 JSON 错误响应，保留默认文案。
  }
  return message
}

/**
 * 带管理员令牌的文件下载。浏览器原生 <a download> 不会带上 Authorization，
 * 所以先 fetch 成 Blob，再用临时链接触发保存。
 */
async function downloadFile(path: string, fallbackName: string): Promise<void> {
  const headers = new Headers()
  const token = readToken()
  if (token) headers.set('Authorization', `Bearer ${token}`)

  let response: Response
  try {
    response = await fetch(`${API_BASE}${path}`, { headers })
  } catch {
    throw new ApiError(0, '无法连接服务器，请检查网络')
  }
  if (response.status === 401) {
    clearToken()
    window.dispatchEvent(new CustomEvent('admin:unauthorized'))
  }
  if (!response.ok) throw new ApiError(response.status, await readErrorMessage(response))

  const blob = await response.blob()
  const disposition = response.headers.get('Content-Disposition') ?? ''
  const match = /filename\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(disposition)
  const name = match?.[1] ? decodeURIComponent(match[1]) : fallbackName

  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = name
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
  window.setTimeout(() => URL.revokeObjectURL(url), 1000)
}

export const api = {
  login(email: string, password: string) {
    return request<AdminSession>(
      '/api/admin/login',
      { method: 'POST', body: JSON.stringify({ email, password }) },
      false,
    )
  },
  logout() {
    return request<void>('/api/admin/logout', { method: 'POST' })
  },
  announcements() {
    return request<AdminAnnouncement[]>('/api/admin/announcements')
  },
  saveAnnouncement(input: AnnouncementInput) {
    return request<AdminAnnouncement>('/api/admin/announcements', {
      method: 'POST',
      body: JSON.stringify(input),
    })
  },
  deleteAnnouncement(id: string) {
    return request<void>(`/api/admin/announcements/${encodeURIComponent(id)}`, {
      method: 'DELETE',
    })
  },
  users(
    query: string,
    level: number | null,
    offset: number,
    limit: number,
    sort: SortState | null = null,
  ) {
    const params = withSort(
      new URLSearchParams({
        query,
        offset: String(offset),
        limit: String(limit),
      }),
      sort,
    )
    if (level !== null) params.set('level', String(level))
    return request<AdminUserPage>(`/api/admin/users?${params}`)
  },
  user(userId: string) {
    return request<AdminUserSummary>(`/api/admin/users/${encodeURIComponent(userId)}`)
  },
  updateUser(userId: string, input: AdminUserUpdateInput) {
    return request<AdminUserSummary>(`/api/admin/users/${encodeURIComponent(userId)}`, {
      method: 'PUT',
      body: JSON.stringify(input),
    })
  },
  deleteUser(userId: string) {
    return request<void>(`/api/admin/users/${encodeURIComponent(userId)}`, {
      method: 'DELETE',
    })
  },
  trips(userId: string, includeDeleted: boolean) {
    const params = new URLSearchParams({ includeDeleted: String(includeDeleted) })
    return request<AdminTrip[]>(
      `/api/admin/users/${encodeURIComponent(userId)}/trips?${params}`,
    )
  },
  createTrip(userId: string, input: AdminTripInput) {
    return request<AdminTrip>(`/api/admin/users/${encodeURIComponent(userId)}/trips`, {
      method: 'POST',
      body: JSON.stringify(input),
    })
  },
  updateTrip(ticketId: number, input: AdminTripInput) {
    return request<AdminTrip>(`/api/admin/trips/${ticketId}`, {
      method: 'PUT',
      body: JSON.stringify(input),
    })
  },
  deleteTrip(ticketId: number) {
    return request<void>(`/api/admin/trips/${ticketId}`, { method: 'DELETE' })
  },
  overview() {
    return request<AdminOverview>('/api/admin/overview')
  },
  trip(ticketId: number) {
    return request<AdminTrip>(`/api/admin/trips/${ticketId}`)
  },
  duplicates(offset: number, limit: number) {
    const params = new URLSearchParams({
      offset: String(offset),
      limit: String(limit),
    })
    return request<AdminDuplicateGroupPage>(`/api/admin/duplicates?${params}`)
  },
  resolveDuplicates() {
    return request<AdminDuplicateResolveResult>('/api/admin/duplicates/resolve', {
      method: 'POST',
    })
  },
  ticketPasswordStatus() {
    return request<AdminTicketPasswordStatus>('/api/admin/ticket-password')
  },
  setTicketPassword(password: string) {
    return request<void>('/api/admin/ticket-password', {
      method: 'PUT',
      body: JSON.stringify({ password }),
    })
  },
  clearTicketPassword() {
    return request<void>('/api/admin/ticket-password', { method: 'DELETE' })
  },
  leaderboards() {
    return request<StatisticsResponse>('/api/admin/leaderboards')
  },
  reviews(filters: {
    query: string
    entityType: string
    reviewType: string
    userId?: string
    offset: number
    limit: number
    sort?: SortState | null
  }) {
    const params = withSort(
      new URLSearchParams({
        query: filters.query,
        entityType: filters.entityType,
        reviewType: filters.reviewType,
        userId: filters.userId ?? '',
        offset: String(filters.offset),
        limit: String(filters.limit),
      }),
      filters.sort ?? null,
    )
    return request<AdminReviewPage>(`/api/admin/reviews?${params}`)
  },
  deleteReview(id: number) {
    return request<void>(`/api/admin/reviews/${id}`, { method: 'DELETE' })
  },
  reviewReactions(reviewId: number) {
    return request<AdminReviewReaction[]>(`/api/admin/reviews/${reviewId}/reactions`)
  },
  deleteReviewReaction(reviewId: number, userId: string) {
    return request<void>(
      `/api/admin/reviews/${reviewId}/reactions/${encodeURIComponent(userId)}`,
      { method: 'DELETE' },
    )
  },
  reactions(filters: {
    query: string
    emoji: string
    entityType: string
    reactorId?: string
    authorId?: string
    offset: number
    limit: number
    sort?: SortState | null
  }) {
    const params = withSort(
      new URLSearchParams({
        query: filters.query,
        emoji: filters.emoji,
        entityType: filters.entityType,
        reactorId: filters.reactorId ?? '',
        authorId: filters.authorId ?? '',
        offset: String(filters.offset),
        limit: String(filters.limit),
      }),
      filters.sort ?? null,
    )
    return request<AdminReactionPage>(`/api/admin/reactions?${params}`)
  },
  reviewUsers(filters: {
    query: string
    offset: number
    limit: number
    sort?: SortState | null
  }) {
    const params = withSort(
      new URLSearchParams({
        query: filters.query,
        offset: String(filters.offset),
        limit: String(filters.limit),
      }),
      filters.sort ?? null,
    )
    return request<AdminReviewUserPage>(`/api/admin/review-users?${params}`)
  },
  achievements() {
    return request<AdminAchievementOverview>('/api/admin/achievements')
  },
  achievementUnlocks(achievementId: string, offset: number, limit: number) {
    const params = new URLSearchParams({
      offset: String(offset),
      limit: String(limit),
    })
    return request<AdminAchievementUnlockPage>(
      `/api/admin/achievements/${encodeURIComponent(achievementId)}/unlocks?${params}`,
    )
  },
  pdfRequests(query: string, offset: number, limit: number, sort: SortState | null = null) {
    const params = withSort(
      new URLSearchParams({
        query,
        offset: String(offset),
        limit: String(limit),
      }),
      sort,
    )
    return request<AdminPdfRequestPage>(`/api/admin/pdf-requests?${params}`)
  },
  deletePdfRequest(id: string) {
    return request<void>(`/api/admin/pdf-requests/${encodeURIComponent(id)}`, {
      method: 'DELETE',
    })
  },
  cleanupPdfRequests() {
    return request<{ removed: number }>('/api/admin/pdf-requests/cleanup', {
      method: 'POST',
    })
  },
  userLevels() {
    return request<AdminUserLevelConfig>('/api/admin/user-levels')
  },
  saveUserLevels(thresholds: number[]) {
    return request<AdminUserLevelConfig>('/api/admin/user-levels', {
      method: 'PUT',
      body: JSON.stringify({ thresholds }),
    })
  },
  backups() {
    return request<AdminBackupOverview>('/api/admin/backups')
  },
  downloadBackup() {
    return downloadFile('/api/admin/backups/download', 'raillog-backup.db')
  },
  downloadBackupFile(name: string) {
    return downloadFile(
      `/api/admin/backups/${encodeURIComponent(name)}/download`,
      name,
    )
  },
  deleteBackup(name: string) {
    return request<void>(`/api/admin/backups/${encodeURIComponent(name)}`, {
      method: 'DELETE',
    })
  },
  auditLogs(query: string, offset: number, limit: number, sort: SortState | null = null) {
    const params = withSort(
      new URLSearchParams({
        query,
        offset: String(offset),
        limit: String(limit),
      }),
      sort,
    )
    return request<AdminAuditPage>(`/api/admin/audit-logs?${params}`)
  },
  timetableSyncStatus() {
    return request<AdminTimetableSyncStatus>('/api/admin/timetable-sync')
  },
  runTimetableSync() {
    return request<{ message: string }>('/api/admin/timetable-sync/run', {
      method: 'POST',
    })
  },
  timetableUpstream() {
    return request<AdminTimetableUpstream>('/api/admin/timetable-sync/upstream')
  },
}
