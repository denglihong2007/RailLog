# 时刻表里「没里程」是 0.0 不是 NULL

*迁移自 Claude Code 项目记忆*

历史时刻表库里，某站**没有里程**落库是 `0.0`，不是 `NULL`。三处一起这么定的：
`tools/build_train_timetables.py` 的 `normalize_mileage`、表结构的
`mileage REAL NOT NULL DEFAULT 0`、接口侧的 `ReadDouble` 回退值。

拿它算区间里程（相邻站累计里程相减）时，**非始发站的 0 或负值只能理解成缺失**：
真按 0 算，这一段就成了「从 0 到 900」的巨型里程，经由线路跟着整条错掉 ——
而且错得不像错，图上的搜索照样返回一条看着合理的走法。
始发站（下标 0）本来就是 0，判缺失时要用 `index > 0` 放行，别误伤。

对照 [stations-null-means-unknown](./stations-null-means-unknown.md)：那张 `stations` 表里 `NULL` 表示「没有可信坐标」，
和这里 `0.0` 表示「没有里程」是两个不同表的两种不同约定，别混用判据。

**Why:** 0.0 是个合法数字，看起来不像「缺数据」，静态检查、类型系统、代码审查都拦不住；
这条只有翻建库脚本和表结构才能发现，而它在距离计算里的破坏是整条经由线路级别的。

**How to apply:** 任何消费历史站序里程的地方（现为
`app/lib/src/models/train_schedule_stop.dart` 的 `_cumulativeMileageAt`），
都要把非始发站的 `<= 0` 折成 `null`，让那段退回最短路径，而不是拿去相减。
