import 'package:shared_preferences/shared_preferences.dart';

enum EngagementPromptKind { share, donate }

enum EngagementPromptEvent {
  tripSaved,
  ticketImageSaved,
  excelExported,
  achievementMilestoneViewed,
}

class EngagementPromptService {
  EngagementPromptService._();

  static const websiteUrl = 'https://www.raillog.top/';
  static const websiteShareText =
      '用「轨记 RailLog」记录每一段铁路旅程，收藏车票、统计里程、解锁成就。来看看：\n$websiteUrl';
  static const donationUrl = 'https://afdian.com/a/CRSim';
  static const achievementPromptThreshold = 10;

  static const _saveCountKey = 'engagement_prompt_save_count';
  static const _lastPromptSaveCountKey =
      'engagement_prompt_last_prompt_save_count';
  static const _lastPromptAtKey = 'engagement_prompt_last_prompt_at';
  static const _nextPromptKindKey = 'engagement_prompt_next_kind';
  static const _disabledKey = 'engagement_prompt_disabled';
  static const _ticketImagePromptedKey =
      'engagement_prompt_ticket_image_prompted';
  static const _excelExportPromptedKey =
      'engagement_prompt_excel_export_prompted';
  static const _achievementPromptedKey =
      'engagement_prompt_achievement_prompted';

  static const _firstPromptSaveCount = 5;
  static const _minimumSavesBetweenPrompts = 10;
  static const _minimumPromptInterval = Duration(days: 14);

  static Future<EngagementPromptKind?> recordTripSaved({DateTime? now}) async {
    return recordEvent(EngagementPromptEvent.tripSaved, now: now);
  }

  static Future<EngagementPromptKind?> recordAchievementViewed(
    int unlockedCount, {
    DateTime? now,
  }) async {
    if (unlockedCount < achievementPromptThreshold) return null;
    return recordEvent(
      EngagementPromptEvent.achievementMilestoneViewed,
      now: now,
    );
  }

  static Future<EngagementPromptKind?> recordEvent(
    EngagementPromptEvent event, {
    DateTime? now,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_disabledKey) ?? false) return null;

    final saveCount = event == EngagementPromptEvent.tripSaved
        ? (preferences.getInt(_saveCountKey) ?? 0) + 1
        : preferences.getInt(_saveCountKey) ?? 0;
    if (event == EngagementPromptEvent.tripSaved) {
      await preferences.setInt(_saveCountKey, saveCount);
    }

    final kind = switch (event) {
      EngagementPromptEvent.tripSaved => _tripSavePromptKind(
        preferences,
        saveCount,
      ),
      EngagementPromptEvent.ticketImageSaved =>
        preferences.getBool(_ticketImagePromptedKey) ?? false
            ? null
            : EngagementPromptKind.share,
      EngagementPromptEvent.excelExported =>
        preferences.getBool(_excelExportPromptedKey) ?? false
            ? null
            : EngagementPromptKind.donate,
      EngagementPromptEvent.achievementMilestoneViewed =>
        preferences.getBool(_achievementPromptedKey) ?? false
            ? null
            : EngagementPromptKind.share,
    };
    if (kind == null) return null;

    final currentTime = now ?? DateTime.now();
    final lastPromptAt = preferences.getInt(_lastPromptAtKey);
    if (lastPromptAt != null &&
        currentTime.difference(
              DateTime.fromMillisecondsSinceEpoch(lastPromptAt),
            ) <
            _minimumPromptInterval) {
      return null;
    }

    await preferences.setInt(_lastPromptSaveCountKey, saveCount);
    await preferences.setInt(
      _lastPromptAtKey,
      currentTime.millisecondsSinceEpoch,
    );
    await preferences.setInt(
      _nextPromptKindKey,
      kind == EngagementPromptKind.share ? 1 : 0,
    );
    if (event == EngagementPromptEvent.ticketImageSaved) {
      await preferences.setBool(_ticketImagePromptedKey, true);
    } else if (event == EngagementPromptEvent.excelExported) {
      await preferences.setBool(_excelExportPromptedKey, true);
    } else if (event == EngagementPromptEvent.achievementMilestoneViewed) {
      await preferences.setBool(_achievementPromptedKey, true);
    }
    return kind;
  }

  static EngagementPromptKind? _tripSavePromptKind(
    SharedPreferences preferences,
    int saveCount,
  ) {
    final lastPromptSaveCount =
        preferences.getInt(_lastPromptSaveCountKey) ?? 0;
    final requiredSaveCount = lastPromptSaveCount == 0
        ? _firstPromptSaveCount
        : lastPromptSaveCount + _minimumSavesBetweenPrompts;
    if (saveCount < requiredSaveCount) return null;
    return preferences.getInt(_nextPromptKindKey) == 1
        ? EngagementPromptKind.donate
        : EngagementPromptKind.share;
  }

  static Future<void> disable() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_disabledKey, true);
  }
}
