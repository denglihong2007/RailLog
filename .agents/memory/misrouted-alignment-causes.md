# 线路走错线位的三个病因

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-10*

2026-10-10 排查用户反馈的两处错配，**三个独立病因**，别混为一谈。三个的修法都已落地
（`SCHEMA_VERSION = 2` 那一版）。

**一、profile 按线路名推断错（已修：普速侧改认线路名）**
`宁蓉线宁渝段` 六安↔长安集：实际跑的是 OSM 的 `沪蓉线`，但「宁蓉线宁渝段」里没有
高铁/客专 字样 → `infer_profile` 判成 conventional；而旧 `preferred_for` 对普速侧是
「没打高铁标签就算数」，成了默认垃圾桶，于是 宁西线（61.47km，ratio 1.00）压过
沪蓉线（60.78km，**里程误差反而更小**）。修法：普速侧 preferred 改为 way 名与
`line_match_key(route_name)` 同名；名字对不上就偏好集为空、退回纯里程——该段现在
自愈（走沪蓉线 58.83km，`preferred_basis='none'`）。全国匹配率：637 条普速线里 119 条
对不上，`probe_line_match.py` 有清单。

**二、OSM 正线与站场拓扑断裂（已修：登乘跳）**
`京广高铁` 广州北→广州南：`京广高速线` 与京广线在广州北并行 14~24m、**无共点**（并行
正线本就不该共点，这是正确映射，改 OSM 是错的）。`_alternative_snaps` 要求两端同分量，
永远够不着正线；`_extra_snap_candidates` 的池子按距离取最近 16 个，120m 内已被咽喉股道
占满。修法：`_jump_snap_candidates` 允许跨连通分量吸附到半径 1km 内**目标线上**的节点，
池子先按 `_on_preferred_edge` 过滤再取最近。

**三、登乘跳的放行门槛分不清「目标线」和「另一条同样被偏好命中的线」（已修）**
这是第二个修完**仍然没生效**的原因，最隐蔽：门槛原写「现有候选里没有 ratio ≥ 0.5 的
才跳」，而这段的主吸附对是**通的**——绕行线借道 `南广线`（250km/h，同样带 highspeed
标签），整段 ratio 0.5004 刚刚压过 0.5，于是跳线一次都不触发，一直画在 51.71km 的
绕行线上（里程差 4.71km）。高铁侧 preferred 的定义就是「带等级标签」，任何 200km/h
以上的线都算数，所以门槛必须取高：现为 `JUMP_PROFILE_FLOOR = 0.9`。修完该段
46.40km / ratio 0.997 / 里程差 0.60。

**How to apply:** 再遇到「某段走了别的线位」，先跑
`python tools/.test_out/probe_jump_gate.py <线路名> <起始站> <终到站>`——一条命令列出主对
候选的 ratio/误差、门槛判定、跳线候选，能直接分清是上面哪一种。要看走廊里有哪些 way、
怎么打的 tag，再用同目录的 `inventory_corridor.py` / `diagnose_alignment_choice.py`。

代价提醒：门槛放宽后登乘跳从 89 段涨到 435 段。全量对照旧库：成功 5489→5532、
误差 >2km 的段 329→291、49 段从 >2km 改善到 ≤2km；真正的回归 12 段，其中 9 段
ratio ≥ 0.69（换到正确线位的有意代价），只剩 4 段「跳了但没换来 ratio 提升」
（如 鹤岗铁路 鹤立→大陆 0.13→3.66km、ratio 0.03）。若嫌这 4 段，可加一条「跳线必须
换来 ratio 明显提升」的护栏——尚未实现。

**踩过的坑（护栏别挡过头）**：为省枚举给 `_extra_snap_candidates` 加
`if not graph.preferred_edges: return []`，本意只挡 `ratio < 阈值` 那条恒成立的判据，
结果把**里程误差**那条判据一起废了 → 约 30 段线条名对不上的普速腿丢掉备用吸附锚点的
兜底（盐城→东台 从误差 1.14km 劣化成 19.27km）。修法：护栏只对准 ratio 判据
（`suspicious = bool(graph.preferred_edges) and ...`）。教训：短路整个兜底函数时，
先数清它里面有**几条**用途不同的判据。

相关：[pipeline-run-gotchas](./pipeline-run-gotchas.md)、[track-split-removed](./track-split-removed.md)、[stations-null-means-unknown](./stations-null-means-unknown.md)
