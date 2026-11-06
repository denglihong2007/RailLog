# 时刻表接口的三个消费方

*迁移自 Claude Code 项目记忆 · 更新于 2026-09-30*

`/api/train-timetables` 有三个消费方，改响应的字段前必须同时看这三处：

1. **主 App** — 本仓库 `app/`，只读 `stops` / `trains`，靠 `train_no` 去拉站序
   （`_selectTrain` → `fetchTrainSchedule(result.trainNo)`）。站站查询点选车次后
   直接进「录入行程」表单，靠的就是这个字段。
2. **RailLog-Query** — `C:\Users\delih\Desktop\repos\RailLog-Query`，Flutter 应用，
   **不在本仓库、也不是 git 仓库**。它消费 `/at-station`（本仓库 Web 文档里没有）、
   `/between` 的区间时刻/里程、站序的 `train_codes`。它的模型层对老服务端向后兼容
   （缺 `train_codes` 时退回 `station_train_code`），也永远显式传 `/search` 的 `limit`。
3. **Web 文档** — `web/src/components/ApiDocs.vue` 是对外契约，`/between` 一节复用
   `trainSearchFields`。

**Why:** 2026-10 那次改动是为 RailLog-Query 加的接口（新增 `/at-station`、`train_codes`、
`/search` 的 `limit`），顺手把 `/between` 的 `train_no` 删了、又把 `/search` 的默认上限
设成 50。RailLog-Query 根本不需要这两处 —— 结果是主 App 的站站查询点选车次后拉不到站序，
前缀搜索的建议列表被字典序截断成 G1/G10/G100…。

**How to apply:** 新增字段随意；**删字段、改字段含义、改无参调用的默认行为之前**，
先确认主 App 和 RailLog-Query 都没用到。可选参数应保持 opt-in（不传 = 旧行为），
别把新上限做成服务端默认值。相关：[timetable-db-outside-repo](./timetable-db-outside-repo.md)、[timetable-version-resolution](./timetable-version-resolution.md)
