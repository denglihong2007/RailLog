class PartnerAdvertisement {
  const PartnerAdvertisement({
    required this.partnerId,
    required this.text,
    required this.weight,
  });

  final String partnerId;
  final String text;
  final int weight;

  factory PartnerAdvertisement.fromJson(Map<String, dynamic> json) =>
      PartnerAdvertisement(
        partnerId: json['partnerId'] as String? ?? '',
        text: json['text'] as String? ?? '',
        weight: (json['weight'] as num?)?.toInt() ?? 0,
      );
}

class PartnerAdvertisementConfig {
  const PartnerAdvertisementConfig({
    required this.hiddenWeight,
    required this.advertisements,
  });

  final int hiddenWeight;
  final List<PartnerAdvertisement> advertisements;

  factory PartnerAdvertisementConfig.fromJson(Map<String, dynamic> json) {
    final items = json['advertisements'];
    return PartnerAdvertisementConfig(
      hiddenWeight: (json['hiddenWeight'] as num?)?.toInt() ?? 0,
      advertisements: [
        if (items is List)
          for (final item in items)
            if (item is Map)
              PartnerAdvertisement.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }
}
