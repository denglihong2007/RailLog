# RailLog — 代理工作指南

RailLog 由 `app` 里的 Flutter 客户端和 `api` 里的 ASP.NET Core 服务组成：客户端持有离线
SQLite 库，登录后按账号同步行程记录。运行方式、配置项与部署说明见 [README.md](README.md)。

## 项目记忆

这些条目迁移自此前 Claude Code 的 RailLog 项目记忆（原文在
`~/.claude/projects/c--Users-delih-Desktop-repos-RailLog/memory/`），现在存放在
`.agents/memory/`，随仓库一起维护。

- 每行只是结论摘要；**动手改相关代码前先读对应的完整文件**，里面有具体路径、Why 与 How to apply。
- 记忆记录的是「不读代码或历史就会踩错」的结论，不是文档；与代码冲突时以代码为准，并顺手更正记忆。
- 新增长期有效的结论：在 `.agents/memory/<slug>.md` 新建文件（`# 标题` + 正文，按需写 **Why** / **How to apply**），并在下面列表里加一行。

- [material_ui 迁移阻塞](.agents/memory/material-ui-migration-blocker.md) — cached_network_image 4.x / dynamic_color 2.x / shimmer 4.x 在 Flutter 3.44.6 上都用不了；筛依赖查 pub.dev API 的运行期依赖
- [管线运行期的两个坑](.agents/memory/pipeline-run-gotchas.md) — 跑起来后不能改 build_rail_tracks.py；整轮落库约 9 分钟，干跑 1.5 分钟够用
- [stations 表的 NULL ≠ 缺行](.agents/memory/stations-null-means-unknown.md) — NULL 行是「没有可信坐标」，必须让 App 一并丢掉 CSV 的同名值
- [等级门槛的三处副本](.agents/memory/user-level-thresholds-contract.md) — 默认值仍在引擎与 App 里硬编码，改一处要改全部
- [成就图标的三方契约](.agents/memory/achievement-icon-contract.md) — 引擎/App/Web 三处图标表，App 侧通常已有备用条目，Web 侧会静默降级成奖杯
- [历史时刻表库不在仓库里](.agents/memory/timetable-db-outside-repo.md) — API 每天从 Timetable-Results 的 Release 同步，一个快照一个 db 文件，token 走 user-secrets
- [Release 库的 train_no 没归一化](.agents/memory/timetable-release-query-normalization.md) — 查询侧要在 SQL 里复刻归一化规则，改完必须跑新旧等价性探针
- [行程日期 → 版本号的推导规则](.agents/memory/timetable-version-resolution.md) — 约 20% 的日期会回退到「绝对最近」，选出的版本可能在行程之后
- [时刻表里「没里程」是 0.0 不是 NULL](.agents/memory/timetable-zero-means-no-mileage.md) — 非始发站的 0 要当缺失，否则算出一段巨型里程、整条经由线路错掉
- [时刻表接口的三个消费方](.agents/memory/timetable-api-multi-client.md) — 主 App / 仓库外的 RailLog-Query / Web 文档，字段只能加不能删
- [对比每周成就.xlsx 的固定噪声](.agents/memory/achievement-spec-excel.md) — 数字排版、附表5/6 编号笔误、附表6 计数列、附表1 旧站名、表头行，别当成真实差异
- [后端验证靠 api/.tmp harness](.agents/memory/api-tmp-harness-pattern.md) — 没有测试工程；这些 harness 被 git 忽略，只在本机；断成就要判 TriggerTripId
- [widget 测试能做哪些 I/O](.agents/memory/widget-tests-cannot-do-io.md) — sqflite/资源/文件会静默挂死；走 SharedPreferences 的页面用 setMockInitialValues 可以测；页面里 Future.delayed 的残留 Timer 会在收尾判死
- [「/」编组分隔符与存量数据冲突](.agents/memory/slash-formation-legacy-data.md) — 库里 55 条旧车型串把 / 当车号用，用户选择不兼容、待清理
- [成就重算的真实耗时](.agents/memory/achievement-recompute-cost.md) — 单个大账号约 170 秒、全站 1153 人约 1–2 小时，同步 upsert 只要 0.7 秒；批量 upsert 优化没有意义
- [SQLite 外键默认就是开的](.agents/memory/sqlite-foreign-keys-already-on.md) — 那两行 PRAGMA 是冗余的，别据此推断外键关闭
- [设置页副标题的写法](.agents/memory/settings-subtitle-style.md) — 描述设置项本身，不要呈现当前状态/当前值
- [上下行分离已整链移除](.agents/memory/track-split-removed.md) — 一段只存一条折线，tracks 表没有 direction 列，别再按平行 way 拆上下行
- [线路走错线位的三个病因](.agents/memory/misrouted-alignment-causes.md) — profile 推断错 / 站场与正线断裂 / 登乘跳门槛分不清目标线；先跑 probe_jump_gate.py 定位
- [经由线路在平行线间横跳](.agents/memory/via-route-tie-flip.md) — 四轮：状态带线路名 / 1 km 并列带 / 排序按「线路名少 → 误差小 → 潜力里程」/ 刻度差按站数累积（0.5 km×站数）
- [换向行程的折返怎么合并](.agents/memory/via-route-reversal-self-loop.md) — 判据是「本段已走过的站又被走一遍」，不是首尾同名；西安换向拆成 灞桥→西安 / 西安→灞桥
- [车型解析器认哪些车号分隔符](.agents/memory/train-model-parser-number-forms.md) — 动车组认 - 和空格，客车/机车只认空格，RZ25K-111111 会解析不出车号
- [更新日志的写法](.agents/memory/release-notes-writing-style.md) — 受众是普通用户：成就不写细节只列名字，实现细节与开发侧提醒都不进日志
- [更新日志的版本范围怎么取](.agents/memory/release-notes-range-derivation.md) — 按最终 diff 写，别逐条搬 commit subject；release 提交自己也带改动
- [减弱动效在 Flutter 里的真实语义](.agents/memory/flutter-reduce-motion-semantics.md) — 裸 AnimatedSize 也响应系统设置（框架压到 5%），别当成无障碍缺陷去渲染严重性
- [跑 plans/ 执行代理的两个坑](.agents/memory/plan-execution-worktree-mechanics.md) — dev 与 origin/master 分叉；plans/ 未被跟踪，worktree 里的代理读不到
- [别全量跑 dart format](.agents/memory/dart-format-preexisting-drift.md) — home_page.dart 等历史文件本就不符合新版格式化器，会卷进无关 diff
- [原生注册文件的幽灵改动](.agents/memory/generated-registrant-phantom-diff.md) — pub get 之后 7 个 generated_plugin_registrant* 显示已修改，其实只是行尾
- [layout 回调里抛异常 = 卡死](.agents/memory/layout-callback-build-exception-hangs.md) — TweenAnimationBuilder 断言 end 非空；网格/列表里的卡片崩了会每帧重放，界面永远出不来
- [SkiaSharp 4 打印更浓](.agents/memory/skiasharp4-pdf-print-darkening.md) — 文字从内联路径改成 Type3 字体；逐像素一致，但部分打印驱动会把 Type3 打得更粗
