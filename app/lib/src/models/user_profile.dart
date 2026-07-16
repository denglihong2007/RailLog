class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    required this.showEmailOnProfile,
  });

  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final bool showEmailOnProfile;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String,
    avatarUrl: json['avatarUrl'] as String?,
    bio: json['bio'] as String?,
    showEmailOnProfile: json['showEmailOnProfile'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'bio': bio,
    'showEmailOnProfile': showEmailOnProfile,
  };
}
