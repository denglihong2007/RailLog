# widget 测试能做哪些 I/O

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-11*

`app/test/` 里 `testWidgets` 的 body 跑在假时钟 zone 里，**真实的异步 I/O 永远不会完成**：sqflite（`sqflite_common_ffi`）、`rootBundle.load` 资源、文件读写都会永久挂起。表现是 `flutter test` 卡到超时，只报一行 `did not complete [E]`，没有任何堆栈——看不出是哪里卡的。

两个具体的坑：

- `await DbHelper.instance.getAllTrips()` 写在 `testWidgets` body 里（哪怕外面套着 `runAsync`）也不可靠。纯 `test()` 没这个问题，所以 `db_helper_sync_test.dart` 那种写法是好的，照抄它。
- `ManualTripPage`（以及任何 `initState` 里做 I/O 的页面）**连 `pumpAndSettle` 都过不去**：`initState → _loadRouteCatalog() → RouteService` 要读 `assets/db/routes.db`，其间 `_isLoadingRouteCatalog` 为真、界面挂着转圈，永远 settle 不了。实测 `pumpAndSettle`、`runAsync` 两种写法都挂，两次各耗 7 分钟。

**结论：widget 测试只用来测纯 UI 组件**（`app_card_test.dart`、`user_level_badge_test.dart` 那种）。涉及数据库或页面级逻辑的，退到 `test()` + `DbHelper` 这一层写；`ManualTripPage` 这类页面目前没有可行的测试入口，要测就得先把 `RouteService` 改成可注入。

**2026-10-10 补充（SharedPreferences 是例外）**：`setUp(() => SharedPreferences.setMockInitialValues({}))` 之后，纯 prefs 支撑的页面可以正常写 widget 测试——`settings_pages_layout_test.dart` 里 10 个设置页（含根页面，它通过 `_TicketOcrEntry` 读 prefs）渲染测试 1 秒全过。挂死的只有 sqflite / `rootBundle` / 真实文件。另外，界面上有**常驻**加载指示器的页面（如 OCR 页的 `_loading` 转圈）别用 `pumpAndSettle`，它永远 settle 不下来，改用 `await tester.pump(const Duration(milliseconds: 800))`。抓布局溢出的办法：先把 `tester.view.physicalSize` 设成 360 宽再 pump，溢出会直接被 `tester.takeException()` 抓到。

**2026-10-11 补充（测试结束时残留的 Timer 会当场判死）**：页面代码里用 `Future.delayed` 排的等待，在 widget 测试末尾没法掐断，teardown 报 `Failed assertion: '!timersPending'`（`flutter_test` 的 `A Timer is still pending even after the widget tree was disposed`），而且只报断言、不给位置，得靠回想「哪段页面逻辑还在等」才找得到。**页面里的等待要能被 `dispose` 掐断**：持有一个 `Timer?` 字段，`dispose` 里 `cancel`；掐断时不必去完成配对的 `Completer`（调用方此时必然 `!mounted`，让它吊着既省事又无泄漏）。成就页的「逐个庆祝」巡回就是这么改的（`_waitTimer`）。

同一次踩到的另一半：**断言「第 N 次发生了某件事」时，不能数某一帧里挂着的 widget 实例**。成就页每发彩带是换 key 重新挂载的，上一发会在下一发开始前卸掉，所以任何一帧最多只看得见 1 个，`expect(seen.length >= 3)` 永远不成立——而它前一步恰好能过（上一发的 controller 还挂着），失败点因此指向了完全无关的那一行。让计数集合由测试自己持有、跨次累加。

**Why:** 这类挂死不给任何线索，很容易反复重试同一条死路，白烧时间。
**How to apply:** 想给某个页面加回归测试前，先看它的 `initState` 有没有 I/O；只有 sqflite / 资源加载 / 文件读写要直接放弃，走 prefs 的可以放心写。相关：[api-tmp-harness-pattern](./api-tmp-harness-pattern.md)
