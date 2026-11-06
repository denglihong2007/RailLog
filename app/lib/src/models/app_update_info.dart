class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.tagName,
    required this.name,
    required this.publishedAt,
    required this.releaseNotes,
    required this.releaseUrl,
    required this.windowsDownloadUrl,
    required this.androidDownloadUrl,
    required this.windowsDomesticDownloadUrl,
    required this.downloadPageUrl,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
    version: json['version'] as String,
    tagName: json['tagName'] as String,
    name: json['name'] as String,
    publishedAt: DateTime.parse(json['publishedAt'] as String),
    releaseNotes: json['releaseNotes'] as String?,
    releaseUrl: json['releaseUrl'] as String,
    windowsDownloadUrl: json['windowsDownloadUrl'] as String?,
    androidDownloadUrl: json['androidDownloadUrl'] as String?,
    windowsDomesticDownloadUrl: json['windowsDomesticDownloadUrl'] as String?,
    downloadPageUrl: json['downloadPageUrl'] as String,
  );

  final String version;
  final String tagName;
  final String name;
  final DateTime publishedAt;
  final String? releaseNotes;
  final String releaseUrl;
  final String? windowsDownloadUrl;
  final String? androidDownloadUrl;
  final String? windowsDomesticDownloadUrl;
  final String downloadPageUrl;
}
