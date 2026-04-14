import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/message.dart'; 
import 'chat_screen.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileScreen extends StatelessWidget {
  final UserModel user;
  final List<Message> chatMessages; 

  // Теперь профиль снова умеет принимать историю сообщений из чата!
  const UserProfileScreen({super.key, required this.user, this.chatMessages = const []});

  String _getStatusText(UserModel user) {
    if (user.isOnline) return 'В сети';
    if (user.lastSeen == null) return 'Был(а) недавно';
    final time = DateFormat('HH:mm').format(user.lastSeen!.toLocal());
    final date = DateFormat('dd.MM.yyyy').format(user.lastSeen!.toLocal());
    return 'Был(а) $date в $time';
  }

  @override
  Widget build(BuildContext context) {
    Widget buildAvatar() {
      if (user.avatarBase64 == null) return const Icon(Icons.person, size: 80, color: Colors.grey);
      try {
        final Uint8List bytes = base64Decode(user.avatarBase64!);
        return Image.memory(bytes, fit: BoxFit.cover, width: 150, height: 150);
      } catch (e) {
        return const Icon(Icons.error, size: 80, color: Colors.red);
      }
    }

    final bool hasBio = user.bio != null && user.bio!.trim().isNotEmpty;
    
    // ДОСТАЕМ ВСЕ ФОТО ИЗ ВСЕХ СООБЩЕНИЙ В ОДИН ПЛОСКИЙ СПИСОК
    final List<Map<String, String>> mediaList = [];
    for (var m in chatMessages) {
      if (m.imagesBase64 != null && m.imagesBase64!.isNotEmpty) {
        for (int i = 0; i < m.imagesBase64!.length; i++) {
          mediaList.add({'base64': m.imagesBase64![i], 'tag': '${m.id}_$i'});
        }
      } else if (m.imageBase64 != null && m.imageBase64!.isNotEmpty) {
        mediaList.add({'base64': m.imageBase64!, 'tag': '${m.id}_0'});
      }
    }

    void showDeleteDialog() {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Удалить чат?'),
            content: Text('Как именно вы хотите удалить переписку с ${user.username}? Это действие нельзя отменить.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context), // Просто закрываем окно
                child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
              ),
              // КНОПКА "ТОЛЬКО У МЕНЯ"
             // КНОПКА "ТОЛЬКО У МЕНЯ" (С ДЕБАГОМ)
              // КНОПКА "ТОЛЬКО У МЕНЯ"
              TextButton(
                onPressed: () async {
                  // 1. "Захватываем" навигатор до начала долгой операции
                  final nav = Navigator.of(context);
                  
                  // 2. Отправляем запрос в Firebase
                  final success = await ApiService().deleteChat(FirebaseAuth.instance.currentUser!.uid, user.id, false);
                  
                  // 3. Закрываем все окна железобетонным способом
                  if (success) {
                    nav.popUntil((route) => route.isFirst);
                  }
                },
                child: const Text('Только у меня'),
              ),

              // КНОПКА "У ОБОИХ"
              TextButton(
                onPressed: () async {
                  // 1. "Захватываем" навигатор
                  final nav = Navigator.of(context);
                  
                  // 2. Отправляем запрос в Firebase
                  final success = await ApiService().deleteChat(FirebaseAuth.instance.currentUser!.uid, user.id, true);
                  
                  // 3. Выкидываем пользователя на главный экран
                  if (success) {
                    nav.popUntil((route) => route.isFirst);
                  }
                },
                child: const Text('У обоих', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    }

    // --- ОБНОВЛЕННЫЙ SCAFFOLD С КНОПКОЙ В ШАПКЕ ---
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'), 
        elevation: 0,
        actions: [
          // Кнопка с тремя точками
          // Оборачиваем меню в StreamBuilder, чтобы оно в реальном времени знало статус блокировки
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .snapshots(),
            builder: (context, snapshot) {
              
              // 1. Узнаем, заблокирован ли пользователь прямо сейчас
              bool isBlocked = false;
              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>?;
                if (data != null && data.containsKey('blockedUsers')) {
                  List blockedUsers = data['blockedUsers'];
                  isBlocked = blockedUsers.contains(user.id); // user.id - это ID собеседника
                }
              }

              // 2. Рисуем само меню с тремя точками
              return PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'delete') {
                    showDeleteDialog(); // Твоя старая функция удаления чата
                  } else if (value == 'block') {
                    // Вызываем наш метод блокировки/разблокировки из ApiService
                    await ApiService().toggleBlockUser(
                      FirebaseAuth.instance.currentUser!.uid,
                      user.id,
                      isBlocked,
                    );
                  }
                },
                itemBuilder: (BuildContext context) => [
                  // --- ПЕРВАЯ КНОПКА: УДАЛИТЬ ЧАТ ---
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text('Удалить чат', style: TextStyle(color: Colors.redAccent)),
                      ],
                    ),
                  ),
                  
                  // --- ВТОРАЯ КНОПКА: ЗАБЛОКИРОВАТЬ / РАЗБЛОКИРОВАТЬ ---
                  PopupMenuItem<String>(
                    value: 'block',
                    child: Row(
                      children: [
                        Icon(
                          isBlocked ? Icons.lock_open : Icons.block,
                          color: isBlocked ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isBlocked ? 'Разблокировать' : 'Заблокировать',
                          style: TextStyle(
                            color: isBlocked ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      // --- ДАЛЬШЕ ИДЕТ ТВОЙ СТАРЫЙ КОД ---
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // --- НОВАЯ АВАТАРКА С КЛИКОМ ---
            Center(
              child: GestureDetector(
                onTap: () {
                  // Если у юзера нет фото (стоит просто иконка), то ничего не открываем
                  if (user.avatarBase64 == null) return; 

                  // Открываем фото на весь экран
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      backgroundColor: Colors.black.withOpacity(0.9),
                      insetPadding: EdgeInsets.zero,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          InteractiveViewer(
                            panEnabled: true,
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.height,
                              // БЕРЕМ ТВОЮ РЕАЛЬНУЮ ФОТКУ ИЗ БАЗЫ
                              child: Image.memory(
                                base64Decode(user.avatarBase64!),
                                fit: BoxFit.contain, // contain чтобы фото влезло целиком и не обрезалось
                              ),
                            ),
                          ),
                          // Крестик закрытия
                          Positioned(
                            top: 40,
                            left: 16,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white, size: 30),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue[100]!, width: 3),
                  ),
                  child: ClipOval(child: buildAvatar()),
                ),
              ),
            ),
            // --- КОНЕЦ АВАТАРКИ ---
            const SizedBox(height: 24),
            Text(user.username, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              _getStatusText(user),
              style: TextStyle(fontSize: 16, color: user.isOnline ? Colors.green : Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.phone, color: Colors.blue),
                    title: Text(user.phoneNumber ?? 'Номер скрыт', style: const TextStyle(fontSize: 18)),
                    subtitle: const Text('Мобильный телефон'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline, color: Colors.blue),
                    title: Text(
                      hasBio ? user.bio! : 'Здесь пока пусто',
                      style: TextStyle(
                        fontSize: 16,
                        color: hasBio ? null : Colors.grey,
                        fontStyle: hasBio ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                    subtitle: const Text('О себе'),
                  ),
                ],
              ),
            ),
            
            if (mediaList.isNotEmpty) ...[
              const SizedBox(height: 32),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Медиа', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shrinkWrap: true, 
                physics: const NeverScrollableScrollPhysics(), 
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, 
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: mediaList.length,
                itemBuilder: (context, index) {
                  final media = mediaList[index];
                  final bytes = base64Decode(media['base64']!.replaceAll(RegExp(r'\s+'), ''));
                  
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(context, PageRouteBuilder(
                        opaque: false,
                        transitionDuration: const Duration(milliseconds: 300),
                        pageBuilder: (context, animation, secondaryAnimation) => FullScreenImageScreen(
                          mediaList: mediaList,
                          initialIndex: index,
                        ),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                      ));
                    },
                    child: Hero(
                      tag: media['tag']!,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          bytes, 
                          fit: BoxFit.cover, 
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40), 
            ],
          ],
        ),
      ),
    );
  }
}