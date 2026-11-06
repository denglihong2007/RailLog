# 别全量跑 dart format

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-11*

`dart format --output=none --set-exit-if-changed` 对 RailLog 的
`app/lib/src/pages/home_page.dart` **必然报「已改」**，但那是 Dart 3.7+ 新格式化器与该文件历史格式的
既有分歧，**不是任何一次改动的锅**。（典型形态：把「参数刚好放得下」的多行调用收成一行。）

**判断方法**：把基线也丢进格式化器 —— `git show HEAD:<path> > /tmp/x.dart` 然后对两边各跑一次，
比较 `grep '^@@'` 出来的 hunk 头。若**逐字节一致**，分歧就是既有的，与你的改动无关。
2026-10-11 对 home_page.dart 实测：基线与改动后都是 7 个 hunk，hunk 头完全相同。

**Why**：我据此差点把一次干净的执行代理误判成引入了缩进漂移。

**How to apply**：提交前别顺手跑全量 `dart format`，否则 diff 会混进一大片无关重排；
只在确认某文件基线本就干净时才对它单独格式化。

相关：[plan-execution-worktree-mechanics](./plan-execution-worktree-mechanics.md)
