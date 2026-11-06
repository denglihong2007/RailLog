# 原生注册文件的幽灵改动

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-11*

在 RailLog 里跑过任何触发 `pub get` 的 flutter 命令（`flutter pub add`、`flutter test`、
`flutter build`）之后，`git status` 会多出这 7 个「已修改」：

```
app/linux/flutter/generated_plugin_registrant.cc / .h / generated_plugins.cmake
app/macos/Flutter/GeneratedPluginRegistrant.swift
app/windows/flutter/generated_plugin_registrant.cc / .h / generated_plugins.cmake
```

**它们没有任何内容改动**，纯粹是行尾：工具链写回 LF，而 git 按 `text=auto` 会 checkout 成
CRLF。判据是 `git diff --ignore-all-space --stat -- app/linux app/macos app/windows`
**输出为空**（只有 `warning: LF will be replaced by CRLF`）。

**How to apply**：当作噪声，`git checkout -- app/linux app/macos app/windows` 还原即可，
别提交、也别据此以为自己的改动碰了原生侧。提交时用显式路径 `git add <file>...`，
不要 `git add -A`。

**Why**：2026-10-11 一个会话里连踩两次，且因为 `git status` 有它、`git diff` 没有它，
很容易误判成「执行代理改了原生注册文件」。

相关：[dart-format-preexisting-drift](./dart-format-preexisting-drift.md)（同类噪声：看着像自己的改动，其实是环境差异）
