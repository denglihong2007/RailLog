# Release 库的 train_no 没归一化

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-31*

Timetable-Results 的 Release 库里 `stops.train_no` 是**原始车次串**：`4651/4654B`、
`1060/1061/1063`、`6062#2` 这类写法都还在，而客户端一直看到的是归一化后的号对
（`4651/4654`、`1060/1061`、`6062`）。改造后查询侧不再转换数据，只能在 SQL 里复刻
`tools/build_train_timetables.py` 的规则（见 `TrainTimetableService.PairsCte`）：

- 只取前两段，三段号丢掉第三段；
- 去掉 `#N` 后缀与车号尾缀字母；
- 两段相同只留第一段；
- 归一化后重号只保留**字典序最小**的原始 train_no（其余整趟丢弃，约 400 趟）。

**Why:** 少做一步归一化就会出现「搜 D114 搜到 D111/D114、查站序却查不到」这类断链；
验证办法是拿改造前的 DLL 跑同一组探针做逐字比对（`api/.tmp/timetable-baseline` 与
`api/.tmp/timetable-eq-check`）。

**How to apply:** 改这两处任何一个（构建脚本或查询 CTE）都要重跑等价性探针，
不要只看行数。相关背景见 [timetable-db-outside-repo](./timetable-db-outside-repo.md)。
