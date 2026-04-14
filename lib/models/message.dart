class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String messageText;
  final DateTime sentAt;
  final bool isRead;
  final List<String> deletedBy;
  final String? replyToMessageId;
  final String? imageBase64; // Старое поле для одиночных фото
  final List<String>? imagesBase64; // НОВОЕ ПОЛЕ: массив для альбомов
  final String? audioBase64;
  final String? videoUrl;
  final bool isPinned;
  final bool isEdited; // НОВОЕ ПОЛЕ
  final List<String>? imageUrls; // <--- НОВОЕ: Список ссылок на HD-фото

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.messageText,
    required this.sentAt,
    required this.isRead,
    required this.deletedBy,
    this.replyToMessageId,
    this.imageBase64,
    this.imagesBase64,
    this.audioBase64,
    this.videoUrl,
    this.isPinned = false, // По умолчанию сообщения не закреплены
    this.isEdited = false, // По умолчанию не изменено
    this.imageUrls, // <--- НОВОЕ
  });
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'messageText': messageText,
      'sentAt': sentAt.toUtc().toIso8601String(),
      'isRead': isRead,
      'deletedBy': deletedBy,
      'replyToMessageId': replyToMessageId,
      'imageBase64': imageBase64,
      'imagesBase64': imagesBase64,
      'audioBase64': audioBase64,
      'videoUrl': videoUrl,
      'isPinned': isPinned, // Теперь не будет красным
      'isEdited': isEdited,
      if (imageUrls != null && imageUrls!.isNotEmpty) 'imageUrls': imageUrls, // <--- НОВОЕ
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      isPinned: json['isPinned'] ?? false,
      id: json['id'] ?? '',
      senderId: json['senderId'] ?? '',
      receiverId: json['receiverId'] ?? '',
      messageText: json['messageText'] ?? '',
      sentAt: json['sentAt'] != null ? DateTime.parse(json['sentAt']) : DateTime.now(),
      isRead: json['isRead'] ?? false,
      deletedBy: json['deletedBy'] != null ? List<String>.from(json['deletedBy']) : [],
      replyToMessageId: json['replyToMessageId'],
      imageBase64: json['imageBase64'],
      // Читаем массив фото из базы
      imagesBase64: json['imagesBase64'] != null ? List<String>.from(json['imagesBase64']) : null,
      audioBase64: json['audioBase64'],
      videoUrl: json['videoUrl'],
     imageUrls: json['imageUrls'] != null ? List<String>.from(json['imageUrls']) : null, // <--- НОВОЕ
    );
  }

  String get time {
    final localTime = sentAt.toLocal();
    return "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}";
  }
}