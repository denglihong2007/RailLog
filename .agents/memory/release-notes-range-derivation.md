# 更新日志的版本范围怎么取

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-10*

写某一版的更新日志时：

- **基线**取上一版的 `release: x.y.z` 提交（2.5.1 是 `8b60e3d`），范围 `git log <基线>..HEAD`。注意真正发布的点是 master 上的 PR 合并提交（`v2.5.1` tag 指向 `25dcc4e`，不是 `8b60e3d`），两者内容一致，但别拿 tag 的 SHA 当基线。
- **按最终状态写，不要逐条搬 commit subject**。区间里常有更晚的提交把前面的改动重做或推翻，逐条写会写出已经不存在的中间状态。2.5.2 区间里就有三处：`8921797` 加在设置根页的地图卡片被 `bc478a5` 搬进「显示」子页；`57992c2` 茕茕孑立兼容连字符的写法被 `0307539` 推翻；`13cf103` 的「我的评价」独立卡片被 `440173b` 并进账户卡。
- **`release: x.y.z` 这个提交自己可能带用户可见改动**（`440173b` 改了 77 增 42 删的设置页），subject 里看不出来，必须看它的 diff。
- 每个结论落笔前用 `git show HEAD:<file>` 或 grep 核对最终值（常量、文案、阈值、成就定义），别只信 commit message。
- CI 建 release 时 `body: ''`、`generate_release_notes: false`，说明文字全部手写。

**Why:** 用户 2026-10-11 连着两次纠这一点——「有些 commit 是新的 commit 产生的」「release commit 自带的改动」。

**How to apply:** 先 `git log --format="%h %s%n%b" <基线>..HEAD` 通读全量 body，再对每条结论回 HEAD 验证。写法与受众见 [release-notes-writing-style](./release-notes-writing-style.md)。
