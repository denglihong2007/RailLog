# 铁路时刻表

历史铁路时刻表按快照版本组织，版本号为 `yyyy.MM.dd`，表示数据快照日期，不代表车次的开行日期。当前覆盖 2003 至 2026 年，可用版本会随每日同步增加，请以[版本列表](#版本列表)为准。

车次号不区分大小写；车站名称需使用数据库中的完整站名。`version` 必填，且必须是版本列表中的值，否则返回 `400`。

## 版本列表

<Badge type="tip" text="GET" /> `/api/train-timetables/versions`

返回当前可用的全部快照版本，按版本号升序排列。其他时刻表接口的 `version` 参数必须取自该列表。

### 请求示例

```bash
curl "https://api.raillog.top/api/train-timetables/versions"
```

### 响应字段

响应正文直接是 `array<string>`，元素为 `yyyy.MM.dd` 格式的版本号；没有可用快照时为空数组。

```json
["2003.11.25", "2004.10.03", "2026.11.08"]
```

::: tip 版本与行程日期
版本是数据快照日期，不是车次的开行日期。调用方需要自行决定目标日期对应哪个版本；通常可以选择不晚于目标日期的最近一个版本。
:::

## 车次完整时刻表

<Badge type="tip" text="GET" /> `/api/train-timetables`

返回指定版本、指定车次的完整停站序列。无匹配记录时返回空的 `stops` 数组。

### 查询参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `trainNumber` | string | 是 | 车次号，例如 `G1`；也可以是带 `/` 的号对，例如 `D111/D114`。 |
| `version` | string | 是 | 快照版本，格式 `yyyy.MM.dd`，例如 `2026.11.08`。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/train-timetables?trainNumber=G1&version=2026.11.08"
```

### 响应字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `trainNumber` | string | 请求车次号去除首尾空白并转换为大写后的值，例如 `"G1"`。 |
| `version` | string | 本次查询使用的快照版本。 |
| `train_codes` | string | 实际命中的规范号对，例如 `"D111/D114"`；单号车次与 `trainNumber` 相同。 |
| `stops` | `array<object>` | 按运行顺序排列的停站数组；没有匹配车次时为空数组。 |
| `stops[].station_name` | string | 车站完整名称，不附加“站”字，例如 `"北京南"`。 |
| `stops[].station_no` | string | 停站顺序号。为兼容历史数据以字符串返回，例如 `"01"`；不应按数值格式解析。 |
| `stops[].arrive_time` | string | 计划到达时刻，通常为 24 小时制 `HH:mm`；始发站或原始数据缺失时为空字符串。 |
| `stops[].start_time` | string | 计划出发时刻，通常为 24 小时制 `HH:mm`；终到站或原始数据缺失时为空字符串。 |
| `stops[].running_time` | string | 预留的累计运行时间文本；当前历史数据返回空字符串。 |
| `stops[].arrive_day_str` | string | 预留的到达日描述；当前历史数据返回空字符串。 |
| `stops[].arrive_day_diff` | integer | 相对始发日的自然日偏移，`0` 表示当日，`1` 表示次日；最小值为 0。 |
| `stops[].mileage` | number | 从车次起点累计至该站的里程，单位 km；缺失或无法解析时为 0。 |

## 车次搜索

<Badge type="tip" text="GET" /> `/api/train-timetables/search`

按车次号前缀搜索车次，返回车次及始发、终到站。

### 查询参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `trainNumber` | string | 是 | 车次号前缀。 |
| `version` | string | 是 | 快照版本，格式 `yyyy.MM.dd`。 |
| `limit` | integer | 否 | 返回条数上限，取值 1–500；不传时不截断。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/train-timetables/search?trainNumber=G&version=2026.11.08&limit=50"
```

### 响应字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `version` | string | 本次搜索使用的快照版本。 |
| `trains` | `array<object>` | 匹配车次数组；无匹配结果时为空数组。 |
| `trains[].station_train_code` | string | 用于展示和后续查询的车次号。匹配到的号排在前面，例如搜索 `D114` 可能返回 `"D114/D111"`。 |
| `trains[].from_station` | string | 车次始发站。 |
| `trains[].to_station` | string | 车次终到站。 |
| `trains[].train_no` | string | 车次查询标识。当前与 `station_train_code` 相同，调用方不应依赖两者永远相等。 |
| `trains[].train_codes` | string | 库里的规范号对顺序，例如 `"D111/D114"`；单号车次只有一段。 |

::: tip 号对与单号
搜索按单个号前缀匹配，但每个号对只返回一行。同一个单号若挂在两个号对下（例如 `D8269` 与 `D8269/D8272` 是两趟不同的车），两行都会返回，不会合并。
:::

## 两站间车次

<Badge type="tip" text="GET" /> `/api/train-timetables/between`

查询在指定版本按顺序经过起点站和终点站的车次，最多返回 500 条。

### 查询参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `fromStation` | string | 是 | 起点站完整名称。 |
| `toStation` | string | 是 | 终点站完整名称。 |
| `version` | string | 是 | 快照版本，格式 `yyyy.MM.dd`。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/train-timetables/between?fromStation=北京南&toStation=上海虹桥&version=2026.11.08"
```

### 响应字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `version` | string | 本次查询使用的快照版本。 |
| `trains` | `array<object>` | 匹配车次数组；无匹配结果时为空数组。 |
| `trains[].station_train_code` | string | 完整号对形式的车次号，例如 `"D111/D114"`。 |
| `trains[].from_station` | string | 请求的起点站。 |
| `trains[].to_station` | string | 请求的终点站。 |
| `trains[].origin_station` | string | 该车次自身的始发站；过路车时与 `from_station` 不同。 |
| `trains[].terminal_station` | string | 该车次自身的终到站；过路车时与 `to_station` 不同。 |
| `trains[].depart_time` | string | 在起点站的计划出发时刻，`HH:mm`。 |
| `trains[].arrive_time` | string | 在终点站的计划到达时刻，`HH:mm`。 |
| `trains[].arrive_day_diff` | integer | 到达日相对出发日的自然日偏移，最小值为 0。 |
| `trains[].mileage` | number | 起点站至终点站的区间里程，单位 km。 |
| `trains[].train_no` | string | 车次查询标识。当前与 `station_train_code` 相同。 |
| `trains[].train_codes` | string | 库里的规范号对顺序。 |

## 车站到发车次

<Badge type="tip" text="GET" /> `/api/train-timetables/at-station`

返回指定版本在某站停靠的全部车次，附在该站的到达、出发时刻。最多返回 2000 趟。

### 查询参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `station` | string | 是 | 车站完整名称。 |
| `version` | string | 是 | 快照版本，格式 `yyyy.MM.dd`。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/train-timetables/at-station?station=北京南&version=2026.11.08"
```

### 响应字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `version` | string | 本次查询使用的快照版本。 |
| `trains` | `array<object>` | 停靠车次数组；无匹配结果时为空数组。 |
| `trains[].station_train_code` | string | 完整号对形式的车次号，例如 `"D111/D114"`。 |
| `trains[].from_station` | string | 该车次自身的始发站。 |
| `trains[].to_station` | string | 该车次自身的终到站。 |
| `trains[].train_no` | string | 车次查询标识。当前与 `station_train_code` 相同。 |
| `trains[].arrive_time` | string | 在该站的计划到达时刻；该站为始发站时为空字符串。 |
| `trains[].start_time` | string | 在该站的计划出发时刻；该站为终到站时为空字符串。 |
| `trains[].train_codes` | string | 库里的规范号对顺序。 |

::: tip 同一车次可能出现两行
折返车在同一站会去程、回程各停一次，因此同一车次号可能返回两行，且到发时刻不同。不要把车次号当作结果行的唯一键。
:::

## 车站列表

<Badge type="tip" text="GET" /> `/api/train-timetables/stations`

返回指定版本时刻表中的所有车站名称，按名称排序。

### 查询参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `version` | string | 是 | 快照版本，格式 `yyyy.MM.dd`。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/train-timetables/stations?version=2026.11.08"
```

### 响应字段

响应正文直接是 `array<string>`：车站完整名称组成的 JSON 数组，按名称升序排列且已去重；没有数据时为空数组。数组元素不会为 `null`。

### 响应示例

```json
["上海", "上海南", "上海虹桥"]
```
