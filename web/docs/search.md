# 搜索

## 实体搜索

<Badge type="tip" text="GET" /> `/api/search/entities`

按名称搜索车站、线路、车次、车型或承运单位，并返回每个结果关联的公开铁路行程数。无需认证。

### 查询参数

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `type` | string | 是 | 实体类型：`station`、`route`、`company`、`rollingstock` 或 `train`。 |
| `q` | string | 否 | 搜索关键词；为空或缺失时返回空数组，最长 100 个字符。 |
| `limit` | integer | 否 | 返回条数上限，默认 20，取值范围 1–50。 |

### 请求示例

```bash
curl "https://api.raillog.top/api/search/entities?type=station&q=北京&limit=5"
```

### 匹配规则

- 匹配前会去除首尾空白、转为小写并删除所有空白字符；
- 关键词与实体名称做包含匹配，因此 `北京` 可以匹配 `北京南`；
- 结果按「完全匹配 → 前缀匹配 → 关联行程数降序 → 名称升序」排序；
- `station` 同时匹配行程的出发站和到达站；
- `route` 匹配经由线路名；
- `rollingstock` 按车型解析后的标准化车型代码匹配；
- `train` 匹配车次号。

### 响应字段

响应正文是 `array<object>`；没有匹配结果时为空数组。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `entityType` | string | 实体类型，与请求的 `type` 对应（小写）。 |
| `entityKey` | string | 实体名称，可作为[评价接口](./reviews.md)中的 `{key}`。 |
| `tripCount` | integer | 关联的公开铁路行程数。 |

### 响应示例

```json
[
  { "entityType": "station", "entityKey": "北京南", "tripCount": 123 },
  { "entityType": "station", "entityKey": "北京", "tripCount": 98 }
]
```

### 错误

不支持的 `type` 或超过 100 个字符的 `q` 返回 `400`。
