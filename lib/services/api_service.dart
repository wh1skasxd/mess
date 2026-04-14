import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';
import '../models/message.dart';

class ApiService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

// ==========================================
  // ☁️ ЗАГРУЗКА ВИДЕО В CLOUDINARY
  // ==========================================
  Future<String?> uploadVideoToCloudinary(File videoFile) async {
    try {
      // Твое личное облако Cloudinary
      final url = Uri.parse('https://api.cloudinary.com/v1_1/dip4kum0k/video/upload');
      
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = 'meowly_video' // Твой открытый пресет
        ..files.add(await http.MultipartFile.fromPath('file', videoFile.path));

      print('🚀 Начинаю загрузку видео в облако...');
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonMap = jsonDecode(responseData);

      if (response.statusCode == 200) {
        print('✅ Видео успешно загружено!');
        return jsonMap['secure_url']; // Возвращаем готовую ссылку на видео!
      } else {
        print('❌ Ошибка Cloudinary: ${jsonMap['error']['message']}');
        return null;
      }
    } catch (e) {
      print('❌ Критическая ошибка при загрузке видео: $e');
      return null;
    }
  }

// --- МЕТОД УДАЛЕНИЯ ЧАТА (ФИНАЛЬНЫЙ) ---
  Future<bool> deleteChat(String currentUserId, String otherUserId, bool deleteForBoth) async {
    try {
      // 1. Формируем правильный ID чата (как у тебя в базе: id1_id2)
      // Во Flutter ID обычно сортируются по алфавиту, чтобы у обоих пользователей папка называлась одинаково
      List<String> ids = [currentUserId, otherUserId];
      ids.sort(); 
      String chatId = ids.join('_'); 

      // 2. Идем в нужную папку: коллекция chats -> наш чат -> подколлекция messages
      final messagesQuery = await _db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      // 3. Проходимся по всем найденным сообщениям
      for (var doc in messagesQuery.docs) {
        if (deleteForBoth) {
          // УДАЛИТЬ У ОБОИХ: стираем документ сообщения насовсем
          await doc.reference.delete();
        } else {
          // УДАЛИТЬ ТОЛЬКО У СЕБЯ:
          // Добавляем твой ID в список тех, кто удалил это сообщение
          await doc.reference.update({
            'deletedBy': FieldValue.arrayUnion([currentUserId])
          });
        }
      }
      final chatRef = _db.collection('chats').doc(chatId);
      
      if (deleteForBoth) {
        // Если удаляем у обоих: сносим саму папку чата в корзину
        await chatRef.delete();
      } else {
        // Если только у себя: вешаем на папку ярлык, что ты её скрыла
        // (используем set с merge, чтобы не сломать документ, если он полупустой)
        await chatRef.set({
          'deletedBy': FieldValue.arrayUnion([currentUserId])
        }, SetOptions(merge: true));
      }

      print('Успешно удалено сообщений: ${messagesQuery.docs.length}');
      return true; 
      
    } catch (e) {
      print('Ошибка при удалении чата в Firebase: $e');
      return false;
    }
  }

  // --- МАГИЧЕСКАЯ ФУНКЦИЯ ОТПРАВКИ ПУШЕЙ ---
  Future<void> sendPushNotification(String targetUserId, String senderName, String messageText) async {
    try {
      // 1. Ищем токен получателя в базе данных
      final userDoc = await _db.collection('users').doc(targetUserId).get();
      if (!userDoc.exists) return; // Если пользователя нет, отмена
      
      final targetToken = userDoc.data()?['fcmToken'];
      if (targetToken == null || targetToken.isEmpty) {
        print('У пользователя $targetUserId нет токена, пуш не отправлен.');
        return;
      }

     // 2. Достаем наш секретный ключ из папки assets
      final jsonString = await rootBundle.loadString('assets/service_account.json');
      final credentials = ServiceAccountCredentials.fromJson(jsonString);
      
      // Читаем JSON напрямую, чтобы вытащить ID проекта (это самый надежный способ!)
      final Map<String, dynamic> keyMap = jsonDecode(jsonString);
      final projectId = keyMap['project_id']; 

      // 3. Получаем временный пропуск от Google
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await clientViaServiceAccount(credentials, scopes);

      // 4. Формируем красивое уведомление
      final url = 'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';
      
      // Скрываем текст, если это фото или голосовое
      String bodyText = messageText;
      if (messageText == '📸 Фото' || messageText == '🎤 Голосовое сообщение') {
        bodyText = messageText; 
      }

      final message = {
        'message': {
          'token': targetToken,
          'notification': {
            'title': senderName,
            'body': bodyText,
          },
          // --- МАГИЯ ДЛЯ АНДРОИДА (Всплывашка + Звук) ---
          'android': {
            'priority': 'high', // Заставляет пуш выпрыгнуть сверху!
            'notification': {
              'channel_id': 'meowly_channel_v2', // <--- УКАЗЫВАЕМ НАШ НОВЫЙ КАНАЛ
              'sound': 'meow_sound',             // <--- ИМЯ ЗВУКА БЕЗ .mp3
            }
          },
          // --- МАГИЯ ДЛЯ АЙФОНА (На будущее) ---
          'apns': {
            'payload': {
              'aps': {
                'sound': 'meow_sound.mp3', // <--- ТУТ НУЖНО С РАСШИРЕНИЕМ .mp3
              }
            }
          }
        }
      };

      // 5. Отправляем письмо!
      final response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(message),
      );

      if (response.statusCode == 200) {
        print('✅ Ура! Пуш успешно улетел на телефон собеседника!');
      } else {
        print('❌ Ошибка отправки пуша: ${response.body}');
      }
      
      client.close(); // Закрываем соединение
    } catch (e) {
      print('❌ Критическая ошибка в sendPushNotification: $e');
    }
  }

  // --- МЕТОД БЛОКИРОВКИ / РАЗБЛОКИРОВКИ ---
  Future<void> toggleBlockUser(String currentUserId, String targetUserId, bool isBlocked) async {
    try {
      // Обращаемся к ТВОЕМУ документу в коллекции пользователей
      final currentUserRef = _db.collection('users').doc(currentUserId);

      if (isBlocked) {
        // Если уже в блоке -> РАЗБЛОКИРОВАТЬ (удаляем ID из массива)
        await currentUserRef.update({
          'blockedUsers': FieldValue.arrayRemove([targetUserId])
        });
      } else {
        // Если не в блоке -> ЗАБЛОКИРОВАТЬ (добавляем ID в массив)
        await currentUserRef.update({
          'blockedUsers': FieldValue.arrayUnion([targetUserId])
        });
      }
    } catch (e) {
      print('Ошибка при блокировке: $e');
    }
  }

  Future<List<UserModel>> getUsers() async {
    try {
      final snapshot = await _db.collection('users').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return UserModel.fromJson(data);
      }).toList();
    } catch (e) { print('Ошибка: $e'); return []; }
  }

  Future<List<String>> getActiveChatIds(String currentUserId) async {
    try {
      final snapshot = await _db.collection('users').doc(currentUserId).collection('active_chats').get();
      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) { return []; }
  }

  String _getChatId(String user1, String user2) {
    List<String> ids = [user1, user2];
    ids.sort();
    return ids.join('_');
  }

  Future<List<Message>> getMessages(String currentUserId, String otherUserId) async {
    final String chatId = _getChatId(currentUserId, otherUserId);
    try {
      final snapshot = await _db.collection('chats').doc(chatId).collection('messages').orderBy('sentAt').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Message.fromJson(data);
      }).where((msg) => !msg.deletedBy.contains(currentUserId)).toList(); 
    } catch (e) { return []; }
  }
  // --- МЕТОД РЕДАКТИРОВАНИЯ СООБЩЕНИЯ ---
  Future<bool> editMessage(String currentUserId, String targetUserId, String messageId, String newText) async {
    try {
      // Формируем общий ID чата (как ты делаешь в других методах)
      List<String> ids = [currentUserId, targetUserId];
      ids.sort();
      String chatId = ids.join('_');

      // Обновляем документ сообщения
      await _db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'messageText': newText,
        'isEdited': true, // Ставим пометку, что текст был изменен
      });

      return true;
    } catch (e) {
      print('Ошибка при редактировании сообщения: $e');
      return false;
    }
  }
  // --- СОХРАНЕНИЕ FCM ТОКЕНА ПОЛЬЗОВАТЕЛЯ ---
  Future<void> saveUserToken(String userId, String token) async {
    try {
      await _db.collection('users').doc(userId).update({
        'fcmToken': token,
      });
      print('✅ Токен успешно сохранен в базу для пользователя $userId');
    } catch (e) {
      print('Ошибка при сохранении токена: $e');
    }
  }

  Future<bool> deleteMessage(String currentUserId, String otherUserId, String messageId, bool forEveryone) async {
    final String chatId = _getChatId(currentUserId, otherUserId);
    try {
      if (forEveryone) {
        await _db.collection('chats').doc(chatId).collection('messages').doc(messageId).delete();
      } else {
        await _db.collection('chats').doc(chatId).collection('messages').doc(messageId).update({'deletedBy': FieldValue.arrayUnion([currentUserId])});
      }
      return true;
    } catch (e) { return false; }
  }

 // ДОБАВИЛИ imageUrls В ПАРАМЕТРЫ
  Future<bool> sendMessage(String senderId, String receiverId, String text, {String? replyToId, String? imageBase64, String? audioBase64, List<String>? imagesBase64, String? videoUrl, List<String>? imageUrls}) async {
    final String chatId = _getChatId(senderId, receiverId);
    try {
      await _db.collection('chats').doc(chatId).collection('messages').add({
        'senderId': senderId,
        'receiverId': receiverId,
        'messageText': text,
        'sentAt': DateTime.now().toUtc().toIso8601String(),
        'isRead': false,
        if (replyToId != null) 'replyToMessageId': replyToId,
        if (imageBase64 != null) 'imageBase64': imageBase64,
        if (imagesBase64 != null && imagesBase64.isNotEmpty) 'imagesBase64': imagesBase64,
        if (audioBase64 != null) 'audioBase64': audioBase64,
        if (videoUrl != null) 'videoUrl': videoUrl,
        if (imageUrls != null && imageUrls.isNotEmpty) 'imageUrls': imageUrls, // <--- СОХРАНЯЕМ ССЫЛКИ В БАЗУ
      });
      await _db.collection('users').doc(senderId).collection('active_chats').doc(receiverId).set({'active': true});
      await _db.collection('users').doc(receiverId).collection('active_chats').doc(senderId).set({'active': true});
      return true;
    } catch (e) { return false; }
  }


  Future<void> saveUser(UserModel user) async { await _db.collection('users').doc(user.id).set(user.toJson()); }
  Future<void> updateUserPresence(String userId, bool isOnline) async { try { await _db.collection('users').doc(userId).update({'isOnline': isOnline, 'lastSeen': DateTime.now().toUtc().toIso8601String()}); } catch (e) {} }
  Future<void> setTypingStatus(String currentUserId, String otherUserId, bool isTyping) async { final String chatId = _getChatId(currentUserId, otherUserId); try { await _db.collection('chats').doc(chatId).set({'typing_$currentUserId': isTyping}, SetOptions(merge: true)); } catch (e) {} }
  Stream<bool> getTypingStatus(String currentUserId, String otherUserId) { final String chatId = _getChatId(currentUserId, otherUserId); return _db.collection('chats').doc(chatId).snapshots().map((doc) { if (doc.exists && doc.data() != null) return doc.data()!['typing_$otherUserId'] ?? false; return false; }); }
  Stream<int> getUnreadCountStream(String currentUserId, String otherUserId) { final String chatId = _getChatId(currentUserId, otherUserId); return _db.collection('chats').doc(chatId).collection('messages').where('receiverId', isEqualTo: currentUserId).where('isRead', isEqualTo: false).snapshots().map((snapshot) => snapshot.docs.length); }
  Future<void> markMessagesAsRead(String currentUserId, String otherUserId) async { final String chatId = _getChatId(currentUserId, otherUserId); try { final snapshot = await _db.collection('chats').doc(chatId).collection('messages').where('receiverId', isEqualTo: currentUserId).where('isRead', isEqualTo: false).get(); WriteBatch batch = _db.batch(); for (var doc in snapshot.docs) { batch.update(doc.reference, {'isRead': true}); } await batch.commit(); } catch (e) {} }
// --- МЕТОД УДАЛЕНИЯ АККАУНТА ---
  Future<bool> deleteAccount(String userId) async {
    try {
      // 1. Удаляем документ пользователя из базы данных Firestore (коллекция users)
      var _db;
      await _db.collection('users').doc(userId).delete();

      // 2. Удаляем саму учетную запись из Firebase Authentication
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await currentUser.delete();
      }

      return true;
    } catch (e) {
      print('Ошибка при удалении аккаунта: $e');
      // ВАЖНО: Firebase в целях безопасности иногда требует недавнего входа (requires-recent-login),
      // чтобы удалить аккаунт. Если токен устарел, метод может вернуть ошибку.
      return false;
    }
  }
  // --- МЕТОД ЗАКРЕПА СООБЩЕНИЯ ---
  Future<bool> togglePinMessage(String currentUserId, String otherUserId, String messageId, bool isPinned) async {
    final String chatId = _getChatId(currentUserId, otherUserId);
    try {
      await _db.collection('chats').doc(chatId).collection('messages').doc(messageId).update({
        'isPinned': isPinned,
      });
      return true;
    } catch (e) {
      print('Ошибка при закреплении: $e');
      return false;
    }
  }
  // ==========================================
  // ☁️ ЗАГРУЗКА ФОТО В CLOUDINARY (HD КАЧЕСТВО)
  // ==========================================
  Future<String?> uploadImageToCloudinary(File imageFile) async {
    try {
      // Заметь: тут в ссылке слово /image/upload, а не video!
      final url = Uri.parse('https://api.cloudinary.com/v1_1/dip4kum0k/image/upload');
      
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = 'meowly_video' // Твой пресет отлично скушает и фото
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonMap = jsonDecode(responseData);

      if (response.statusCode == 200) {
        return jsonMap['secure_url']; // Возвращаем ссылку на HD фото!
      }
      return null;
    } catch (e) {
      print('❌ Ошибка загрузки фото: $e');
      return null;
    }
  }
}


   