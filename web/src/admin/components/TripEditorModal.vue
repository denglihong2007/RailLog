<script setup lang="ts">
import { reactive, ref } from 'vue'
import {
  AlertTriangle,
  Braces,
  Info,
  ListPlus,
  LoaderCircle,
  Plus,
  Route,
  Save,
  Trash2,
  X,
} from '@lucide/vue'
import { api, ApiError, type AdminTrip, type AdminTripInput } from '../api'
import { dateInputValue, dateTimeInputValue } from '../format'
import { toast } from '../toast'

interface Segment {
  routeName: string
  fromStation: string
  toStation: string
  mileageKm: number
}

const props = defineProps<{
  userId: string
  trip: AdminTrip | null
}>()

const emit = defineEmits<{
  close: []
  saved: [trip: AdminTrip]
}>()

const form = reactive({
  trainNumber: '',
  travelDate: '',
  fromStation: '',
  toStation: '',
  departureTime: '',
  arrivalTime: '',
  mileageKm: 0,
  price: 0,
  rollingStock: '',
  companyName: '',
  seatType: '',
  seatNumber: '',
  groupName: '',
  notes: '',
  isRailTrip: true,
  isDeleted: false,
})

const segments = ref<Segment[]>([])
const routeJson = ref('[]')
const routeMode = ref<'segments' | 'json'>('segments')
const saving = ref(false)
const error = ref('')

const initial = props.trip
if (initial) {
  form.trainNumber = initial.trainNumber
  form.travelDate = dateInputValue(initial.travelDate)
  form.fromStation = initial.fromStation
  form.toStation = initial.toStation
  form.departureTime = dateTimeInputValue(initial.departureTime)
  form.arrivalTime = dateTimeInputValue(initial.arrivalTime)
  form.mileageKm = initial.mileageKm
  form.price = initial.price
  form.rollingStock = initial.rollingStock ?? ''
  form.companyName = initial.companyName ?? ''
  form.seatType = initial.seatType ?? ''
  form.seatNumber = initial.seatNumber ?? ''
  form.groupName = initial.groupName ?? ''
  form.notes = initial.notes ?? ''
  form.isRailTrip = initial.isRailTrip
  form.isDeleted = initial.deletedAt !== null
}

const parsed = parseSegments(initial?.viaRoutes ?? '[]')
routeJson.value = initial?.viaRoutes ?? '[]'
if (parsed !== null) {
  segments.value = parsed
  routeMode.value = 'segments'
} else {
  routeMode.value = 'json'
}

function parseSegments(raw: string): Segment[] | null {
  try {
    const value: unknown = JSON.parse(raw || '[]')
    if (!Array.isArray(value)) return null
    return value.map((item) => {
      const record = (item ?? {}) as Record<string, unknown>
      return {
        routeName: typeof record.routeName === 'string' ? record.routeName : '',
        fromStation: typeof record.fromStation === 'string' ? record.fromStation : '',
        toStation: typeof record.toStation === 'string' ? record.toStation : '',
        mileageKm: typeof record.mileageKm === 'number' ? record.mileageKm : 0,
      }
    })
  } catch {
    return null
  }
}

function nullable(value: string): string | null {
  const trimmed = value.trim()
  return trimmed.length > 0 ? trimmed : null
}

/** 乘车日期在服务端通常带有时分，编辑时保留原时分以免改变排序。 */
function travelTimeSuffix(): string {
  const original = /T(\d{2}:\d{2}:\d{2})/.exec(props.trip?.travelDate ?? '')
  if (original?.[1]) return original[1]
  const departure = form.departureTime.slice(11)
  return departure ? `${departure}:00` : '00:00:00'
}

function addSegment(): void {
  const last = segments.value[segments.value.length - 1]
  segments.value.push({
    routeName: '',
    fromStation: last?.toStation || form.fromStation,
    toStation: form.toStation,
    mileageKm: 0,
  })
}

function removeSegment(index: number): void {
  segments.value.splice(index, 1)
}

function switchMode(mode: 'segments' | 'json'): void {
  if (mode === routeMode.value) return
  if (mode === 'json') {
    routeJson.value = JSON.stringify(segments.value, null, 2)
    routeMode.value = 'json'
    return
  }
  const next = parseSegments(routeJson.value)
  if (next === null) {
    toast('当前 JSON 不是数组，无法切换到分段编辑', 'error')
    return
  }
  segments.value = next
  routeMode.value = 'segments'
}

function validate(): string {
  if (!form.trainNumber.trim()) return '请填写车次'
  if (!form.travelDate) return '请选择乘车日期'
  if (!form.fromStation.trim()) return '请填写出发站'
  if (!form.toStation.trim()) return '请填写到达站'
  if (!Number.isFinite(Number(form.mileageKm)) || Number(form.mileageKm) < 0) return '里程必须为非负数'
  if (!Number.isFinite(Number(form.price)) || Number(form.price) < 0) return '票价必须为非负数'
  if (routeMode.value === 'json' && parseSegments(routeJson.value) === null) {
    return '经由线路必须是 JSON 数组'
  }
  return ''
}

function buildInput(): AdminTripInput {
  const routes = routeMode.value === 'json'
    ? (routeJson.value.trim() || '[]')
    : JSON.stringify(segments.value.map((segment) => ({
        routeName: segment.routeName.trim(),
        fromStation: segment.fromStation.trim(),
        toStation: segment.toStation.trim(),
        mileageKm: Number(segment.mileageKm) || 0,
      })))
  const departure = form.departureTime ? `${form.departureTime}:00` : null
  const arrival = form.arrivalTime ? `${form.arrivalTime}:00` : null
  return {
    trainNumber: form.trainNumber.trim(),
    travelDate: `${form.travelDate}T${travelTimeSuffix()}`,
    rollingStock: nullable(form.rollingStock),
    companyName: nullable(form.companyName),
    fromStation: form.fromStation.trim(),
    toStation: form.toStation.trim(),
    departureTime: departure,
    arrivalTime: arrival,
    mileageKm: Number(form.mileageKm) || 0,
    viaRoutes: routes,
    seatType: nullable(form.seatType),
    seatNumber: nullable(form.seatNumber),
    price: Number(form.price) || 0,
    notes: nullable(form.notes),
    groupName: nullable(form.groupName),
    isRailTrip: form.isRailTrip,
    isDeleted: form.isDeleted,
  }
}

async function save(): Promise<void> {
  if (saving.value) return
  const problem = validate()
  if (problem) {
    error.value = problem
    return
  }
  saving.value = true
  error.value = ''
  try {
    const input = buildInput()
    const result = props.trip
      ? await api.updateTrip(props.trip.ticketId, input)
      : await api.createTrip(props.userId, input)
    toast(props.trip ? '行程已保存，将在用户下次同步时送达' : '行程已新增，将在用户下次同步时送达')
    emit('saved', result)
  } catch (exception) {
    error.value = exception instanceof ApiError ? exception.message : '保存失败'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <Teleport to="body">
    <div class="modal-backdrop" @click.self="!saving && emit('close')">
      <div class="modal wide" role="dialog" aria-modal="true" aria-labelledby="trip-editor-title">
        <header class="modal-head">
          <div>
            <h2 id="trip-editor-title">{{ trip ? '编辑行程' : '新增行程' }}</h2>
            <p v-if="trip">行程 ID {{ trip.ticketId }} · 同步版本 {{ trip.syncVersion }}</p>
            <p v-else>为用户补录一条行程记录</p>
          </div>
          <button type="button" class="icon-button" aria-label="关闭" :disabled="saving" @click="emit('close')">
            <X :size="19" />
          </button>
        </header>

        <div class="modal-body">
          <p class="info-note compact">
            <Info :size="16" />
            保存会自增服务端同步版本；该用户下次同步时会收到这条修改或删除记录。
          </p>

          <section class="form-section">
            <h3>基本信息</h3>
            <div class="field-grid">
              <label class="field">
                <span class="field-label">车次 <em>*</em></span>
                <input v-model="form.trainNumber" maxlength="40" placeholder="例如 G1" />
              </label>
              <label class="field">
                <span class="field-label">乘车日期 <em>*</em></span>
                <input v-model="form.travelDate" type="date" />
              </label>
              <label class="field">
                <span class="field-label">出发站 <em>*</em></span>
                <input v-model="form.fromStation" maxlength="100" placeholder="北京南" />
              </label>
              <label class="field">
                <span class="field-label">到达站 <em>*</em></span>
                <input v-model="form.toStation" maxlength="100" placeholder="上海虹桥" />
              </label>
              <label class="field">
                <span class="field-label">出发时间</span>
                <input v-model="form.departureTime" type="datetime-local" />
              </label>
              <label class="field">
                <span class="field-label">到达时间</span>
                <input v-model="form.arrivalTime" type="datetime-local" />
              </label>
            </div>
          </section>

          <section class="form-section">
            <h3>行程数据</h3>
            <div class="field-grid">
              <label class="field">
                <span class="field-label">里程（km）</span>
                <input v-model.number="form.mileageKm" type="number" min="0" max="100000" step="0.1" />
              </label>
              <label class="field">
                <span class="field-label">票价（元）</span>
                <input v-model.number="form.price" type="number" min="0" max="1000000" step="0.01" />
              </label>
              <label class="field">
                <span class="field-label">车型 / 编组</span>
                <input v-model="form.rollingStock" maxlength="100" placeholder="例如 CR400AF-2011" />
              </label>
              <label class="field">
                <span class="field-label">值乘公司</span>
                <input v-model="form.companyName" maxlength="100" placeholder="例如 上海局" />
              </label>
              <label class="field">
                <span class="field-label">席位类型</span>
                <input v-model="form.seatType" maxlength="50" placeholder="例如 二等座" />
              </label>
              <label class="field">
                <span class="field-label">席别号</span>
                <input v-model="form.seatNumber" maxlength="50" placeholder="例如 12车 08F" />
              </label>
              <label class="field">
                <span class="field-label">分组</span>
                <input v-model="form.groupName" maxlength="100" placeholder="例如 2025 春运" />
              </label>
              <label class="switch-row inline-switch">
                <span>
                  <strong>计入铁路行程</strong>
                  <small>关闭后不计入里程与排行榜</small>
                </span>
                <input v-model="form.isRailTrip" type="checkbox" class="switch" />
              </label>
            </div>
          </section>

          <section class="form-section">
            <div class="section-head">
              <div>
                <h3>经由线路</h3>
                <p>分段描述行程经过的线路；里程为 0 表示未知。</p>
              </div>
              <div class="segment-toolbar">
                <button
                  type="button"
                  :class="['button', 'ghost', 'small', { selected: routeMode === 'segments' }]"
                  @click="switchMode('segments')"
                >
                  <ListPlus :size="15" /> 分段编辑
                </button>
                <button
                  type="button"
                  :class="['button', 'ghost', 'small', { selected: routeMode === 'json' }]"
                  @click="switchMode('json')"
                >
                  <Braces :size="15" /> JSON
                </button>
              </div>
            </div>

            <div v-if="routeMode === 'segments'" class="segments">
              <div v-if="segments.length === 0" class="segment-empty">
                <Route :size="20" />
                <span>还没有经由线路分段</span>
              </div>
              <div v-for="(segment, index) in segments" :key="index" class="segment-row">
                <span class="segment-index">{{ index + 1 }}</span>
                <input v-model="segment.routeName" placeholder="线路名，如 京沪高速线" />
                <input v-model="segment.fromStation" placeholder="始发站" />
                <input v-model="segment.toStation" placeholder="终到站" />
                <input v-model.number="segment.mileageKm" type="number" min="0" step="0.1" placeholder="km" />
                <button type="button" class="icon-button danger" aria-label="删除分段" @click="removeSegment(index)">
                  <Trash2 :size="15" />
                </button>
              </div>
              <button type="button" class="button ghost small add-segment" @click="addSegment">
                <Plus :size="15" /> 添加分段
              </button>
            </div>

            <label v-else class="field">
              <span class="field-label">经由线路 JSON</span>
              <textarea v-model="routeJson" rows="8" spellcheck="false" class="code-input" />
              <span class="field-hint">必须是数组，元素包含 routeName / fromStation / toStation / mileageKm</span>
            </label>
          </section>

          <section class="form-section">
            <h3>备注</h3>
            <label class="field">
              <textarea v-model="form.notes" rows="3" maxlength="2000" placeholder="可选" />
            </label>
          </section>

          <section v-if="trip" class="form-section danger-zone">
            <label class="switch-row">
              <span>
                <strong>标记为已删除</strong>
                <small>软删除，用户同步时会在客户端移除该行程；暂时保留数据以便恢复</small>
              </span>
              <input v-model="form.isDeleted" type="checkbox" class="switch" />
            </label>
          </section>

          <p v-if="error" class="form-error" role="alert">
            <AlertTriangle :size="16" /> {{ error }}
          </p>
        </div>

        <footer class="modal-foot">
          <button type="button" class="button ghost" :disabled="saving" @click="emit('close')">取消</button>
          <button type="button" class="button primary" :disabled="saving" @click="save">
            <LoaderCircle v-if="saving" :size="17" class="spin" />
            <Save v-else :size="17" />
            {{ trip ? '保存修改' : '创建行程' }}
          </button>
        </footer>
      </div>
    </div>
  </Teleport>
</template>
