import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/engagement_prompt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('首次在第五次保存后提示分享', () async {
    final now = DateTime(2026, 7, 22);
    for (var count = 1; count < 5; count++) {
      expect(await EngagementPromptService.recordTripSaved(now: now), isNull);
    }
    expect(
      await EngagementPromptService.recordTripSaved(now: now),
      EngagementPromptKind.share,
    );
  });

  test('满足保存次数和冷却时间后交替提示捐赠', () async {
    final firstPromptAt = DateTime(2026, 1, 1);
    for (var count = 0; count < 5; count++) {
      await EngagementPromptService.recordTripSaved(now: firstPromptAt);
    }

    final nextPromptAt = firstPromptAt.add(const Duration(days: 15));
    for (var count = 0; count < 9; count++) {
      expect(
        await EngagementPromptService.recordTripSaved(now: nextPromptAt),
        isNull,
      );
    }
    expect(
      await EngagementPromptService.recordTripSaved(now: nextPromptAt),
      EngagementPromptKind.donate,
    );
  });

  test('关闭提示后不再返回提示类型', () async {
    await EngagementPromptService.disable();
    for (var count = 0; count < 20; count++) {
      expect(
        await EngagementPromptService.recordTripSaved(
          now: DateTime(2026, 7, 22),
        ),
        isNull,
      );
    }
  });

  test('保存纪念车票后仅主动提示一次分享', () async {
    final now = DateTime(2026, 7, 22);
    expect(
      await EngagementPromptService.recordEvent(
        EngagementPromptEvent.ticketImageSaved,
        now: now,
      ),
      EngagementPromptKind.share,
    );
    expect(
      await EngagementPromptService.recordEvent(
        EngagementPromptEvent.ticketImageSaved,
        now: now.add(const Duration(days: 15)),
      ),
      isNull,
    );
  });

  test('导出提示与其它场景共享冷却时间', () async {
    final now = DateTime(2026, 7, 22);
    expect(
      await EngagementPromptService.recordEvent(
        EngagementPromptEvent.ticketImageSaved,
        now: now,
      ),
      EngagementPromptKind.share,
    );
    expect(
      await EngagementPromptService.recordEvent(
        EngagementPromptEvent.excelExported,
        now: now,
      ),
      isNull,
    );
    expect(
      await EngagementPromptService.recordEvent(
        EngagementPromptEvent.excelExported,
        now: now.add(const Duration(days: 15)),
      ),
      EngagementPromptKind.donate,
    );
  });

  test('查看成就并解锁十项后提示分享', () async {
    final now = DateTime(2026, 7, 22);

    expect(
      await EngagementPromptService.recordAchievementViewed(9, now: now),
      isNull,
    );
    expect(
      await EngagementPromptService.recordAchievementViewed(10, now: now),
      EngagementPromptKind.share,
    );
    expect(
      await EngagementPromptService.recordAchievementViewed(
        12,
        now: now.add(const Duration(days: 15)),
      ),
      isNull,
    );
  });

  test('成就提示在冷却期内不消耗一次机会', () async {
    final now = DateTime(2026, 7, 22);
    expect(
      await EngagementPromptService.recordEvent(
        EngagementPromptEvent.ticketImageSaved,
        now: now,
      ),
      EngagementPromptKind.share,
    );
    expect(
      await EngagementPromptService.recordAchievementViewed(10, now: now),
      isNull,
    );
    expect(
      await EngagementPromptService.recordAchievementViewed(
        10,
        now: now.add(const Duration(days: 15)),
      ),
      EngagementPromptKind.share,
    );
  });
}
