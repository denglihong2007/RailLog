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
    final advertisements = config.advertisements
        .where((item) => item.weight > 0 && item.text.trim().isNotEmpty)
        .toList(growable: false);
    final totalWeight = advertisements.fold<int>(
      hiddenWeight,
      (total, item) => total + item.weight,
    );
    if (totalWeight <= 0) return null;

    var roll = Random().nextInt(totalWeight);
    if (roll < hiddenWeight) return null;
    roll -= hiddenWeight;
    for (final advertisement in advertisements) {
      if (roll < advertisement.weight) return advertisement;
      roll -= advertisement.weight;
    }
    return null;
  }
}
