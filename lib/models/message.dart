import 'package:intl/intl.dart';

class Message {
  final String id; // <-- String
  final String senderId; // <-- String
  final String receiverId; // <-- String
  final String messageText;
  final DateTime sentAt;
  final bool isRead;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.messageText,
    required this.sentAt,
    required this.isRead,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      receiverId: json['receiverId'] as String? ?? '',
      messageText: json['messageText'] as String? ?? '',
      sentAt: json['sentAt'] != null
          ? DateTime.tryParse(json['sentAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'messageText': messageText,
      'sentAt': sentAt.toUtc().toIso8601String(),
      'isRead': isRead,
    };
  }

  String get time => DateFormat('HH:mm').format(sentAt);
}