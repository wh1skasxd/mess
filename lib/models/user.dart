class UserModel {
  final String id;
  final String username;
  final String? avatarBase64;
  final String? phoneNumber;
  final bool isActive;
  final DateTime? createdAt;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? bio; // <-- НОВОЕ ПОЛЕ: О себе

  UserModel({
    required this.id,
    required this.username,
    this.avatarBase64,
    this.phoneNumber,
    required this.isActive,
    this.createdAt,
    this.isOnline = false,
    this.lastSeen,
    this.bio, // <-- ДОБАВИЛИ СЮДА
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      username: json['username'] ?? 'Без имени',
      avatarBase64: json['avatarBase64'],
      phoneNumber: json['phoneNumber'],
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
      isOnline: json['isOnline'] ?? false,
      lastSeen: json['lastSeen'] != null ? DateTime.tryParse(json['lastSeen']) : null,
      bio: json['bio'], // <-- ЧИТАЕМ ИЗ БАЗЫ
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'avatarBase64': avatarBase64,
      'phoneNumber': phoneNumber,
      'isActive': isActive,
      'createdAt': createdAt?.toIso8601String(),
      'isOnline': isOnline,
      'lastSeen': lastSeen?.toIso8601String(),
      'bio': bio, // <-- СОХРАНЯЕМ В БАЗУ
    };
  }
}