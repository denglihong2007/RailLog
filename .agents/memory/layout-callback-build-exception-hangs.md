# layout 回调里抛异常 = 卡死

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-11*

两个连在一起的事实，2026-10-11 在成就页上踩实（`cf1231c`）：

1. **`TweenAnimationBuilder` 断言 `tween.end != null`**（`tween_animation_builder.dart:197`，
   在 `initState` 的 `_constructTweens` 里）。写 `ColorTween(end: someNullable)` 是地雷 ——
   传 `null` 表示「这次不补间」是不存在的语义。同一个文件里的
   `quick_add_card.dart:692` 之所以没事，只是因为它三个分支都落成具体颜色。

2. **在 layout 回调里构建的 widget 抛异常 = 卡死，不是「一个红框」**。
   `SliverGrid`/`SliverList` 的 `performLayout` → `invokeLayoutCallback` → `buildScope`
   是一条链；异常中断整个网格的布局，之后**每帧重试、每帧再抛**，画面永远 present
   不出来。用户描述成「卡死 / 界面不动」，而且 debug 下才成立（release 断言被剥掉）。

**Why**：`DashboardAchievementCard` 的底色补间把未解锁分支的 `null` 交给了
`TweenAnimationBuilder`，成就页列表里绝大多数卡片未解锁 → 点「查看更多」直接卡死。
一开始我怀疑是彩带（新依赖、无限 ticker）造成的，方向全错 —— 真正的原因在
卡片上，且**没有待庆祝项时同样必现**，这一点就足以排除彩带。

**How to apply**：页面「卡死 / 打不开」时，先找有没有断言类异常，别先怀疑动画库。
优先跑一条把整页挂起来的 `testWidgets`（记 `expect(tester.takeException(), isNull)`），
它比读代码快得多。给 `TweenAnimationBuilder` 传值前确认 `end` 非空；
列表/网格里的卡片尤其要有一条**未解锁、未选中、空数据**这类「默认态」的测试 ——
已有的 `dashboard_achievement_test.dart` 只测了 `unlocked: true`，所以漏了。

相关：[widget-tests-cannot-do-io](./widget-tests-cannot-do-io.md)（挂整页测试要做哪些 mock）、
[flutter-reduce-motion-semantics](./flutter-reduce-motion-semantics.md)（同一批动效改动里的另一条）
