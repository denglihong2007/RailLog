class PartnerAdvertisement {
  const PartnerAdvertisement({
    required this.partnerId,
    required this.text,
    required this.weight,
    this.isAnnouncement = false,
  });

  final String partnerId;
  final String text;
  final int weight;

  /// 系统公告与合作伙伴推荐共用主页横幅，但并不引导到「合作应用」页。
  final bool isAnnouncement;

  factory PartnerAdvertisement.fromJson(Map<String, dynamic> json) =>
      PartnerAdvertisement(
        partnerId: json['partnerId'] as String? ?? '',
        text: json['text'] as String? ?? '',
        weight: (json['weight'] as num?)?.toInt() ?? 0,
      );
}

class SystemAnnouncement {
  const SystemAnnouncement({required this.text, required this.weight});

  final String text;
  final int weight;

  factory SystemAnnouncement.fromJson(Map<String, dynamic> json) =>
      SystemAnnouncement(
        text: json['text'] as String? ?? '',
        weight: (json['weight'] as num?)?.toInt() ?? 0,
      );
}

class PartnerAdvertisementConfig {
  const PartnerAdvertisementConfig({
    required this.hiddenWeight,
    required this.advertisements,
    required this.announcements,
  });

  final int hiddenWeight;
  final List<PartnerAdvertisement> advertisements;
  final List<SystemAnnouncement> announcements;

  factory PartnerAdvertisementConfig.fromJson(Map<String, dynamic> json) {
    final items = json['advertisements'];
    final announcementItems = json['announcements'];
    return PartnerAdvertisementConfig(
      hiddenWeight: (json['hiddenWeight'] as num?)?.toInt() ?? 0,
      advertisements: [
        if (items is List)
          for (final item in items)
            if (item is Map)
              PartnerAdvertisement.fromJson(Map<String, dynamic>.from(item)),
      ],
      announcements: [
        if (announcementItems is List)
          for (final item in announcementItems)
            if (item is Map)
              SystemAnnouncement.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }
}
