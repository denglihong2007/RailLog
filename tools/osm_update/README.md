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
| `rail_track_geometry.py` | 几何与规划算法：构图、Yen k-短路、里程校验、上下行分离判定、绕路护栏、折线编码 |

**排查用的探针**（都是一次性诊断，改口径时用）

| 文件 | 查什么 |
| --- | --- |
| `probe_pbf.py` | PBF 里铁路数据的规模：way 数、坐标点数、单遍读取耗时与常驻内存 |
| `probe_stations.py` | OSM 车站坐标能覆盖 `routes.db` 里多少站（决定坐标主源） |
| `probe_service_connectors.py` | 车站咽喉的 `service=yard/siding` way 被丢掉是否就是拓扑断裂的成因 |
| `probe_lost_legs.py` | 对比两次生成的库，查「原本成功、现在失败」的段为什么失败 |
| `probe_discards.py` | 核对每个被舍去坐标的站：它到前后站的直线距离 vs 前后站的里程差（判断有没有误舍） |
| `probe_remaining_suspect.py` | 舍去坐标后仍判「坐标不可信」的段有哪几条 |
| `diagnose_failures.py` | 把 `mileage_mismatch` 拆成「里程不对」还是「OSM 拓扑断裂」 |

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

## 耗时与内存

实测（32 核 / 31 GB 内存、可用内存只剩 11 GB 时的一次 16 进程全量重建）：

| 阶段 | 耗时 | 说明 |
| --- | --- | --- |
| 下载 | 视带宽 | 1.6 GB；10 MB/s 约 3 分钟 |
| 读 PBF | 16 × 20s（排队串行） | 每个 worker 各读一遍，是本阶段的大头 |
| 逐段规划 | 约 120s | 5796 段，16 进程并行 |
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
一遍，而十几段短腿的规划本身还不到一秒，多开进程纯属自找。全量那 5796 段才值得铺开。

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
