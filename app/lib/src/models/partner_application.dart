class PartnerApplication {
  const PartnerApplication({
    required this.id,
    required this.name,
    required this.title,
    required this.description,
    required this.websiteUrl,
    required this.posterUrl,
    required this.iconUrl,
  });

  final String id;
  final String name;
  final String title;
  final String description;
  final String websiteUrl;
  final String posterUrl;
  final String iconUrl;

  factory PartnerApplication.fromJson(
    Map<String, dynamic> json, {
    required String baseUrl,
  }) => PartnerApplication(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    websiteUrl: json['websiteUrl'] as String? ?? '',
    posterUrl: _resolveUrl(baseUrl, json['posterUrl'] as String?),
    iconUrl: _resolveUrl(baseUrl, json['iconUrl'] as String?),
  );
}

String _resolveUrl(String baseUrl, String? value) {
  final path = value?.trim() ?? '';
  if (path.isEmpty) return '';
  return Uri.parse(baseUrl).resolve(path).toString();
}
