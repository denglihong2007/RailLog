# 车型解析器认哪些车号分隔符

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-10*

`TrainModelParser` 拆「车型串 → 型号 + 车号」时，两种车的分隔符规则不同：

- **动车组**（以 CR / CJ / MTR / LCR 开头）：从末尾回扫数字，前一个字符是 `-` 或空格都算分隔符。
  `CR400AF-AS-1111` → ModelCode `CR400AF-AS`、Numbers `["1111"]`。
- **客车 / 机车**：只有**空格**算分隔符。`RZ25K-111111` 会解析成 Model `25K-111111`、**Numbers 为空**；
  正确写法是 `RZ25K 111111`。

所以按客车车号判定的成就一律走 `RollingStockMatches(value, new RollingStockTarget("RZ25K", "111111"))`
这条统一解析路径（同 `UnlocksVerticalSleeper`），**不要**为了迁就某个写法再补按原串的正则。

规格书里的 `RZ25K-111111` 是笔误（作者把动车组的 `-` 写法套到了客车上），引擎按正确写法收录，
diff Excel 时这条会一直报"取得条件不一致"，是有意的。

**Why:** 曾想用正则把两种写法都认下来，被否掉了——统一解析比兼容笔误更重要。
**How to apply:** 写按车号判定的成就就造一个 `RollingStockTarget`；规格原文里的车型串先过一遍脑子再照抄。
相关：[achievement-spec-excel](./achievement-spec-excel.md)、[api-tmp-harness-pattern](./api-tmp-harness-pattern.md)
