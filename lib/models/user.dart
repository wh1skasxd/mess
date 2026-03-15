class UserModel {
  final String id; 
  final String username;
  final String? phoneNumber;
  final String? avatarBase64; 
  final DateTime? createdAt;
  final bool isActive;
  
  // НОВЫЕ ПОЛЯ ДЛЯ СТАТУСА:
  final bool isOnline; 
  final DateTime? lastSeen;

  UserModel({
    required this.id,
    required this.username,
    this.phoneNumber,
    this.avatarBase64,
    this.createdAt,
    required this.isActive,
    this.isOnline = false, // По умолчанию не в сети
    this.lastSeen,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? '', 
      username: json['username'] as String? ?? 'unknown',
      phoneNumber: json['phoneNumber'] as String?,
      avatarBase64: json['avatarBase64'] as String?, 
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      isActive: json['isActive'] as bool? ?? true,
      // Читаем статус из базы
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (avatarBase64 != null) 'avatarBase64': avatarBase64, 
      if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
      'isActive': isActive,
      // Сохраняем статус
      'isOnline': isOnline,
      if (lastSeen != null) 'lastSeen': lastSeen!.toUtc().toIso8601String(),
    };
  }
}