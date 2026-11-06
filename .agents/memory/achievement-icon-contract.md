# 成就图标的三方契约

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-17*

成就图标是三方契约，缺一处不会报错，只会静默走 fallback：

1. `api/Services/AchievementEngine.cs` 的 `Definitions` —— 图标名必须全局唯一（`BuildDefinitionIndex()` 在静态初始化时断言 id 与 icon 都不重复）。
2. `app/lib/src/widgets/dashboard_achievement_card.dart` 的 `dashboardAchievementIconKey` —— `'name' => Icons.name`，`_ => Icons.emoji_events_outlined`。
3. `web/src/components/UserLookup.vue` 的 `achievementIconCodepoints` —— `name: 0x码点`，未知名字回落到 `0xf01a`（奖杯）。

**Why:** 加引擎图标时容易以为要改两个客户端。2026-10 时两张客户端表已基本与引擎对齐（App 仅剩 `help_outline`、`people_outline` 两个未被占用的条目，Web 仅剩 `help_outline`），所以新成就通常要挑一个*全局未用过*的图标名，并在三处同时新增；直接复用现有名字会在静态初始化时被 `BuildDefinitionIndex()` 判重。

**How to apply:** 先从引擎现有图标集合里排除，再查 Web 表；Web 表缺了才补，补之前用 Flutter SDK 的 `D:/flutter/packages/flutter/lib/src/material/icons.dart` 取权威码点（不要从字体文件反查 —— 那个 OTF 的 `post` 是 3.0 格式没有字形名，format-12 cmap 会把内存吃爆）。App 表只有在引擎用了它*确实没有*的名字时才需要改。

**图标名没有权威来源**：`26w40成就.xlsx` 的 sheet2 只有 B 名称 / C 经验 / D 描述 / E 旁白 / F 注释 五列，**没有图标列**，所以引擎里每一个图标名都是自己挑的，对不上不能怪表格。同理 `verify_new.py` 里那 4 条「fields match the workbook」的 icon 断言其实是在断言我自己的选择，改图标签时必须同步改它。

Web 侧码点要先在字体里验字形再写进表：`web/public/fonts/materialicons-regular.otf` 的 cmap 要按 format 4 / format 12 分别二分查找（整表展开会 MemoryError），查不到字形的码点会渲染成豆腐块而不是回落成奖杯。

相关：[stations-null-means-unknown](./stations-null-means-unknown.md)
