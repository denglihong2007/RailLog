import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:raillog/src/models/app_update_info.dart';
import 'package:raillog/src/services/api_client.dart';

const _storageBaseUrl = 'https://raillog.cn-nb2.rains3.com';
const _githubReleaseBaseUrl =
    'https://github.com/denglihong2007/RailLog/releases/download';
const _windowsStoreUrl = 'https://apps.microsoft.com/detail/9P2XGJRHLZXS';

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

  /// GitHub 下载：优先用 API 给出的当前平台产物，其余平台按 Release 文件名拼接。
  static String? githubUrlForCurrentPlatform(AppUpdateInfo update) {
    final preferred = switch (defaultTargetPlatform) {
      TargetPlatform.windows => update.windowsDownloadUrl,
      TargetPlatform.android => update.androidDownloadUrl,
      _ => null,
    };
    final suffix = _assetSuffixForCurrentPlatform();
    final version = _versionNumber(update);
    final constructed = suffix == null
        ? null
        : '$_githubReleaseBaseUrl/v$version/${_assetName(version, suffix)}';
    return _firstNonEmpty([preferred, constructed, update.releaseUrl]);
  }

  /// 官方下载：Windows 走微软商店，其余平台走对象存储里的构建产物。
  static String? officialDownloadUrlForCurrentPlatform(AppUpdateInfo update) {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return _firstNonEmpty([
        update.windowsDomesticDownloadUrl,
        _windowsStoreUrl,
      ]);
    }
    final suffix = _assetSuffixForCurrentPlatform();
    if (suffix == null) return _firstNonEmpty([update.downloadPageUrl]);
    final version = _versionNumber(update);
    return '$_storageBaseUrl/v$version/${_assetName(version, suffix)}';
  }

  static String? _assetSuffixForCurrentPlatform() =>
      switch (defaultTargetPlatform) {
        TargetPlatform.windows => 'windows-x64.zip',
        TargetPlatform.android => 'android-arm64-v8a.apk',
        TargetPlatform.macOS => 'macos-arm64.zip',
        TargetPlatform.linux => 'linux-x64.tar.gz',
        TargetPlatform.iOS => 'ios.ipa',
        _ => null,
      };

  static String _versionNumber(AppUpdateInfo update) {
    final value = update.version.trim();
    return value.startsWith('v') || value.startsWith('V')
        ? value.substring(1)
        : value;
  }

  static String _assetName(String version, String suffix) =>
      'raillog-v$version-$suffix';

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
