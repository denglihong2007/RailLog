<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { BookOpen, Braces, Check, Clipboard, Code2, ExternalLink, ShieldCheck } from '@lucide/vue'

interface FieldDefinition {
  path: string
  type: string
  description: string
}

const timetableFields: FieldDefinition[] = [
  { path: 'trainNumber', type: 'string', description: '请求车次号去除首尾空白并转换为大写后的值，例如 "G1"。' },
  { path: 'year', type: 'integer', description: '本次查询使用的历史时刻表年份。' },
  { path: 'stops', type: 'array<object>', description: '按运行顺序排列的停站数组；没有匹配车次时为空数组。' },
  { path: 'stops[].station_name', type: 'string', description: '车站完整名称，不附加“站”字，例如 "北京南"。' },
  { path: 'stops[].station_no', type: 'string', description: '停站顺序号。为兼容历史数据以字符串返回，例如 "01"；不应按数值格式解析。' },
  { path: 'stops[].arrive_time', type: 'string', description: '计划到达时刻，通常为 24 小时制 HH:mm；始发站或原始数据缺失时为空字符串。' },
  { path: 'stops[].start_time', type: 'string', description: '计划出发时刻，通常为 24 小时制 HH:mm；终到站或原始数据缺失时为空字符串。' },
  { path: 'stops[].running_time', type: 'string', description: '预留的累计运行时间文本；当前历史数据返回空字符串。' },
  { path: 'stops[].arrive_day_str', type: 'string', description: '预留的到达日描述；当前历史数据返回空字符串。' },
  { path: 'stops[].arrive_day_diff', type: 'integer', description: '相对始发日的自然日偏移，0 表示当日，1 表示次日；最小值为 0。' },
  { path: 'stops[].mileage', type: 'number', description: '从车次起点累计至该站的里程，单位 km；缺失或无法解析时为 0。' },
]

const trainSearchFields: FieldDefinition[] = [
  { path: 'year', type: 'integer', description: '本次搜索使用的历史时刻表年份。' },
  { path: 'trains', type: 'array<object>', description: '匹配车次数组；无匹配结果时为空数组。' },
  { path: 'trains[].station_train_code', type: 'string', description: '用于展示和后续查询的车次号，例如 "G1"。' },
  { path: 'trains[].from_station', type: 'string', description: '车次始发站；两站间查询中为请求的起点站。' },
  { path: 'trains[].to_station', type: 'string', description: '车次终到站；两站间查询中为请求的终点站。' },
  { path: 'trains[].train_no', type: 'string', description: '车次查询标识。当前与 station_train_code 相同，调用方不应依赖两者永远相等。' },
]

const publicUserFields: FieldDefinition[] = [
  { path: 'id', type: 'string', description: '用户的稳定公开 ID；作为 /api/users/{userId} 的路径参数使用。' },
  { path: 'displayName', type: 'string', description: '用户公开显示名称。' },
  { path: 'avatarUrl', type: 'string | null', description: '头像的绝对或可访问 URL；未设置头像时为 null。' },
  { path: 'bio', type: 'string | null', description: '用户公开个人简介；未填写时为 null。' },
  { path: 'email', type: 'string | null', description: '电子邮箱地址。仅当用户主动开启公开邮箱时返回，否则为 null。' },
]

const publicTripFields: FieldDefinition[] = [
  { path: 'ticketId', type: 'integer', description: '行程的公开数字 ID，可用于 /api/trips/{ticketId}。' },
  { path: 'createdAt', type: 'string<date-time>', description: '行程记录创建时间，ISO 8601 日期时间字符串。' },
  { path: 'trainNumber', type: 'string', description: '车次或交通班次号；未记录时可能为空字符串。' },
  { path: 'rollingStock', type: 'string | null', description: '车型或车辆型号，例如 "CR400AF"；未记录时为 null。' },
  { path: 'companyName', type: 'string | null', description: '承运单位或担当单位名称；未记录时为 null。' },
  { path: 'fromStation', type: 'string', description: '行程起点站或起点地点名称。' },
  { path: 'toStation', type: 'string', description: '行程终点站或终点地点名称。' },
  { path: 'departureTime', type: 'string<date-time> | null', description: '实际记录的出发时间，ISO 8601 日期时间；未记录时为 null。' },
  { path: 'arrivalTime', type: 'string<date-time> | null', description: '实际记录的到达时间，ISO 8601 日期时间；未记录时为 null。' },
  { path: 'mileageKm', type: 'number', description: '本次行程里程，单位 km；未记录时通常为 0。' },
  { path: 'viaRoutes', type: 'string', description: '经由线路的 JSON 编码字符串。解码后通常为对象数组：routeName 是线路名，fromStation/toStation 是该段起终点，mileageKm 是该段公里数；无有效数据时可能为空字符串。' },
  { path: 'seatType', type: 'string | null', description: '席别，例如 "二等座"；未记录时为 null。' },
  { path: 'seatNumber', type: 'string | null', description: '座位或铺位文本，例如 "05车 12A"；未记录时为 null。' },
  { path: 'price', type: 'number', description: '票价或行程花费，单位人民币元；保留位数由原始记录决定。' },
  { path: 'notes', type: 'string | null', description: '用户公开备注；未填写时为 null。' },
  { path: 'isRailTrip', type: 'boolean', description: '是否为铁路行程；false 表示用户记录的其他交通行程。' },
]

const achievementFields: FieldDefinition[] = [
  { path: 'totalUserCount', type: 'integer', description: '计算成就解锁人数时采用的全站用户总数。' },
  { path: 'achievements', type: 'array<object>', description: '完整成就定义及该用户状态数组，包括未解锁成就。' },
  { path: 'achievements[].id', type: 'string', description: '成就稳定标识，例如 "midnightBoarding"。' },
  { path: 'achievements[].category', type: 'string', description: '成就分类：milestones、extremeChallenges、railwayCatalog、touring 或 funJourneys。' },
  { path: 'achievements[].icon', type: 'string', description: 'Material Icons 图标 key，例如 "nightlight_outlined"。' },
  { path: 'achievements[].title', type: 'string', description: '成就的中文标题。' },
  { path: 'achievements[].description', type: 'string', description: '成就解锁条件的文字说明。' },
  { path: 'achievements[].status', type: 'string', description: '该用户的状态："unlocked" 表示已解锁，"locked" 表示未解锁。' },
  { path: 'achievements[].triggerTripId', type: 'integer | null', description: '触发解锁的公开行程 ID；尚未解锁或没有对应行程时为 null。' },
  { path: 'achievements[].unlockedUserCount', type: 'integer', description: '全站已解锁该成就的用户数量。' },
  { path: 'achievements[].progressCurrent', type: 'number | null', description: '可量化成就的当前进度；不支持进度或已无进度信息时为 null。单位由成就条件决定。' },
  { path: 'achievements[].progressTarget', type: 'number | null', description: '可量化成就的目标值；不支持进度时为 null，与 progressCurrent 使用相同单位。' },
]

const props = defineProps<{ apiBase: string }>()
const productionBase = props.apiBase || 'https://api.raillog.top'
const copied = ref('')

onMounted(() => {
  document.title = '开放 API - RailLog 轨记'
})

async function copy(value: string, key: string): Promise<void> {
  await navigator.clipboard.writeText(value)
  copied.value = key
  window.setTimeout(() => {
    if (copied.value === key) copied.value = ''
  }, 1600)
}

function curl(path: string): string {
  return `curl "${productionBase}${path}"`
}
</script>

<template>
  <section class="api-page" aria-labelledby="api-title">
    <aside class="api-sidebar" aria-label="API 文档目录">
      <strong>开放 API</strong>
      <nav>
        <a href="#overview">概览</a>
        <a href="#compatibility">兼容性承诺</a>
        <a href="#timetable">铁路时刻表</a>
        <a href="#trip">行程详情</a>
        <a href="#user">用户信息</a>
        <a href="#errors">格式与错误</a>
      </nav>
    </aside>

    <article class="api-content">
      <header class="api-heading" id="overview">
        <p><BookOpen :size="18" /> 开发者文档</p>
        <h1 id="api-title">RailLog 开放 API</h1>
        <span>稳定版 v1 · 生效日期 2026-08-17</span>
        <p class="api-lead">面向铁路应用、个人工具与数据研究的公开只读接口。无需 API Key，支持服务端和浏览器跨域调用。</p>
      </header>

      <section class="quick-facts" aria-label="API 摘要">
        <div><Code2 :size="21" /><span>基地址</span><strong>{{ productionBase }}</strong></div>
        <div><ShieldCheck :size="21" /><span>认证</span><strong>无需认证</strong></div>
        <div><Braces :size="21" /><span>响应格式</span><strong>JSON · UTF-8</strong></div>
      </section>

      <section id="compatibility" class="doc-section">
        <p class="section-label">接口契约</p>
        <h2>兼容性承诺</h2>
        <p>本文列出的未版本化路径构成 RailLog 开放 API v1。RailLog 承诺在 v1 生命周期内维持现有 HTTP 方法、路径、必填参数、字段类型和既有字段语义。</p>
        <ul class="policy-list">
          <li><Check :size="17" /><span>新增响应字段、增加新的可选参数或新增端点属于向后兼容变更。调用方应忽略无法识别的字段。</span></li>
          <li><Check :size="17" /><span>不会在 v1 中删除字段、改变字段类型、收紧已有有效参数，或把公开端点改为必须认证。</span></li>
          <li><Check :size="17" /><span>确需破坏性变更时将发布新版本路径；v1 会提前至少 12 个月公告弃用，并在公告期内继续可用。</span></li>
          <li><Check :size="17" /><span>安全修复、滥用防护、数据纠错及服务不可用时返回的 4xx/5xx，不视为兼容性破坏。</span></li>
        </ul>
        <p class="callout">兼容性承诺针对接口结构与语义，不构成可用性 SLA，也不保证历史数据库中始终存在某一车次或用户记录。</p>
      </section>

      <section id="timetable" class="doc-section">
        <p class="section-label">Railway</p>
        <h2>铁路时刻表</h2>
        <p>历史铁路时刻表当前覆盖 2009 至 2026 年。车次号不区分大小写；车站名称需使用数据库中的完整站名。</p>

        <div class="endpoint" id="timetable-detail">
          <div class="endpoint-title"><span class="method">GET</span><code>/api/train-timetables</code></div>
          <p>返回指定年份、指定车次的完整停站序列。无匹配记录时返回空的 <code>stops</code> 数组。</p>
          <h3>查询参数</h3>
          <dl class="parameter-list">
            <div><dt><code>trainNumber</code><b>string · 必填</b></dt><dd>车次号，例如 <code>G1</code>。</dd></div>
            <div><dt><code>year</code><b>integer · 必填</b></dt><dd>时刻表年份，当前为 2009–2026。</dd></div>
          </dl>
          <div class="code-heading"><span>请求示例</span><button type="button" title="复制请求" @click="copy(curl('/api/train-timetables?trainNumber=G1&year=2026'), 'detail')"><Check v-if="copied === 'detail'" :size="16" /><Clipboard v-else :size="16" /></button></div>
          <pre><code>{{ curl('/api/train-timetables?trainNumber=G1&year=2026') }}</code></pre>
          <details open><summary>响应字段</summary><dl class="schema-list"><div v-for="field in timetableFields" :key="field.path"><dt><code>{{ field.path }}</code><b>{{ field.type }}</b></dt><dd>{{ field.description }}</dd></div></dl></details>
        </div>

        <div class="endpoint" id="timetable-search">
          <div class="endpoint-title"><span class="method">GET</span><code>/api/train-timetables/search</code></div>
          <p>按车次号前缀搜索车次，返回车次及始发、终到站。</p>
          <dl class="parameter-list"><div><dt><code>trainNumber</code><b>string · 必填</b></dt><dd>车次号前缀。</dd></div><div><dt><code>year</code><b>integer · 必填</b></dt><dd>时刻表年份。</dd></div></dl>
          <div class="code-heading"><span>请求示例</span><button type="button" title="复制请求" @click="copy(curl('/api/train-timetables/search?trainNumber=G&year=2026'), 'search')"><Check v-if="copied === 'search'" :size="16" /><Clipboard v-else :size="16" /></button></div>
          <pre><code>{{ curl('/api/train-timetables/search?trainNumber=G&year=2026') }}</code></pre>
          <details open><summary>响应字段</summary><dl class="schema-list"><div v-for="field in trainSearchFields" :key="field.path"><dt><code>{{ field.path }}</code><b>{{ field.type }}</b></dt><dd>{{ field.description }}</dd></div></dl></details>
        </div>

        <div class="endpoint" id="timetable-between">
          <div class="endpoint-title"><span class="method">GET</span><code>/api/train-timetables/between</code></div>
          <p>查询在指定年份按顺序经过起点站和终点站的车次，最多返回 100 条。</p>
          <dl class="parameter-list"><div><dt><code>fromStation</code><b>string · 必填</b></dt><dd>起点站完整名称。</dd></div><div><dt><code>toStation</code><b>string · 必填</b></dt><dd>终点站完整名称。</dd></div><div><dt><code>year</code><b>integer · 必填</b></dt><dd>时刻表年份。</dd></div></dl>
          <div class="code-heading"><span>请求示例</span><button type="button" title="复制请求" @click="copy(curl('/api/train-timetables/between?fromStation=北京南&toStation=上海虹桥&year=2026'), 'between')"><Check v-if="copied === 'between'" :size="16" /><Clipboard v-else :size="16" /></button></div>
          <pre><code>{{ curl('/api/train-timetables/between?fromStation=北京南&toStation=上海虹桥&year=2026') }}</code></pre>
          <details open><summary>响应字段</summary><dl class="schema-list"><div v-for="field in trainSearchFields" :key="field.path"><dt><code>{{ field.path }}</code><b>{{ field.type }}</b></dt><dd>{{ field.description }}</dd></div></dl></details>
        </div>

        <div class="endpoint" id="stations">
          <div class="endpoint-title"><span class="method">GET</span><code>/api/train-timetables/stations</code></div>
          <p>返回指定年份时刻表中的所有车站名称，按名称排序。</p>
          <dl class="parameter-list"><div><dt><code>year</code><b>integer · 必填</b></dt><dd>时刻表年份。</dd></div></dl>
          <div class="code-heading"><span>请求示例</span><button type="button" title="复制请求" @click="copy(curl('/api/train-timetables/stations?year=2026'), 'stations')"><Check v-if="copied === 'stations'" :size="16" /><Clipboard v-else :size="16" /></button></div>
          <pre><code>{{ curl('/api/train-timetables/stations?year=2026') }}</code></pre>
          <details open><summary>响应字段</summary><dl class="schema-list"><div><dt><code>响应正文</code><b>array&lt;string&gt;</b></dt><dd>车站完整名称组成的 JSON 数组，按名称升序排列且已去重；没有数据时为空数组。数组元素不会为 null。</dd></div></dl></details>
          <details><summary>响应示例</summary><pre><code>["上海", "上海南", "上海虹桥"]</code></pre></details>
        </div>
      </section>

      <section id="trip" class="doc-section">
        <p class="section-label">Trips</p><h2>公开行程详情</h2>
        <div class="endpoint">
          <div class="endpoint-title"><span class="method">GET</span><code>/api/trips/{ticketId}</code></div>
          <p>按正整数行程 ID 返回公开用户资料和单条行程；记录不存在时返回 <code>404</code>。</p>
          <dl class="parameter-list"><div><dt><code>ticketId</code><b>integer · 必填</b></dt><dd>行程的公开数字 ID。</dd></div></dl>
          <div class="code-heading"><span>请求示例</span><button type="button" title="复制请求" @click="copy(curl('/api/trips/123'), 'trip')"><Check v-if="copied === 'trip'" :size="16" /><Clipboard v-else :size="16" /></button></div>
          <pre><code>{{ curl('/api/trips/123') }}</code></pre>
          <details open><summary>响应字段</summary><h3>根对象</h3><dl class="schema-list"><div><dt><code>user</code><b>object</b></dt><dd>该行程所属用户的公开资料。</dd></div><div><dt><code>trip</code><b>object</b></dt><dd>指定 ID 对应的公开行程详情。</dd></div></dl><h3>user 对象</h3><dl class="schema-list"><div v-for="field in publicUserFields" :key="field.path"><dt><code>user.{{ field.path }}</code><b>{{ field.type }}</b></dt><dd>{{ field.description }}</dd></div></dl><h3>trip 对象</h3><dl class="schema-list"><div v-for="field in publicTripFields" :key="field.path"><dt><code>trip.{{ field.path }}</code><b>{{ field.type }}</b></dt><dd>{{ field.description }}</dd></div></dl></details>
        </div>
      </section>

      <section id="user" class="doc-section">
        <p class="section-label">Users</p><h2>公开用户信息</h2>
        <div class="endpoint">
          <div class="endpoint-title"><span class="method">GET</span><code>/api/users/{userId}</code></div>
          <p>返回用户公开资料、全部未删除行程及成就信息；用户不存在时返回 <code>404</code>。</p>
          <dl class="parameter-list"><div><dt><code>userId</code><b>string · 必填</b></dt><dd>用户的完整公开 ID，路径中需进行 URL 编码。</dd></div></dl>
          <div class="code-heading"><span>请求示例</span><button type="button" title="复制请求" @click="copy(curl('/api/users/USER_ID'), 'user')"><Check v-if="copied === 'user'" :size="16" /><Clipboard v-else :size="16" /></button></div>
          <pre><code>{{ curl('/api/users/USER_ID') }}</code></pre>
          <details open><summary>响应字段</summary><h3>根对象</h3><dl class="schema-list"><div><dt><code>user</code><b>object</b></dt><dd>被查询用户的公开资料。</dd></div><div><dt><code>trips</code><b>array&lt;object&gt;</b></dt><dd>该用户全部未删除的公开行程，按出发时间降序、行程 ID 降序排列；没有记录时为空数组。</dd></div><div><dt><code>achievements</code><b>object</b></dt><dd>该用户完整的成就状态和全站解锁统计。</dd></div></dl><h3>user 对象</h3><dl class="schema-list"><div v-for="field in publicUserFields" :key="field.path"><dt><code>user.{{ field.path }}</code><b>{{ field.type }}</b></dt><dd>{{ field.description }}</dd></div></dl><h3>trips[] 元素</h3><dl class="schema-list"><div v-for="field in publicTripFields" :key="field.path"><dt><code>trips[].{{ field.path }}</code><b>{{ field.type }}</b></dt><dd>{{ field.description }}</dd></div></dl><h3>achievements 对象</h3><dl class="schema-list"><div v-for="field in achievementFields" :key="field.path"><dt><code>achievements.{{ field.path }}</code><b>{{ field.type }}</b></dt><dd>{{ field.description }}</dd></div></dl></details>
        </div>
      </section>

      <section id="errors" class="doc-section">
        <p class="section-label">Protocol</p><h2>格式与错误</h2>
        <div class="status-table" role="table" aria-label="HTTP 状态码">
          <div role="row"><strong role="cell">200</strong><span role="cell">请求成功。搜索不到车次通常返回空数组。</span></div>
          <div role="row"><strong role="cell">400</strong><span role="cell">参数缺失、为空或超出支持范围；正文通常为 <code>{ "message": "..." }</code>。</span></div>
          <div role="row"><strong role="cell">404</strong><span role="cell">指定行程或用户不存在。</span></div>
          <div role="row"><strong role="cell">5xx</strong><span role="cell">服务暂时不可用；调用方应采用指数退避重试。</span></div>
        </div>
        <p>除时刻表停站和搜索项为兼容铁路数据源使用蛇形命名外，JSON 字段使用 <code>camelCase</code>。时间为 ISO 8601 字符串；可选值可能为 <code>null</code>。所有响应采用 UTF-8。</p>
        <a class="issue-link" href="https://github.com/denglihong2007/RailLog/issues" target="_blank" rel="noreferrer">报告接口问题或订阅变更 <ExternalLink :size="16" /></a>
      </section>
    </article>
  </section>
</template>

<style scoped>
.api-page { width:min(1180px,100%); min-height:calc(100svh - 68px); margin:0 auto; padding:42px 24px 80px; display:grid; grid-template-columns:190px minmax(0,780px); gap:58px; align-items:start; }
.api-sidebar { position:sticky; top:100px; display:grid; gap:14px; }
.api-sidebar>strong { font-size:16px; }
.api-sidebar nav { display:grid; gap:2px; }
.api-sidebar a { min-height:36px; padding:7px 9px; border-left:2px solid var(--line); border-radius:0; color:var(--muted); font-size:14px; }
.api-sidebar a:hover { border-color:var(--brand); background:var(--surface-low); color:var(--ink); }
.api-content { min-width:0; }
.api-heading { scroll-margin-top:88px; }
.api-heading>p:first-child { margin:0 0 10px; display:flex; align-items:center; gap:8px; color:var(--brand); font-weight:700; }
.api-heading h1 { margin:0; display:block; font-size:clamp(38px,6vw,58px); line-height:1.1; }
.api-heading>span { display:inline-block; margin-top:12px; padding:5px 9px; border:1px solid var(--line); border-radius:5px; color:var(--muted); font-size:13px; }
.api-lead { max-width:700px; margin:20px 0 0; color:var(--muted); font-size:18px; line-height:1.75; }
.quick-facts { margin:30px 0 52px; display:grid; grid-template-columns:2fr 1fr 1.4fr; border-block:1px solid var(--line); }
.quick-facts div { min-width:0; padding:16px 14px; display:grid; grid-template-columns:auto minmax(0,1fr); gap:3px 8px; align-items:center; border-left:1px solid var(--line); }
.quick-facts div:first-child { border-left:0; }
.quick-facts svg { grid-row:1/3; color:var(--brand); }
.quick-facts span { color:var(--muted); font-size:12px; }
.quick-facts strong { overflow-wrap:anywhere; font-size:14px; }
.doc-section { padding:36px 0; border-top:1px solid var(--line); scroll-margin-top:78px; }
.doc-section:first-of-type { border-top:0; }
.section-label { margin:0 0 5px; color:var(--brand); font-size:13px; font-weight:750; text-transform:uppercase; }
.doc-section>h2 { margin:0 0 16px; font-size:30px; }
.doc-section>p:not(.section-label,.callout) { color:var(--muted); line-height:1.75; }
.policy-list { margin:22px 0; padding:0; display:grid; gap:13px; list-style:none; }
.policy-list li { display:grid; grid-template-columns:20px minmax(0,1fr); gap:9px; line-height:1.65; }
.policy-list svg { margin-top:4px; color:#26713a; }
.callout { margin:20px 0 0; padding:15px 17px; border-left:3px solid var(--brand); background:var(--surface-low); line-height:1.65; }
.endpoint { margin-top:26px; padding-top:25px; border-top:1px solid var(--line); scroll-margin-top:82px; }
.endpoint-title { min-width:0; display:flex; align-items:center; gap:10px; }
.method { flex:0 0 auto; padding:5px 7px; border-radius:5px; background:#176b3a; color:#fff; font-size:12px; font-weight:800; }
.endpoint-title code { min-width:0; font-size:17px; font-weight:700; overflow-wrap:anywhere; }
.endpoint>p { color:var(--muted); line-height:1.7; }
.endpoint h3 { margin:20px 0 8px; font-size:14px; }
code { font-family:"Cascadia Code","SFMono-Regular",Consolas,monospace; }
.parameter-list,.schema-list { margin:10px 0 20px; border-top:1px solid var(--line); }
.parameter-list div,.schema-list div { padding:11px 0; display:grid; grid-template-columns:190px minmax(0,1fr); gap:16px; border-bottom:1px solid var(--line); }
.parameter-list dt,.schema-list dt { min-width:0; }
.parameter-list code,.schema-list code { white-space:normal; overflow-wrap:anywhere; word-break:break-word; }
.parameter-list dt b,.schema-list dt b { display:block; margin-top:4px; color:var(--muted); font-size:11px; font-weight:500; }
.parameter-list dd,.schema-list dd { min-width:0; margin:0; color:var(--muted); line-height:1.55; overflow-wrap:anywhere; word-break:break-word; }
.code-heading { margin-top:18px; padding:8px 10px; display:flex; align-items:center; justify-content:space-between; background:#25282c; color:#dfe2e5; font-size:12px; }
.code-heading button { width:30px; height:30px; display:grid; place-items:center; border:0; border-radius:5px; background:transparent; color:inherit; cursor:pointer; }
.code-heading button:hover { background:#393d42; }
pre { max-width:100%; margin:0; padding:15px; overflow:auto; background:#16181b; color:#eef0f2; font-size:13px; line-height:1.6; }
details { margin-top:14px; padding:13px 15px; background:var(--surface-low); border-radius:6px; }
summary { cursor:pointer; font-weight:700; }
details p { color:var(--muted); line-height:1.65; }
.status-table { margin:20px 0; border-top:1px solid var(--line); }
.status-table>div { padding:12px 0; display:grid; grid-template-columns:64px minmax(0,1fr); gap:12px; border-bottom:1px solid var(--line); }
.status-table strong { color:var(--brand); font-family:monospace; }
.status-table span { color:var(--muted); line-height:1.55; }
.issue-link { margin-top:18px; display:inline-flex; align-items:center; gap:7px; color:var(--blue); font-weight:700; }
@media (max-width:800px) {
  .api-page { grid-template-columns:1fr; padding:34px 20px 60px; }
  .api-sidebar { display:none; }
}
@media (max-width:600px) {
  .api-page { padding-inline:16px; }
  .quick-facts { grid-template-columns:1fr; }
  .quick-facts div { border-left:0; border-top:1px solid var(--line); }
  .quick-facts div:first-child { border-top:0; }
  .parameter-list div,.schema-list div { grid-template-columns:1fr; gap:6px; }
  .endpoint-title { align-items:flex-start; }
}
@media (prefers-color-scheme:dark) { .method { background:#8bd49c; color:#12331d; } .policy-list svg { color:#8bd49c; } }
</style>
