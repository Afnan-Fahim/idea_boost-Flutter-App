class UserModel {
  final String id;
  String name;
  String email;
  String profileImage;
  String language;
  bool isPro;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.profileImage,
    required this.language,
    this.isPro = false,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      profileImage: map['profileImage'] ?? '',
      language: map['language'] ?? 'en',
      isPro: map['plan'] == 'pro',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'profileImage': profileImage,
      'language': language,
      'plan': isPro ? 'pro' : 'free',
    };
  }
}
