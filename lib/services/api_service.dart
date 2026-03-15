import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import '../models/message.dart';

class ApiService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. Получаем список всех пользователей (для поиска)
  Future<List<UserModel>> getUsers() async {
    try {
      final snapshot = await _db.collection('users').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return UserModel.fromJson(data);
      }).toList();
    } catch (e) {
      print('Ошибка получения пользователей: $e');
      return [];
    }
  }

  // НОВАЯ МАГИЯ: Получаем ID только тех людей, с кем у нас есть чат
  Future<List<String>> getActiveChatIds(String currentUserId) async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(currentUserId)
          .collection('active_chats') // Смотрим в секретную папку контактов
          .get();
      return snapshot.docs.map((doc) => doc.id).toList(); // Возвращаем только ID
    } catch (e) {
      print('Ошибка получения активных чатов: $e');
      return [];
    }
  }

  String _getChatId(String user1, String user2) {
    List<String> ids = [user1, user2];
    ids.sort();
    return ids.join('_');
  }

  // 2. Получаем историю переписки
  Future<List<Message>> getMessages(String currentUserId, String otherUserId) async {
    final String chatId = _getChatId(currentUserId, otherUserId);
    try {
      final snapshot = await _db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('sentAt')
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Message.fromJson(data);
      }).toList();
    } catch (e) {
      print('Ошибка получения сообщений: $e');
      return [];
    }
  }

  // 3. Отправляем сообщение
  Future<bool> sendMessage(String senderId, String receiverId, String text) async {
    final String chatId = _getChatId(senderId, receiverId);
    
    try {
      // Сохраняем само сообщение
      await _db.collection('chats').doc(chatId).collection('messages').add({
        'senderId': senderId,
        'receiverId': receiverId,
        'messageText': text,
        'sentAt': DateTime.now().toUtc().toIso8601String(),
        'isRead': false,
      });

      // НОВАЯ МАГИЯ: Добавляем пользователей друг другу в список "Активных чатов"
      await _db.collection('users').doc(senderId).collection('active_chats').doc(receiverId).set({'active': true});
      await _db.collection('users').doc(receiverId).collection('active_chats').doc(senderId).set({'active': true});

      return true;
    } catch (e) {
      print('Ошибка отправки сообщения: $e');
      return false;
    }
  }

  // 4. Сохраняем нового пользователя
  Future<void> saveUser(UserModel user) async {
    await _db.collection('users').doc(user.id).set(user.toJson());
  }
  // --- НОВАЯ ФУНКЦИЯ: Обновление статуса в сети ---
  Future<void> updateUserPresence(String userId, bool isOnline) async {
    try {
      await _db.collection('users').doc(userId).update({
        'isOnline': isOnline,
        'lastSeen': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      print('Ошибка обновления статуса: $e');
    }
  }
}
