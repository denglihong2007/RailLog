# 评价

铁路行程可以关联多条公开评价。评价可按实体或行程读取，均为只读接口，无需认证。

## 实体关联行程数

<Badge type="tip" text="GET" /> `/api/entities/{type}/{key}/count`

返回与指定实体关联的公开铁路行程数。统计的是行程，不是评价条数。

### 路径参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `type` | string | 是 | 实体类型：`station`、`route`、`company`、`rollingstock` 或 `train`。 |
| `key` | string | 是 | 实体名称，需进行 URL 编码；建议原样使用[实体搜索](./search.md)返回的 `entityKey`。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/entities/station/北京南/count"
```

### 响应字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `entityType` | string | 请求的实体类型。 |
| `entityKey` | string | 请求的实体名称。 |
| `totalCount` | integer | 关联的公开铁路行程数；无匹配时为 0。 |

### 匹配说明

- `station` 匹配出发站或到达站；
- `route` 对经由线路名做包含匹配；
- 其他类型按标准化后的名称精确匹配；
- 匹配不区分大小写并忽略空白。

## 实体评价

<Badge type="tip" text="GET" /> `/api/entities/{type}/{key}/reviews`

返回指定实体的全部公开评价，按创建时间降序排列。没有评价时返回空数组。

### 路径参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `type` | string | 是 | 实体类型：`station`、`route`、`company`、`rollingstock` 或 `train`。 |
| `key` | string | 是 | 实体名称，需进行 URL 编码。 |

::: tip 精确匹配
该接口按存储的 `entityType` 与 `entityKey` 精确匹配，区分大小写。请原样使用实体搜索返回的 `entityKey`；大小写或全半角不同都可能查不到记录。
:::

### 请求示例

```bash
curl "https://api.raillog.top/api/entities/station/北京南/reviews"
```

### 响应字段

响应正文是 `array<object>`，元素字段见[评价对象](#评价对象)。

## 行程评价

<Badge type="tip" text="GET" /> `/api/trips/{ticketId}/reviews`

返回与该行程关联的全部公开评价，包括该行程作为第一行程或第二行程的记录，按创建时间降序排列。

行程不存在、已删除或不是铁路行程时返回空数组，而不是 `404`。

### 路径参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `ticketId` | integer | 是 | 行程的公开数字 ID。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/trips/123/reviews"
```

### 响应字段

响应正文是 `array<object>`，元素字段见[评价对象](#评价对象)。

## 评价对象

实体评价与行程评价返回同一种对象：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | integer | 评价 ID。 |
| `entityType` | string | 被评价的实体类型。 |
| `entityKey` | string | 被评价的实体名称。 |
| `reviewType` | string | 评价类型：`station`、`transfer`、`route`、`company`、`meal`、`rollingStock` 或 `train`。 |
| `userId` | string | 作者的公开用户 ID。 |
| `displayName` | string | 作者的显示名称。 |
| `avatarUrl` | `string \| null` | 作者头像的绝对或可访问 URL；未设置时为 `null`。 |
| `rating` | integer | 评分，范围 1–5。 |
| `comment` | string | 评价正文。 |
| `tripId` | `integer \| null` | 关联的第一条行程 ID。 |
| `secondTripId` | `integer \| null` | 关联的第二条行程 ID，通常用于换乘评价。 |
| `transferMinutes` | `integer \| null` | 换乘等待分钟数；不适用时为 `null`。 |
| `routeFromStation` | `string \| null` | 经由区间的起点站；不适用时为 `null`。 |
| `routeToStation` | `string \| null` | 经由区间的终点站；不适用时为 `null`。 |
| `dish` | `string \| null` | 餐饮评价中的菜品；不适用时为 `null`。 |
| `price` | `number \| null` | 评价中记录的价格，单位人民币元；未记录时为 `null`。 |
| `createdAt` | `string<date-time>` | 评价创建时间，ISO 8601 日期时间字符串。 |
| `trip` | `object \| null` | 第一条关联行程；行程已删除时为 `null`。字段与[行程对象](./trips.md#trip-对象)一致。 |
| `secondTrip` | `object \| null` | 第二条关联行程；没有或已删除时为 `null`。字段与[行程对象](./trips.md#trip-对象)一致。 |
| `reactions` | `array<object>` | 表情回应汇总；没有回应时为空数组。 |
| `reactions[].emoji` | string | 表情符号。 |
| `reactions[].count` | integer | 该表情的回应数量。 |
| `reactions[].reactedByCurrentUser` | boolean | 匿名请求恒为 `false`。 |
| `achievementExperience` | integer | 作者当前累计的成就经验值。 |
