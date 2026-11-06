# 管线运行期的两个坑

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-28*

`tools/osm_update/build_rail_tracks.py` 跑 `--apply` 时用 `multiprocessing`（Windows 上是 spawn），
worker **在启动时会重新 import 这个模块**。所以管线一旦跑起来（16 个 worker 陆续启动的头几分钟），
就不能再编辑 build_rail_tracks.py——父进程和 worker 会各跑一份不同版本的代码，结果无从解释。
要改就先停掉或等它结束。

**Why:** 我在运行中改了一行 docstring 才意识到这个风险，之后只能把编辑全部推到跑完，白等一轮。

**How to apply:** 先跑干跑（`--source pbf`，不写库、约 1.5 分钟，只吃车站缓存）确认坐标/段数一类的数字，
再跑 `--source pbf --apply` 落库。全量落库 2026-10-29 实测 979s（约 16 分钟，早先无宽走廊重试时是约 543s）：
失败段会各多取 1-2 次更宽 bbox 的数并重新构图，失败段越多越慢。坐标类改动靠干跑就能验证，
不必每次都落库。落完库两边都要回归：`cd app && flutter analyze && flutter test`，
以及 `cd tools && python -m unittest discover -p "test_*.py"`。相关：[stations-null-means-unknown](./stations-null-means-unknown.md)
