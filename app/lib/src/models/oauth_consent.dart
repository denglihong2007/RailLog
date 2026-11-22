class OAuthConsent {
  const OAuthConsent({
    required this.clientId,
    required this.name,
    required this.logoUrl,
    required this.scopes,
    required this.createdAt,
  });

  final String clientId;
  final String name;
  final String? logoUrl;
  final List<String> scopes;
  final DateTime createdAt;

  factory OAuthConsent.fromJson(Map<String, dynamic> json) => OAuthConsent(
    clientId: json['clientId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    logoUrl: json['logoUrl'] as String?,
    scopes: [
      for (final item in (json['scopes'] as List<dynamic>? ?? const []))
        if (item is String) item,
    ],
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );

  String get scopeLabel => scopes
      .map((scope) => scope == 'profile' ? '账号 ID、昵称和头像' : scope)
      .join('、');
}
