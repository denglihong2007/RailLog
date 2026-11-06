# 行程日期 → 版本号的推导规则

*迁移自 Claude Code 项目记忆 · 更新于 2026-09-30*

App 端不再让用户手选年份，版本由行程日期**自动推导**
（`app/lib/src/models/timetable_version.dart` 的 `resolveTimetableVersion`）：

1. 行程日期**之后第一个**快照，且间隔 ≤ 31 天 → 用它；
2. 否则取**绝对距离最近**的快照（并列取较早的，保证确定性）。

快照间隔不均，实测最大空档 415 天，所以约 **20% 的日期会走到第 2 步**，
而且第 2 步选出的快照**可能仍在行程日期之后**——这是需求「否则选最近的」刻意如此，
不是 bug。

**Why:** 看到「选了个比行程日期晚的版本」时容易误判成实现错误而"修"掉它。

**How to apply:** 改动这段逻辑前先跑 `app/test/timetable_version_test.dart`，
边界用 31 天（含）为界。数据源与库的位置见 [timetable-db-outside-repo](./timetable-db-outside-repo.md)。
