# osm_update — 一键更新铁路底图

App 里「贴轨」用的折线来自 `app/assets/db/rail_tracks.db`，它是从 OSM 全国数据离线算出来的。
这个目录把「取最新数据 → 重新算一遍 → 写回 App 资源」串成一条命令，全部 OSM 相关代码都在
这里：

```bash
python tools/osm_update/update.py
```

跑完 `app/assets/db/rail_tracks.db` 就是最新的，重新构建 App 即生效。

## 目录里都有什么

**流水线本体**

| 文件 | 做什么 |
| --- | --- |
| `update.py` | 一键编排：下载 →（可选）校验 → 重建 → 打结果小结 |
| `download.py` | 拉 Geofabrik 的 [`china-latest.osm.pbf`](https://download.geofabrik.de/asia/china-latest.html)（约 1.6 GB）到 `tools/.cache/rail_tracks/`，支持断点续传 |
| `build_rail_tracks.py` | 主生成器：坐标索引 → 线路消歧 → 舍去对不上里程的坐标 → 枚举站间段 → 逐段规划 → 写 `rail_tracks.db` |
| `rail_track_geometry.py` | 几何与规划算法：构图、Yen k-短路、按线路名选路、绕路护栏、折线编码 |

**排查用的探针**（都是一次性诊断，改口径时用）

| 文件 | 查什么 |
| --- | --- |
| `probe_pbf.py` | PBF 里铁路数据的规模：way 数、坐标点数、单遍读取耗时与常驻内存 |
| `probe_stations.py` | OSM 车站坐标能覆盖 `routes.db` 里多少站（决定坐标主源） |
| `probe_service_connectors.py` | 车站咽喉的 `service=yard/siding` way 被丢掉是否就是拓扑断裂的成因 |
| `probe_line_match.py` | 运价表的线路名与 OSM way 名的匹配率；列不出对不上的普速线（这些段偏好集为空、只按几何选路） |
| `probe_lost_legs.py` | 对比两次生成的库，查「原本成功、现在失败」的段为什么失败 |
| `probe_discards.py` | 核对每个被舍去坐标的站：它到前后站的直线距离 vs 前后站的里程差（判断有没有误舍） |
| `probe_remaining_suspect.py` | 舍去坐标后仍判「坐标不可信」的段有哪几条 |
| `diagnose_failures.py` | 把失败段拆成「拓扑断裂 / 吸附不到」还是「被绕路护栏否掉」 |

**测试**：`test_rail_track_geometry.py`、`test_build_rail_tracks.py`、`test_osm_update.py`

```bash
cd tools && python -m unittest discover -p "test_*.py" -v
```

（`tools/` 本身不是包，所以从 `tools/` 下发现；`osm_update/` 是包，能被正常发现。各脚本
自己把所在目录插进 `sys.path`，因此既能当脚本直接跑，也能被 unittest 当包 import。）

除 `build_rail_tracks.py` 要用的 `pyosmium` 外，这里一律只用标准库。

## 常用姿势

```bash
# 全流程更新
python tools/osm_update/update.py

# 只更新数据，先看看新 PBF 长什么样，不动数据库
python tools/osm_update/update.py --download-only

# 不联网，用缓存里的 PBF 重算（改了算法口径后重跑就用这个）
python tools/osm_update/update.py --skip-download

# 写到别处，不覆盖正式库
python tools/osm_update/update.py --out tools/.test_out/tracks.db

# 只算一条线，验证改动（配 --workers 1：小样本没有多少规划活可并行，
# 多开几个进程只是让它们排队各读一遍 PBF——实测一条线 8 进程 190s、单进程 23s）
python tools/osm_update/update.py --skip-download --route 宝成线 --workers 1 \
    --out tools/.test_out/baocheng.db

# 下载后先校验 PBF 能读出铁路数据，再往下走（网络不稳时值得多花几分钟）
python tools/osm_update/update.py --probe
```

`update.py` 的 `--workers`（默认 16）直接透传给 `build_rail_tracks.py`。其余参数见各自
的 `--help`。

## 线位是怎么选出来的

一段轨道往往有并行好几种走法（高铁与普速各一条、外加联络线），挑哪条由两件事定：

1. **偏好集以线路名为准**。把 `routes.db` 的 `line_name` 和 way 的 `name` 各自归一化
   后比较，三档递进、**前一档命中就停**：

   1. `rail_track_geometry.line_match_key` 相同：剥掉「XX线XX段」的后缀、把
      `高铁/客专/客运专线` 统一成「高速」后一模一样。
   2. `rail_track_geometry.line_base_key` 相同：再把速度等级词（高速/城际/专线）也去掉。
      2.6.1 的线路库把等级词从线路名里删掉了（「沪宁沿江高铁」→「沪宁沿江」），
      当前线路库虽恢复全名，仍有不带等级词的线名；靠这一档接上「沪宁沿江高速线」。
   3. way 的基本名是线路基本名的前缀：「京包张包段」的区段后缀没法机械拆开，靠「京包」
      前缀认领「京包客专线」。

   名字一条都没命中时，高铁腿才退回 OSM 的等级标签（`highspeed` / `maxspeed≥200`）：
   站场附近的正线常常没有 `name`，只认名字会把它们全丢掉。有名字证据时**不再并标签**，
   否则并行的另一条高铁正线也会被算成「本线」，偏好集就分不出两条线了。普速侧没有
   对应的可靠标签（没打 `highspeed` 只是「没标」，不等于普速），所以名字落空时偏好集
   就是空的。

   为什么必须逐档短路：基本名抹掉了速度等级，`京广线` 与 `京广高速线` 在基本名上是同一
   个键。只要这条线在 OSM 里有严格同名正线，就绝不能再把另一等级的并行线拉进偏好集——
   那会把普速车次画到高铁正线上。第 2、3 档只在严格档完全落空时启用，此时这条线路名本
   来就没有同名正线。

   候选按 `长度 + 离线里程 × 5` 取代价最低的一条：离线 1km 相当于多绕 5km。只按长度
   取最短，会把正确但略长的同名正线让给走别的线路的直线捷径；只按贴线比例取最高，又
   会为了省几个百分点的无名站场段选一条明显更长的绕行线。折成一个标量后两个毛病都没
   有。实测徐兰高速线 渭南北→临潼东：借道大西高速线的回头支线 33.59km、离线约 9.5km，
   代价约 81km；正线 24.3km、几乎全在徐兰上，代价约 25km。

   **里程只记录、不选路**。线路库的 km 是运价里程，断链处相邻站的差值能和轨道实长差出
   十几公里（上面那段 km 差 30km、OSM 实长 24.3km），拿它反推几何会把折线拽上并行线，
   或者绕出回头支线。凑里程是经由线路计算那边的事，两边各有各的数据链。

   名字对不上的腿只剩几何可用，**额外吸附兜底仍然留着**：偏好集为空、主吸附候选的
   贴线比例低于 0.5，或最短候选超过直线距离 1.2 倍时，再多试几个「落在目标线上」的
   吸附点对（`search_paths` 的 `extra_snaps`）。最后那条是纯几何的：最近的那个图节点
   有时落在站场死端/环线上，从它出发只能绕一大圈，而一百多米外的节点就是直路（实测
   成灌线 犀浦→红光镇 16.94 vs 3.65km、珠机城际线 珠海长隆→井湾 15.81 vs 6.19km）。
   主吸附对本身不通时换过去的备用对也一样，第一对只能绕环线就接着试下一对（广深港
   高速线 虎门→光明城 53.29 vs 37.19km）。
   实测 新靖线新海段 盐城→东台 偏好集为空，靠这套兜底从 82.27km 的绕行路拉回
   61.86km 的正路。现库 794 条线路里，高铁侧 132 条中有 3 条、普速侧 662 条中有
   118 条在 OSM 找不到同名 way（`probe_line_match.py` 有逐条清单与各档分布）；这些段
   没有偏好信号，只能按几何长度与绕行倍率判定。真名不同（如「宁蓉线」vs「沪蓉线」）
   只能往 `LINE_ALIASES` 补别名，归一化规则救不了。

2. **站场与正线拓扑断开时允许「登乘跳」**。站场节点和正线在 OSM 里常是两套互不共点的
   几何（并行正线本来就不该共点：广州北的京广线与京广高速线并行 14~24m、无共点），
   同分量吸附永远够不着正线。于是允许吸附到半径 `--jump-radius-km`（默认 1km）内
   **目标线上**的节点，哪怕跨连通分量；这一跳以一小段直线出现在折线首尾，与站坐标到
   锚点的接驳段同性质。置 0 即关闭、退回老行为。

   触发条件很窄：主吸附对不通、或通了但现有候选里**没有一条「大半走在目标线上」的**
   （门槛 `JUMP_PROFILE_FLOOR`，0.9）。这个门槛不能取低：绕行线常常有一大段本来就走在
   目标线上（进站前才拐去并行的另一条线），ratio 能刷到刚过半，低门槛就触发不了跳站。
   实测京广高铁 广州北→广州南 的绕行线借道南广线，ratio 0.5004，登乘跳一次都不触发，
   这一段一直画在 51.71km 的绕行线上（里程差 4.71km）；跳上去的正确解是 46.10km、
   ratio 1.00、里程差 0.90km。

每段折线选了哪几条线，落在 `track_lines` 表（`seq` 有序，无名段记为「未命名」）；
`tracks` 上另有四个诊断列：`preferred_ratio`（贴目标线的里程占比）、`line_count`、
`board_jump_km`（首尾两段登乘跳的合计，每段各自不超半径，所以最大到 2×半径）、
`preferred_basis`（`tags` / `way-name` / `none`，即偏好集怎么来的）。
`SCHEMA_VERSION` 同时写进 `meta.schema_version` 与 `PRAGMA user_version`。App 侧按列名
`SELECT`，加列不影响它。

两点查库时的坑：

- **`line_count` 不是「换了几条线」**。无名 way（站场股道、少数没标名字的联络线）也算一段，
  而 OSM 里正线常被短的无名 way 打断——实测一条跑到底的高铁段也能有几十段。想数真正的
  换线次数，用 `SELECT COUNT(DISTINCT line_name) FROM track_lines WHERE line_name <> '未命名'`。
- **加了 `track_lines` 之后库大了约 2MB**（3.49→5.49MB，折线 BLOB 本身没变）。三个文本键
  在主键索引里又存了一份，19205 行摊下来就是这个量级。这是打包进 App 的资源，嫌大可以
  换成整数代理键（`tracks` 加一列 `id`，`track_lines` 只存 `track_id + seq`）。

## 耗时与内存

实测（32 核 / 31 GB 内存、可用内存只剩 11 GB 时的一次 16 进程全量重建）：

| 阶段 | 耗时 | 说明 |
| --- | --- | --- |
| 下载 | 视带宽 | 1.6 GB；10 MB/s 约 3 分钟 |
| 读 PBF | 16 × 20s（排队串行） | 每个 worker 各读一遍，是本阶段的大头 |
| 逐段规划 | 约 120s | 6174 段，16 进程并行 |
| **合计** | **约 440s** | |

重建阶段**每个 worker 进程要独立读一份 PBF**——那份几何网格几百 MB，没法在 Windows 的
spawn 下从父进程继承。内存账大致是：

- 读完稳定后每进程约 **0.6 GB**（那座网格）；
- 读 PBF 的那 20 来秒里，way 的节点号序列、待解析节点集合、解析出的坐标会同时在手，
  实测单进程瞬时私有内存到过 **2.6 GB**；
- 所以真正的峰值出现在**所有 worker 同时开始读**的那一刻，不是跑起来之后。16 个进程
  一起读要 30 GB 以上，硬上会把机器拖进交换。

为此加载阶段用了个跨进程信号量：**同时在读的进程数按当前可用内存算**，其余排队，读完
一个补一个。启动时那行 `并发读 PBF` 会告诉你这次放行几个：

```
并发           : 16 进程，重采样 400 m
并发读 PBF     : 最多 1 个进程同时加载（其余排队，读完转入规划）
```

内存越富余，放行的越多、总耗时越短；可用内存只有十几 GB 时就只能一个一个读，读 PBF
这 16 × 20s 就省不掉了——想快就跑之前先关掉别的程序。机器实在小就 `--workers 4`，或者
`--workers 1`——单进程会在本进程内建源，只读一遍 PBF，不必排队。

反过来说，**只重算一小撮线路时用 `--workers 1`**：每个排队的 worker 都要把整份 PBF 读
一遍，而十几段短腿的规划本身还不到一秒，多开进程纯属自找。全量那 6174 段才值得铺开。

## 断点续传

下载中断（断网、Ctrl-C）后重跑同一条命令即可：已下的部分留在
`tools/.cache/rail_tracks/china.osm.pbf.part`，下次带 `Range` 头从断点接着下，下满了才原子改名
成正式文件。所以**中途失败不会留下一个看起来像好文件的半成品**。

想强制重下用 `--force-download`（残片会一起丢掉）。

国内直连 Geofabrik 慢的话换个镜像：

```bash
python tools/osm_update/download.py --mirror https://mirror.example/china.osm.pbf
# 或者
python tools/osm_update/update.py --url https://mirror.example/china.osm.pbf
```

任何完整的 `china.osm.pbf`（同源 OSM 数据）都能用，`--pbf` 也可以直接指向别处的文件。

## 数据放哪

- 下载产物 `tools/.cache/rail_tracks/` 和调试输出 `tools/.test_out/` 都不进仓库
  （见 `../.gitignore`）；缓存**没跟着代码搬进这个目录**——1.6 GB 的 PBF 还是留在
  `tools/.cache/` 下，省一次重下；
- 脚本本身进仓库；
- 正式产物 `app/assets/db/rail_tracks.db` 是打包进 App 的，改完要重新构建 App 才生效。
