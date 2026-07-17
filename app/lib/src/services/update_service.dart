import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:raillog/src/models/app_update_info.dart';
import 'package:raillog/src/services/api_client.dart';

class UpdateCheckResult {
  const UpdateCheckResult({required this.currentVersion, required this.latest});

  final String currentVersion;
  final AppUpdateInfo latest;

  bool get hasUpdate => compareAppVersions(latest.version, currentVersion) > 0;
}

class UpdateService {
  UpdateService._();

  static bool get supportsAutomaticChecks =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.android);

  static Future<UpdateCheckResult> check() async {
    try {
      final values = await Future.wait([PackageInfo.fromPlatform(), latest()]);
      final package = values[0] as PackageInfo;
      return UpdateCheckResult(
        currentVersion: package.version,
        latest: values[1] as AppUpdateInfo,
      );
    } on UpdateException {
      rethrow;
    } catch (error) {
      throw UpdateException(apiErrorMessage(error));
    }
  }

  static Future<AppUpdateInfo> latest() async {
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/updates/latest',
      );
      return AppUpdateInfo.fromJson(response.data!);
    } catch (error) {
      throw UpdateException(apiErrorMessage(error));
    }
  }

  static String? githubUrlForCurrentPlatform(AppUpdateInfo update) {
    final preferred = switch (defaultTargetPlatform) {
      TargetPlatform.windows => update.windowsDownloadUrl,
      TargetPlatform.android => update.androidDownloadUrl,
      _ => null,
    };
    return _firstNonEmpty([
      preferred,
      update.releaseUrl,
      update.windowsDownloadUrl,
      update.androidDownloadUrl,
    ]);
  }

  static String? domesticUrlForCurrentPlatform(AppUpdateInfo update) {
    final preferred = switch (defaultTargetPlatform) {
      TargetPlatform.windows => update.windowsDomesticDownloadUrl,
      TargetPlatform.android => update.androidDomesticDownloadUrl,
      _ => null,
    };
    return _firstNonEmpty([
      preferred,
      update.windowsDomesticDownloadUrl,
      update.androidDomesticDownloadUrl,
    ]);
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) return normalized;
    }
    return null;
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

int compareAppVersions(String left, String right) {
  final a = _ParsedVersion.parse(left);
  final b = _ParsedVersion.parse(right);
  final length = a.numbers.length > b.numbers.length
      ? a.numbers.length
      : b.numbers.length;
  for (var index = 0; index < length; index++) {
    final aValue = index < a.numbers.length ? a.numbers[index] : 0;
    final bValue = index < b.numbers.length ? b.numbers[index] : 0;
    if (aValue != bValue) return aValue.compareTo(bValue);
  }
  if (a.preRelease == null && b.preRelease != null) return 1;
  if (a.preRelease != null && b.preRelease == null) return -1;
  return (a.preRelease ?? '').compareTo(b.preRelease ?? '');
}

class _ParsedVersion {
  const _ParsedVersion(this.numbers, this.preRelease);

  factory _ParsedVersion.parse(String source) {
    var value = source.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    value = value.split('+').first;
    final separator = value.indexOf('-');
    final preRelease = separator < 0 ? null : value.substring(separator + 1);
    final stable = separator < 0 ? value : value.substring(0, separator);
    final numbers = stable
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
    return _ParsedVersion(numbers, preRelease);
  }

  final List<int> numbers;
  final String? preRelease;
}
