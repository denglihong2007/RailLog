import 'dart:math';

import 'package:raillog/src/models/partner_application.dart';
import 'package:raillog/src/models/partner_advertisement.dart';
import 'package:raillog/src/services/api_client.dart';

class PartnerApplicationService {
  PartnerApplicationService._();

  static Future<List<PartnerApplication>> fetch() async {
    final response = await ApiClient.instance.dio.get<List<dynamic>>(
      '/api/partners',
    );
    return [
      for (final item in response.data ?? const [])
        if (item is Map)
          PartnerApplication.fromJson(
            Map<String, dynamic>.from(item),
            baseUrl: ApiClient.baseUrl,
          ),
    ];
  }

  static Future<PartnerAdvertisement?> fetchAdvertisement() async {
    final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
      '/api/partners/advertisements',
    );
    final config = PartnerAdvertisementConfig.fromJson(
      response.data ?? const {},
    );
    final hiddenWeight = max(0, config.hiddenWeight);
    final candidates = <PartnerAdvertisement>[
      for (final item in config.advertisements)
        if (item.weight > 0 && item.text.trim().isNotEmpty) item,
      for (final announcement in config.announcements)
        if (announcement.weight > 0 && announcement.text.trim().isNotEmpty)
          PartnerAdvertisement(
            partnerId: '',
            text: announcement.text,
            weight: announcement.weight,
            isAnnouncement: true,
          ),
    ];
    final totalWeight = candidates.fold<int>(
      hiddenWeight,
      (total, item) => total + item.weight,
    );
    if (totalWeight <= 0) return null;

    var roll = Random().nextInt(totalWeight);
    if (roll < hiddenWeight) return null;
    roll -= hiddenWeight;
    for (final candidate in candidates) {
      if (roll < candidate.weight) return candidate;
      roll -= candidate.weight;
    }
    return null;
  }
}
