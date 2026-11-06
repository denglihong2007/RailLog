# 用户信息

## 公开用户信息

<Badge type="tip" text="GET" /> `/api/users/{userId}`

返回用户公开资料、全部未删除行程及公开成就信息；隐藏且已解锁的成就不返回，用户不存在时返回 `404`。

### 路径参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | string | 是 | 用户的完整公开 ID，路径中需进行 URL 编码。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/users/USER_ID"
```

### 响应字段

根对象：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `user` | object | 被查询用户的公开资料。 |
| `trips` | `array<object>` | 该用户全部未删除的公开行程，按出发时间降序、行程 ID 降序排列；没有记录时为空数组。 |
| `achievements` | object | 该用户的公开成就状态和全站解锁统计，不包含隐藏且已解锁的成就。 |

#### `user` 对象

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 用户的稳定公开 ID；作为 `/api/users/{userId}` 的路径参数使用。 |
| `displayName` | string | 用户公开显示名称。 |
| `avatarUrl` | `string \| null` | 头像的绝对或可访问 URL；未设置头像时为 `null`。 |
| `bio` | `string \| null` | 用户公开个人简介；未填写时为 `null`。 |
| `email` | `string \| null` | 电子邮箱地址。仅当用户主动开启公开邮箱时返回，否则为 `null`。 |
| `achievementExperience` | integer | 用户已解锁成就的累计经验值，用于计算公开等级。 |

#### `trips[]` 元素

`trips` 数组元素与[行程详情](./trips.md)中的 `trip` 对象字段完全一致：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `ticketId` | integer | 行程的公开数字 ID，可用于 `/api/trips/{ticketId}`。 |
| `createdAt` | `string<date-time>` | 行程记录创建时间，ISO 8601 日期时间字符串。 |
| `trainNumber` | string | 车次或交通班次号；未记录时可能为空字符串。 |
| `rollingStock` | `string \| null` | 车型或车辆型号，例如 `"CR400AF"`；未记录时为 `null`。 |
| `companyName` | `string \| null` | 承运单位或担当单位名称；未记录时为 `null`。 |
| `fromStation` | string | 行程起点站或起点地点名称。 |
| `toStation` | string | 行程终点站或终点地点名称。 |
| `departureTime` | `string<date-time> \| null` | 实际记录的出发时间，ISO 8601 日期时间；未记录时为 `null`。 |
| `arrivalTime` | `string<date-time> \| null` | 实际记录的到达时间，ISO 8601 日期时间；未记录时为 `null`。 |
| `mileageKm` | number | 本次行程里程，单位 km；未记录时通常为 0。 |
| `viaRoutes` | string | 经由线路的 JSON 编码字符串。解码后通常为对象数组：`routeName` 是线路名，`fromStation`/`toStation` 是该段起终点，`mileageKm` 是该段公里数；无有效数据时可能为空字符串。 |
| `seatType` | `string \| null` | 席别，例如 `"二等座"`；未记录时为 `null`。 |
| `seatNumber` | `string \| null` | 座位或铺位文本，例如 `"05车 12A"`；未记录时为 `null`。 |
| `price` | number | 票价或行程花费，单位人民币元；保留位数由原始记录决定。 |
| `notes` | `string \| null` | 用户公开备注；未填写时为 `null`。 |
| `isRailTrip` | boolean | 是否为铁路行程；`false` 表示用户记录的其他交通行程。 |

#### `achievements` 对象

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `totalUserCount` | integer | 计算成就解锁人数时采用的全站用户总数。 |
| `achievements` | `array<object>` | 公开成就定义及该用户状态数组。隐藏成就仅在未解锁时返回，且信息以“？？？”隐藏。 |
| `achievements[].id` | string | 成就稳定标识，例如 `"midnightBoarding"`。 |
| `achievements[].category` | string | 成就分类：`milestones`、`extremeChallenges`、`railwayCatalog`、`touring` 或 `funJourneys`。 |
| `achievements[].icon` | string | Material Icons 图标 key，例如 `"nightlight_outlined"`。 |
| `achievements[].title` | string | 成就的中文标题。 |
| `achievements[].description` | string | 成就解锁条件的文字说明。 |
| `achievements[].status` | string | 该用户的状态：`"unlocked"` 表示已解锁，`"locked"` 表示未解锁。 |
| `achievements[].triggerTripId` | `integer \| null` | 触发解锁的公开行程 ID；尚未解锁或没有对应行程时为 `null`。 |
| `achievements[].unlockedUserCount` | integer | 全站已解锁该成就的用户数量。 |
| `achievements[].progressCurrent` | `number \| null` | 可量化成就的当前进度；不支持进度或已无进度信息时为 `null`。单位由成就条件决定。 |
| `achievements[].progressTarget` | `number \| null` | 可量化成就的目标值；不支持进度时为 `null`，与 `progressCurrent` 使用相同单位。 |
| `achievements[].experience` | integer | 该成就提供的基础经验值；隐藏成就未解锁时返回 0。 |
| `achievements[].note` | `string \| null` | 技术性注释，例如车型清单或判定区间；没有技术注释时为 `null`。 |
| `achievements[].narrativeNote` | `string \| null` | 叙事性注释；隐藏成就未解锁时返回 `null`。 |
| `achievements[].requirements` | `array<object> \| null` | 固定候选集合型成就的逐项达成情况；不适用或隐藏成就时为 `null`。 |
| `achievements[].requirements[].key` | string | 要求项的稳定标识，例如席别、车型、车站或线路名称。 |
| `achievements[].requirements[].label` | string | 要求项的中文展示名称。 |
| `achievements[].requirements[].completed` | boolean | 该要求项是否已经完成。 |
| `achievements[].requirements[].trip` | `object \| null` | 首次完成该要求项的行程摘要；尚未完成时为 `null`。 |
