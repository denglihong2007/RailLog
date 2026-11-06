# 减弱动效在 Flutter 里的真实语义

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-11*

Flutter 隐式动画（`AnimatedSize`、`AnimatedSwitcher`、`TweenAnimationBuilder`、
fl_chart 等继承 `ImplicitlyAnimatedWidget` 的）**已经在系统层面响应「减弱动效」**：

- `packages/flutter/lib/src/animation/animation_controller.dart:651` ——
  `AnimationBehavior.normal when SemanticsBinding.instance.disableAnimations => 0.05`，
  即动画时长压缩到 5%（约一帧）。
- `packages/flutter/lib/src/widgets/media_query.dart:320` —— `MediaQueryData.disableAnimations`
  本身就取自 `view.platformDispatcher.accessibilityFeatures.disableAnimations`，同一个系统开关。

**推论**：RailLog 里 m3_motion.dart 那 4 个 helper 的
`MediaQuery.of(context)?.disableAnimations` 显式闸门，与散落各处的裸 `AnimatedSize`，
**在真机上行为差异很小** —— 两者都响应系统设置。显式闸门的真实价值只在于：
(a) 一致性；(b) 万一将来在 app 内注入 `MediaQuery` 级覆盖，或写断言该行为的 widget 测试。
**评估这类问题时不要把它当成无障碍缺陷去渲染严重性** —— 我 2026-10-11 的审计初稿就犯了
这个错，先夸大后自我更正。

相关：[material-ui-migration-blocker](./material-ui-migration-blocker.md)
