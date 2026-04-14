import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; 
import '../models/user.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'privacy_screen.dart';
import 'passcode_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notifications_screen.dart';

class ChatListScreen extends StatefulWidget {
  final UserModel currentUser;

  const ChatListScreen({super.key, required this.currentUser});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with WidgetsBindingObserver {
  Color _drawerBgColor = Colors.blue;
  Color _drawerTextColor = Colors.white;
  String? _drawerBgImagePath;
  late UserModel _currentUser;
  List<UserModel> _users = [];
  bool _isLoading = true;
  bool _isThemeLoaded = false;
  bool _isLockScreenVisible = false; // <--- ДОБАВИТЬ
  final ApiService _api = ApiService();

  @override
  void initState() {
    super.initState();
    _setupPushNotifications();
    _currentUser = widget.currentUser;
    WidgetsBinding.instance.addObserver(this);
    _api.updateUserPresence(_currentUser.id, true);
    _loadTheme();
    _checkPasscode();
    _loadUsers();
  }
  // --- ФУНКЦИЯ НАСТРОЙКИ ПУШЕЙ ---
  Future<void> _setupPushNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await messaging.getToken();
      
      if (token != null) {
        print('МОЙ FCM ТОКЕН: $token');
        // --- НОВАЯ СТРОЧКА: Сохраняем токен в базу Firebase! ---
        await ApiService().saveUserToken(widget.currentUser.id, token);
      }
      
      // Слушаем обновления токена (если он вдруг изменится)
      messaging.onTokenRefresh.listen((newToken) {
        ApiService().saveUserToken(widget.currentUser.id, newToken);
      });
    }
  }
  
Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final bgColorInt = prefs.getInt('chat_bg_color');
    final bgImage = prefs.getString('chat_bg_image');

    // Предзагрузка картинки для шапки меню!
    if (bgImage != null && mounted) {
      try {
        await precacheImage(FileImage(File(bgImage)), context);
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        if (bgColorInt != null) {
          _drawerBgColor = Color(bgColorInt);
          _drawerTextColor = _drawerBgColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
        } else {
          _drawerBgColor = Colors.blue;
          _drawerTextColor = Colors.white;
        }
        _drawerBgImagePath = bgImage;
        _isThemeLoaded = true; // <--- Шапка готова к показу!
      });
    }
  }

Future<void> _checkPasscode() async {
    if (_isLockScreenVisible) return;
    
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('app_passcode') != null) {
      _isLockScreenVisible = true;
      if (mounted) {
         await Navigator.push(context, MaterialPageRoute(
           fullscreenDialog: true,
           builder: (_) => PasscodeScreen(
             isSetup: false,
             onSuccess: () => Navigator.pop(context),
           )
         ));
         _isLockScreenVisible = false;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

@override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _api.updateUserPresence(_currentUser.id, true);
      _checkPasscode(); // <--- ДОБАВИТЬ СЮДА
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _api.updateUserPresence(_currentUser.id, false);
    }
  }

  Future<void> _loadUsers() async {
    final allUsers = await _api.getUsers();
    final activeChatIds = await _api.getActiveChatIds(_currentUser.id);

    if (mounted) {
      setState(() {
        _users = allUsers.where((u) => activeChatIds.contains(u.id)).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await _api.updateUserPresence(_currentUser.id, false);
    await FirebaseAuth.instance.signOut();
  }

  Widget _buildAvatar(UserModel user, {double radius = 20}) {
    if (user.avatarBase64 != null && user.avatarBase64!.isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(user.avatarBase64!);
        return CircleAvatar(radius: radius, backgroundImage: MemoryImage(bytes), backgroundColor: Colors.transparent);
      } catch (e) {
        return CircleAvatar(radius: radius, backgroundColor: Colors.red, child: const Icon(Icons.error));
      }
    }
    return CircleAvatar(radius: radius, child: Text(user.username.isNotEmpty ? user.username[0].toUpperCase() : '?'));
  }

  String _getStatusText(UserModel user) {
    if (user.isOnline) return 'В сети';
    if (user.lastSeen == null) return 'Был(а) недавно';
    final time = DateFormat('HH:mm').format(user.lastSeen!.toLocal());
    return 'Был(а) в $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawerEdgeDragWidth: MediaQuery.of(context).size.width,
      appBar: AppBar(
        title: const Text('Чаты'),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(
                _currentUser.username, 
                style: TextStyle(fontWeight: FontWeight.bold, color: _drawerTextColor)
              ),
              accountEmail: Text(
                _currentUser.phoneNumber ?? 'Нет номера', 
                style: TextStyle(color: _drawerTextColor)
              ),
              currentAccountPicture: _buildAvatar(_currentUser, radius: 40),
              
              // ВОТ ЭТА ЧАСТЬ ОТВЕЧАЕТ ЗА ЦВЕТ И ФОТО:
              decoration: BoxDecoration(
                color: _drawerBgColor, // Применяем цвет
                image: _drawerBgImagePath != null && _drawerBgImagePath!.isNotEmpty
                    ? DecorationImage(
                        image: FileImage(File(_drawerBgImagePath!)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // 1. Поиск контактов (вернули на место!)
                  ListTile(
                    leading: const Icon(Icons.contacts),
                    title: const Text('Поиск контактов'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SearchScreen(currentUser: _currentUser)),
                      ).then((_) => _loadUsers());
                    },
                  ),
                  
                  // 2. Избранное
                  ListTile(
                    leading: const Icon(Icons.pets, color: Colors.blue),
                    title: const Text('Избранное'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            currentUser: _currentUser,
                            otherUser: _currentUser,
                          ),
                        ),
                      ).then((_) => _loadUsers());
                    },
                  ),
                  
                  const Divider(),
                  
                  // 3. Аккаунт
                  ListTile(
                    leading: const Icon(Icons.account_circle),
                    title: const Text('Аккаунт'),
                    onTap: () async {
                      Navigator.pop(context);
                      final updatedUser = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ProfileScreen(currentUser: _currentUser)),
                      );
                      if (updatedUser != null && updatedUser is UserModel) {
                        setState(() => _currentUser = updatedUser);
                      }
                    },
                  ),
                  
                  // 4. Настройки чатов (ТЕПЕРЬ ОДНА И С ПРАВИЛЬНЫМ ОБНОВЛЕНИЕМ)
                  ListTile(
                    leading: const Icon(Icons.chat),
                    title: const Text('Настройки чатов'),
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                      _loadTheme(); // <--- Теперь шапка будет обновляться всегда!
                    },
                  ),
                  
                  // 5. Конфиденциальность
                  ListTile(
                    leading: const Icon(Icons.privacy_tip), 
                    title: const Text('Конфиденциальность'), 
                    onTap: () {
                      Navigator.pop(context); // Закрываем боковое меню
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen()));
                    }
                  ),
                  
                  // 6. Уведомления и звуки
                  ListTile(
              leading: const Icon(Icons.notifications, color: Colors.blue), // Иконка на твой вкус
              title: const Text('Уведомления и звуки'),
              onTap: () {
                Navigator.pop(context); // Сначала плавно закрываем само боковое меню
                
                // Затем открываем наш новый красивый экран!
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                );
              },
            ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: const Text('Выйти', style: TextStyle(color: Colors.red)),
              onTap: _signOut,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        child: const Icon(Icons.edit, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SearchScreen(currentUser: _currentUser)),
          ).then((_) => _loadUsers()); 
        },
      ),
      body: _isLoading || !_isThemeLoaded
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      const Text(
                        'У вас пока нет чатов.\nНажмите на кнопку внизу,\nчтобы найти друзей!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadUsers,
                  child: ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final isSavedMessages = user.id == _currentUser.id;

          // --- 1. ФОРМИРУЕМ ID ЧАТА ---
          List<String> ids = [user.id, _currentUser.id];
          ids.sort();
          String chatId = ids.join('_');

          // --- 2. СЛУШАЕМ БАЗУ ПЕРЕД ОТРИСОВКОЙ ---
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('chats').doc(chatId).snapshots(),
            builder: (context, snapshot) {
              
              // Пока данные летят с сервера, рисуем "пустоту", чтобы не было мерцаний
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox.shrink(); 
              }

              final chatExists = snapshot.hasData && snapshot.data!.exists;

              // ФИЛЬТР 1: Если мы удалили чат "У обоих" (папки больше нет в базе)
              // Мы прячем этого юзера! (Но "Избранное" оставляем всегда)
              if (!chatExists && !isSavedMessages) {
                return const SizedBox.shrink(); 
              }

              // ФИЛЬТР 2: Если чат удален "Только у меня" (висит ярлык deletedBy)
              if (chatExists) {
                final data = snapshot.data!.data() as Map<String, dynamic>?;
                if (data != null && data.containsKey('deletedBy')) {
                  List deletedBy = data['deletedBy'];
                  if (deletedBy.contains(_currentUser.id)) {
                    return const SizedBox.shrink(); // Прячем юзера!
                  }
                }
              }
                      return ListTile(
                        leading: Stack(
                          children: [
                            // --- ИЗМЕНЕНИЕ 2: Иконка Избранного в списке чатов ---
                            isSavedMessages
                                ? const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.pets, color: Colors.white))
                                : _buildAvatar(user),
                            if (user.isOnline && !isSavedMessages)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(isSavedMessages ? 'Избранное' : user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          isSavedMessages ? 'Ваши сохраненные сообщения' : _getStatusText(user),
                          style: TextStyle(color: user.isOnline && !isSavedMessages ? Colors.blue : Colors.grey),
                        ),
                        
                        // --- НОВОЕ: ВЫВОДИМ СЧЕТЧИК НЕПРОЧИТАННЫХ ---
                        trailing: isSavedMessages
                            ? null // В избранном счетчик не нужен
                            : StreamBuilder<int>(
                                stream: _api.getUnreadCountStream(_currentUser.id, user.id),
                                builder: (context, snapshot) {
                                  final unreadCount = snapshot.data ?? 0;
                                  if (unreadCount > 0) {
                                    return Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        unreadCount.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),

                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(currentUser: _currentUser, otherUser: user),
                            ),
                          ).then((_) => _loadUsers());
                        },
                      ); // 1. Закрываем ListTile
            }, // 2. Закрываем функцию builder (у StreamBuilder)
          ); // 3. Закрываем сам виджет StreamBuilder
        }, // 4. ЗАКРЫВАЕМ функцию itemBuilder (которую мы потеряли!)
      ), // 5. Закрываем ListView.builder
      ), // 6. ЗАКРЫВАЕМ RefreshIndicator (вот этой скобки нам и не хватало!)
    );
  }
}
