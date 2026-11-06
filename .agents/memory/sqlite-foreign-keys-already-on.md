# SQLite 外键默认就是开的

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-03*

2026-10-03 用 `.tmp/deadlockcheck` 实测：`PRAGMA foreign_keys` 在 `Data Source=<path>`
的连接上返回 **1**，无需任何显式设置。Microsoft.Data.Sqlite 在打开连接时默认启用外键。

`RailLogDatabase.cs` 里 `InitializeAsync`(:75) 和 `DeleteAccountAsync`(:548) 各有一行
`PRAGMA foreign_keys = ON;` —— 它们**不影响行为**，只是显式声明意图。schema 里声明的
`ON DELETE CASCADE`（如 `EntityReviewReactions` :176-177）**一直是生效的**。

**Why:** 这两行读起来像是在补一个默认关闭的开关，极易推出「外键没生效、孤儿行没人拦」
这个**错误**结论 —— 一份已批准的计划（R3 条）就这么写了，我也一度照此向用户复述。

**How to apply:**
- 判断某条 FK 会不会拦，直接看 schema 里的 `FOREIGN KEY` 声明即可，不用去查 PRAGMA 有没有设。
- 想「让 INSERT 在父行不存在时变成干净的空操作」仍需 `WHERE EXISTS` 守卫；带外键时
  裸 INSERT 会抛 `SqliteException` 错误码 19，把整轮写入打挂 —— 守卫的作用是避免抛异常，
  不是防孤儿行。
- 相关：[achievement-recompute-cost](./achievement-recompute-cost.md)
