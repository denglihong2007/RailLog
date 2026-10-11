import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/services/achievement_unlock_notifier.dart';

void main() {
  // 单例跨用例共享，每个用例都要从「没建立过基线」的状态开始。
  setUp(AchievementUnlockNotifier.instance.reset);

  test('首次 ingest 只建立基线，不庆祝', () {
    final notifier = AchievementUnlockNotifier.instance;

    notifier.ingest([_achievement('a', unlocked: true)]);

    expect(notifier.pending, isEmpty);
  });

  test('基线之后新出现的解锁会被记为待庆祝', () {
    final notifier = AchievementUnlockNotifier.instance;
    notifier.ingest([
      _achievement('a', unlocked: true),
      _achievement('b'),
    ]);

    notifier.ingest([
      _achievement('a', unlocked: true),
      _achievement('b', unlocked: true),
    ]);

    expect(notifier.pending.map((item) => item.id), ['b']);
  });

  test('重复 ingest 同一批解锁不会反复庆祝', () {
    final notifier = AchievementUnlockNotifier.instance;
    notifier.ingest([_achievement('a')]);
    notifier.ingest([_achievement('a', unlocked: true)]);
    notifier.clearPending();

    notifier.ingest([_achievement('a', unlocked: true)]);

    expect(notifier.pending, isEmpty);
  });

  test('clearPending 之后不再有待庆祝项', () {
    final notifier = AchievementUnlockNotifier.instance;
    notifier.ingest([_achievement('a')]);
    notifier.ingest([_achievement('a', unlocked: true)]);
    expect(notifier.pending, isNotEmpty);

    notifier.clearPending();

    expect(notifier.pending, isEmpty);
  });

  test('reset 之后重新建立基线，不把已有解锁当成刚解锁', () {
    final notifier = AchievementUnlockNotifier.instance;
    notifier.ingest([_achievement('a')]);
    notifier.reset();

    notifier.ingest([_achievement('a', unlocked: true)]);

    expect(notifier.pending, isEmpty);
  });
}

DashboardAchievement _achievement(String id, {bool unlocked = false}) =>
    DashboardAchievement(
      id: id,
      category: AchievementCategory.milestones,
      iconKey: 'flag_outlined',
      title: id,
      requirement: '达成要求',
      unlocked: unlocked,
      triggerTripId: null,
      unlockedUserCount: 0,
      totalUserCount: 0,
      experience: 0,
      hidden: false,
      narrativeNote: null,
    );
