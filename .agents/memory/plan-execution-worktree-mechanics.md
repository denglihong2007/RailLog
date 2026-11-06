# 跑 plans/ 执行代理的两个坑

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-11*

用 subagent 执行 `plans/` 下的计划时，RailLog 有两个坑（2026-10-11 实测）：

1. **分支是分叉的，不是快进关系。** `dev` 领先本地 `master` 233 个提交；而 `origin/master`
   又领先 `dev` **51 个提交且不是 `dev` 的祖先**。`worktree.baseRef` 未配置时，Agent 工具的
   `isolation: "worktree"` 走默认 `fresh`，从 `origin/<默认分支>` = `origin/master` 起分支 ——
   会得到一个**每个 file:line 都对不上**的代码库，计划直接报废（而且不会报错，只会静默漂移）。
   **做法**：不要依赖 Agent 的 worktree 隔离，自己显式建
   `git worktree add .claude/worktrees/<name> -b <name> <dev 的 SHA>`，
   再把**手写**的执行 prompt 交给一个普通 subagent。

2. **`plans/` 未被跟踪**（`?? plans/`；原记忆 `plans-output-location` 未随迁移提供）。所以任何在 worktree 里跑的
   代理**读不到计划文件** —— 必须把主 checkout 的绝对路径
   `C:/Users/delih/Desktop/repos/RailLog/plans/<xxx>.md` 写进 prompt。

另：改动落在 worktree 里时，用户 VSCode 的源代码管理面板**什么都看不到**（那份工作树逐字节等于基线，
SCM 是按仓库来的）。要让他看到就得落库到 `dev`。同时 `.claude/` 未被 gitignore，
`git add .` 会把整个 worktree 连同 `.git` 文件提交进去。

相关：[dart-format-preexisting-drift](./dart-format-preexisting-drift.md)
