class EntitySearchResult {
  const EntitySearchResult({
    required this.entityType,
    required this.entityKey,
    required this.tripCount,
  });

  factory EntitySearchResult.fromJson(Map<String, dynamic> json) =>
      EntitySearchResult(
        entityType: json['entityType'] as String,
        entityKey: json['entityKey'] as String,
        tripCount: (json['tripCount'] as num).toInt(),
      );

  final String entityType;
  final String entityKey;
  final int tripCount;
}

class UserSearchResult {
  const UserSearchResult({
    required this.id,
    required this.displayName,
    required this.tripCount,
    this.avatarUrl,
    this.bio,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) =>
      UserSearchResult(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        bio: json['bio'] as String?,
        tripCount: (json['tripCount'] as num).toInt(),
      );

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final int tripCount;
}
