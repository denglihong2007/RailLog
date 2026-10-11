import 'package:flutter/foundation.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';

/// 记录「本次会话里第一次见到的解锁」，供成就页的庆祝动画取用。
///
/// 成就页在挂载时读一次 [pending]，取到就爆发一次彩带并立刻 [clearPending]，
/// 因此这里不需要谁去监听 —— [notifyListeners] 只是保留 ChangeNotifier 的语义，
/// 方便以后有别的地方想跟着一起庆祝。
class AchievementUnlockNotifier extends ChangeNotifier {
  AchievementUnlockNotifier._();

  static final AchievementUnlockNotifier instance =
      AchievementUnlockNotifier._();

  Set<String> _seen = <String>{};
  List<DashboardAchievement> _pending = const [];
  bool _primed = false;

  /// 本次拉取里「上次没见到、这次见到了」的成就。取走后请调用 [clearPending]，
  /// 否则离开成就页再进来会重放一次。
  List<DashboardAchievement> get pending => _pending;

  /// 每次 `AchievementService.fetchCurrent()` 拿到结果后调用。
  void ingest(List<DashboardAchievement> achievements) {
    final unlockedNow = <String>{
      for (final achievement in achievements)
        if (achievement.isUnlocked) achievement.id,
    };
    if (!_primed) {
      // 首次拉取只建立基线：否则冷启动会把所有历史解锁都庆祝一遍。
      _seen = unlockedNow;
      _primed = true;
      return;
    }
    final fresh = unlockedNow.difference(_seen);
    _seen = unlockedNow;
    if (fresh.isEmpty) return;
    _pending = achievements
        .where((achievement) => fresh.contains(achievement.id))
        .toList(growable: false);
    notifyListeners();
  }

  void clearPending() => _pending = const [];

  /// 会话结束时重置基线，避免把新账号的历史解锁当成「刚刚解锁」。
  void reset() {
    _seen = <String>{};
    _pending = const [];
    _primed = false;
  }
}
