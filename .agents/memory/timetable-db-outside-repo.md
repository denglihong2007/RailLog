# 历史时刻表库不在仓库里

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-31*

历史时刻表（约 860MB、两百多个快照）**不在仓库里**。2026-10-31 改造后 API 不再读
单个 `train_timetables.db`，`TrainTimetables:DatabasePath` 已删除：

- 同步：`TimetableSyncService` 每天 06:00（Asia/Shanghai）从私有仓库
  `denglihong2007/Timetable-Results` 拉 Release，校验后原样存成
  `{ContentRoot}/timetables/{yyyy.MM.dd}.db`（约 860MB 总量），查询侧直接读 `stops` 表，
  不再转换成按版本分表的结构。
- Token 必须走 user-secrets：`dotnet user-secrets set "TrainTimetables:Sync:GitHubToken" "<token>"`。
- 首次部署会补齐全部版本（实测约 7 秒/版，约半小时），期间未同步到的版本接口返回空。
- `tools/build_train_timetables.py` 仍能产出旧的单库分表结构，但 API 已不再使用；
  本地旧库在 `C:\Users\delih\Desktop\raillog-data\train_timetables.db`，可作离线对照。

**Why:** 换机器 / 清环境后仓库里找不到时刻表，容易误以为数据丢了或去改 `Assets/`；
旧文档里「靠 user-secrets 指路径」的说法已经过时。

**How to apply:** 需要动时刻表数据时看 Release 同步是否正常（`api/timetables/` 下的文件数），
不要去找 `DatabasePath` 配置。查询侧的车次号归一化见
[timetable-release-query-normalization](./timetable-release-query-normalization.md)，日期推导规则见 [timetable-version-resolution](./timetable-version-resolution.md)。
