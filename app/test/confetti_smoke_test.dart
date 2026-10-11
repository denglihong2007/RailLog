import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 守住一个新依赖的编译与启动。
///
/// `confetti` 发布于 2024 年，比本机 Flutter 旧，而 `flutter analyze` 只分析本仓库的
/// 源码、不编译 pub cache 里的包 —— 依赖内部若用了新版 SDK 移除的 API，只有真正
/// import 并跑起来才看得出来。成就页的解锁彩带依赖它，所以留一条最小的活体检查。
void main() {
  testWidgets('confetti 能在当前 SDK 上构建并发射', (tester) async {
    final controller = ConfettiController(
      duration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: const Alignment(0, -0.6),
                child: SizedBox.square(
                  dimension: 1,
                  child: ConfettiWidget(
                    confettiController: controller,
                    blastDirectionality: BlastDirectionality.explosive,
                    emissionFrequency: 1,
                    numberOfParticles: 10,
                    gravity: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    controller.play();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // 卸载掉，别把还在跑的 ticker 留在树上。
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
