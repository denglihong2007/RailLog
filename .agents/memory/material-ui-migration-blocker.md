# material_ui 迁移阻塞

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-11*

RailLog 的 App 端（`app/`）在 Flutter 3.44.6 / Dart 3.12.2 上**无法**使用这两个大版本：

- `cached_network_image` 4.x —— 传递依赖 `material_ui` 1.3.0，其源码使用 `@awaitNotRequired` 注解，本机 SDK 未定义，**编译报错**（`flutter analyze` 不会发现，只有 `flutter test` / `flutter build` 才会暴露，因为 analyze 不检查 pub cache）。
- `dynamic_color` 2.x —— `DynamicColorBuilder` 回调返回 `material_ui` 的 `ColorScheme`，与 app 全局使用的 `package:flutter/material.dart` 的 `ColorScheme` 是**不同的类**，赋值直接类型不匹配。
- `shimmer` 4.0.0（2026-10-11 查证）—— pubspec 声明 `flutter: ">=3.44.0"`，看着完全匹配本机 3.44.6，但**运行期**依赖 `material_ui: ^1.0.1`，同一雷区。同功能的 `skeletonizer` 3.0.0 运行期依赖只有 flutter sdk，是可用的替代。

**筛任何新依赖前先查 `pub.dev/api/packages/<name>`**，看 `latest.pubspec.dependencies` 里有没有 `material_ui`。注意只看**运行期**依赖：`skeletonizer` 的 *dev*_dependencies 里有 `material_ui`，但 dev 依赖不传递给消费者，不构成问题。

根因：`material_ui` 是 Flutter 新的 Wasm 兼容 Material 实现（自带 `lib/src/`，不 re-export `flutter/material.dart`）。要用这两个包，必须把整个 app 从 `package:flutter/material.dart` 迁移到 `package:material_ui/material_ui.dart`。

**注意**：`material_ui` 1.3.0 的 pubspec 声明 `flutter: ">=3.44.0"`，看似兼容，实际编译不过 —— 不要相信它的环境约束。

另：`sqlite3` 卡在 3.5.2 是因为 3.6.0 要求 `hooks ^2.2.0`，而 Flutter 3.44.6 工具链把 `hooks` 钉在 2.0.2，属于 SDK 侧限制。（原记忆 `pubspec-upgrade-status` 未随迁移提供。）
