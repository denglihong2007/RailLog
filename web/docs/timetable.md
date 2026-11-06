# 铁路时刻表

历史铁路时刻表当前覆盖 2009 至 2026 年。车次号不区分大小写；车站名称需使用数据库中的完整站名。

## 车次完整时刻表

<Badge type="tip" text="GET" /> `/api/train-timetables`

返回指定年份、指定车次的完整停站序列。无匹配记录时返回空的 `stops` 数组。

### 查询参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `trainNumber` | string | 是 | 车次号，例如 `G1`。 |
| `year` | integer | 是 | 时刻表年份，当前为 2009–2026。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/train-timetables?trainNumber=G1&year=2026"
```

### 响应字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `trainNumber` | string | 请求车次号去除首尾空白并转换为大写后的值，例如 `"G1"`。 |
| `year` | integer | 本次查询使用的历史时刻表年份。 |
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
| `year` | integer | 是 | 时刻表年份。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/train-timetables/search?trainNumber=G&year=2026"
```

### 响应字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `year` | integer | 本次搜索使用的历史时刻表年份。 |
| `trains` | `array<object>` | 匹配车次数组；无匹配结果时为空数组。 |
| `trains[].station_train_code` | string | 用于展示和后续查询的车次号，例如 `"G1"`。 |
| `trains[].from_station` | string | 车次始发站；两站间查询中为请求的起点站。 |
| `trains[].to_station` | string | 车次终到站；两站间查询中为请求的终点站。 |
| `trains[].train_no` | string | 车次查询标识。当前与 `station_train_code` 相同，调用方不应依赖两者永远相等。 |

## 两站间车次

<Badge type="tip" text="GET" /> `/api/train-timetables/between`

查询在指定年份按顺序经过起点站和终点站的车次，最多返回 100 条。

### 查询参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `fromStation` | string | 是 | 起点站完整名称。 |
| `toStation` | string | 是 | 终点站完整名称。 |
| `year` | integer | 是 | 时刻表年份。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/train-timetables/between?fromStation=北京南&toStation=上海虹桥&year=2026"
```

### 响应字段

字段与[车次搜索](#车次搜索)的响应一致：`year` 与 `trains` 数组，其中 `from_station`/`to_station` 为本次请求的起点站与终点站。

## 车站列表

<Badge type="tip" text="GET" /> `/api/train-timetables/stations`

返回指定年份时刻表中的所有车站名称，按名称排序。

### 查询参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `year` | integer | 是 | 时刻表年份。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/train-timetables/stations?year=2026"
```

### 响应字段

响应正文直接是 `array<string>`：车站完整名称组成的 JSON 数组，按名称升序排列且已去重；没有数据时为空数组。数组元素不会为 `null`。

### 响应示例

```json
["上海", "上海南", "上海虹桥"]
```
