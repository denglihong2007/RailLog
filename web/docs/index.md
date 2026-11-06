# RailLog 开放 API

面向铁路应用、个人工具与数据研究的公开只读接口。无需 API Key，支持服务端和浏览器跨域调用。

**稳定版 v1 · 生效日期 2026-08-17**

| 项目 | 说明 |
| --- | --- |
| 基地址 | `https://api.raillog.top` |
| 认证 | 无需认证 |
| 响应格式 | JSON · UTF-8 |
| 数据范围 | 历史铁路时刻表（2003–2026 快照）、公开行程、公开用户资料、公开评价与等级门槛 |

## 兼容性承诺

本文列出的未版本化路径构成 RailLog 开放 API v1。RailLog 承诺在 v1 生命周期内维持现有 HTTP 方法、路径、必填参数、字段类型和既有字段语义。

- 新增响应字段、增加新的可选参数或新增端点属于向后兼容变更。调用方应忽略无法识别的字段。
- 不会在 v1 中删除字段、改变字段类型、收紧已有有效参数，或把公开端点改为必须认证。
- 确需破坏性变更时将发布新版本路径；v1 会提前至少 12 个月公告弃用，并在公告期内继续可用。
- 安全修复、滥用防护、数据纠错及服务不可用时返回的 4xx/5xx，不视为兼容性破坏。

::: warning 兼容性边界
兼容性承诺针对接口结构与语义，不构成可用性 SLA，也不保证历史数据库中始终存在某一车次或用户记录。
:::

## 接口一览

| 接口 | 说明 |
| --- | --- |
| `GET /api/train-timetables/versions` | 获取可用的历史时刻表快照版本 |
| `GET /api/train-timetables` | 按版本与车次号获取完整停站序列 |
| `GET /api/train-timetables/search` | 按车次号前缀搜索车次 |
| `GET /api/train-timetables/between` | 查询按顺序经过两个车站的车次 |
| `GET /api/train-timetables/at-station` | 查询某站的全部到发车次 |
| `GET /api/train-timetables/stations` | 获取某版本的全部车站名称 |
| `GET /api/search/entities` | 搜索车站、线路、车次、车型或承运单位 |
| `GET /api/trips/{ticketId}` | 按行程 ID 获取公开用户资料与行程详情 |
| `GET /api/trips/{ticketId}/reviews` | 获取行程关联的公开评价 |
| `GET /api/entities/{type}/{key}/reviews` | 获取某个实体的公开评价 |
| `GET /api/entities/{type}/{key}/count` | 获取某个实体的关联行程数 |
| `GET /api/users/{userId}` | 获取公开用户资料、全部行程与成就信息 |
| `GET /api/user-levels` | 获取用户等级的经验门槛 |

## 快速开始

```bash
# 先取可用版本，再用版本查询时刻表
curl "https://api.raillog.top/api/train-timetables/versions"
curl "https://api.raillog.top/api/train-timetables?trainNumber=G1&version=2026.11.08"
```

所有响应均为 UTF-8 编码的 JSON，浏览器端可直接跨域调用，无需额外请求头。

## 文档导航

- [铁路时刻表](./timetable.md)：版本列表、车次时刻表、车次搜索、站站查询与车站到发
- [搜索](./search.md)：车站、线路、车次、车型与承运单位搜索
- [评价](./reviews.md)：实体评价、行程评价与关联行程数
- [行程详情](./trips.md)：单条公开行程、所属用户与行程评价
- [用户信息](./users.md)：用户公开资料、出行记录、成就与等级门槛
- [格式与错误](./errors.md)：字段命名、时间格式与 HTTP 状态码
