# stations 表的 NULL ≠ 缺行

*迁移自 Claude Code 项目记忆 · 更新于 2026-09-25*

`rail_tracks.db` 的 `stations` 表里，**坐标为 NULL 的行**表示「管线知道这个站，但判定它没有可信坐标」
（与前后站的直线距离都对不上客里表里程），App 必须把 `coordinates.csv` 里的同名值一并丢掉；
**没有这一行**才表示「管线不知道这个站」，此时才可以退回 `coordinates.csv` 兜底。
管线侧的写法见 `station_rows(index, legs, discarded)`（2026-09-25 加），App 侧的读取见
`RailStationIndex.fromBatches` 与 `StationCoordinateIndex.fromSources`。

**Why:** 这个约定跨 Python 管线和 Dart App 两层，且和直觉相反——「表里没有」看起来更像「不知道」，
而 NULL 反而更像「没有数据」。App 的坐标索引以 coordinates.csv 为基线、管线表只是覆盖，
所以少写一行 NULL 就会让刚舍掉的错坐标从兜底路径原样回来（新立屯/永乐 那类同名异地错配），
地图上照旧画到错误省份，而且不会有任何报错。

**How to apply:** 给 `stations` 表加导出、或在 App 侧改坐标查询逻辑时，先确认这条约定。
被舍去的站前后两站会自动桥接成一段，管线也会为这段写折线，所以不能顺手把 NULL 行「清理」掉。
相关：[pipeline-run-gotchas](./pipeline-run-gotchas.md)
