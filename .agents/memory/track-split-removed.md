# 上下行分离已整链移除

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-10*

2026-10-10 起，站间轨道**只存一条折线**，不再区分上下行：

- `rail_track_geometry.py` 删掉了整套分离判据（`_split_pair`/`_lateral_profile`/`TRACK_SPLIT_*`），
  `LegPlan` 只剩 `polyline`/`length_km`；
- `rail_tracks.db` 的 `tracks` 表**没有 `direction` 列**，主键是 `(route_name, from_station, to_station)`；
- App 侧 `RailTrackPair` 已删，`RailTrackIndex.findOriented` 直接返回 `List<List<double>>?`；
- 元信息的 `split_legs`/`track_split` 两个键也没了（`update.py` 的小结白名单同步删）。

**Why:** 用户明确说「不再需要考虑上下行线路分离相关的逻辑了」，选的是全链路清除而非只停生成器。

**How to apply:** 在 OSM 里见到画成两条明显分开的平行 way（阳安线 石泉县→池河等）时，
按单条折线处理即可，别再去猜哪条是上行。有 `direction` 列的旧库与现在的 App 不兼容——
旧库的 up/down 两行会落到同一个键上互相覆盖，必须用重建后的库（同日重跑
`build_rail_tracks.py --source pbf --apply`，5489 段，约 9 分钟）。相关：[pipeline-run-gotchas](./pipeline-run-gotchas.md)
