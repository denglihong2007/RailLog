# 成就重算的真实耗时

*迁移自 Claude Code 项目记忆 · 更新于 2026-11-05*

2026-10-03 用 `.tmp/synccheck` 实测（本机，Debug）：

- **同步 1 万条行程**：totalMs 705，其中 `upsertMs` 639、`commitMs` 27、`readMs` 39、`lockMs` 0。
- **同一用户的成就重算**：`computeMs` ≈ 142–170 秒（两次运行）。

也就是说**写接口「转圈」的元凶从来不是同步 SQL，而是内联在同步事务里的成就重算**，
两者相差约 240 倍。重算会持进程级 `_writeLock`，所以一个大账号同步会把**所有用户**的写请求堵住
两分多钟 —— 这正是「排行榜秒开、同步卡死」的成因。

重算本身的瓶颈是成就 SQL 里的 O(n²) 自连接（`RailLogDatabase.cs` 的 `secondTrip` 自连接，
约在 :767/:850/:994/:1103 四处）加上 `AchievementEngine.Evaluate` 的 8 轮循环。

**How to apply:**
- 因为 upsert 只占 0.7 秒，**批量 upsert 优化没有意义**（那条待办可以关掉）。
- 大账号是主要风险面：重算已改为后台任务，但 `_recomputeSlots = min(ProcessorCount,4)`，
  小机器上几个大账号同时同步就能打满 CPU。
- `Achievements:RecomputeWaitSeconds` 调大之前先看这组数 —— 重算动辄几分钟，
  上限设大了等于让成就接口长期固定等满。
- 相关：[api-tmp-harness-pattern](./api-tmp-harness-pattern.md)

2026-11-06 补测**全站重算**（admin-test.db 快照，1153 个用户）：普通账号每人 0.3–1.4 秒，
最大的账号单次 46 秒，一轮全站约 1–2 小时量级。所以「保存等级分界线后重算」必须是后台单飞任务，
前台只能轮询状态，不能等它。UI 文案不要承诺「几分钟」。
