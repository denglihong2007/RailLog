# 等级门槛的三处副本

*迁移自 Claude Code 项目记忆 · 更新于 2026-11-05*

用户等级门槛（LV0–LV6 的最低经验）现在由管理后台可配置，存 `AppSettings` 的 `UserLevels:Thresholds`，
公开接口 `GET /api/user-levels` 返回当前值与 `updatedAt`。后台的「等级与成就」页在
`GET /api/admin/user-levels` 里还会返回 `totalUsers` 与各等级人数：统计口径是
`SUM(UserAchievements.Experience)` 按用户分组后套用门槛，与 App/引擎的 TotalExperience 一致，
无成就的用户计入 LV0。但默认值仍硬编码在三处：

- `api/Services/UserLevels.cs` 的 `DefaultThresholds`（引擎未取到配置时的兜底，也是后台「恢复默认值」的来源）
- `app/lib/src/widgets/user_level_badge.dart` 的 `_defaultLevelMinimumExperience`
- 成就引擎的 `reachLevel3/5/6` 已改为读 `AchievementContext.LevelThresholds`，不再自己写死数字

**Why:** 任何一处漏改，都会出现「后台显示 A、App 显示 B、成就按 C 判定」的不一致，而且不会报错。

**How to apply:** 要调整默认分界线时三处一起改，并检查 `UserLevels.Validate`（7 项、`[0]==0`、严格递增、上限 1,000,000）。
保存后会触发全站成就重算（见 [achievement-recompute-cost](./achievement-recompute-cost.md)），App 侧在启动时读本地缓存并后台刷新。
