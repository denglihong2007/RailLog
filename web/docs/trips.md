# 行程详情

## 公开行程详情

<Badge type="tip" text="GET" /> `/api/trips/{ticketId}`

按正整数行程 ID 返回公开用户资料和单条行程；记录不存在时返回 `404`。

### 路径参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `ticketId` | integer | 是 | 行程的公开数字 ID。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/trips/123"
```

### 响应字段

根对象：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `user` | object | 该行程所属用户的公开资料。 |
| `trip` | object | 指定 ID 对应的公开行程详情。 |

#### `user` 对象

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 用户的稳定公开 ID；作为 `/api/users/{userId}` 的路径参数使用。 |
| `displayName` | string | 用户公开显示名称。 |
| `avatarUrl` | `string \| null` | 头像的绝对或可访问 URL；未设置头像时为 `null`。 |
| `bio` | `string \| null` | 用户公开个人简介；未填写时为 `null`。 |
| `email` | `string \| null` | 电子邮箱地址。仅当用户主动开启公开邮箱时返回，否则为 `null`。 |
| `achievementExperience` | integer | 用户已解锁成就的累计经验值，用于计算公开等级。 |

#### `trip` 对象

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
