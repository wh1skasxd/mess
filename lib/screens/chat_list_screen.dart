import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Для красивого времени
import '../models/user.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

// Добавили WidgetsBindingObserver, чтобы следить за сворачиванием приложения!
class ChatListScreen extends StatefulWidget {
  final UserModel currentUser;

  const ChatListScreen({super.key, required this.currentUser});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with WidgetsBindingObserver {
  late UserModel _currentUser;
  List<UserModel> _users = [];
  bool _isLoading = true;
  final ApiService _api = ApiService();

  @override
  void initState() {
    super.initState();
    _currentUser = widget.currentUser;
    // Говорим Флаттеру: "Я буду следить за состоянием приложения"
    WidgetsBinding.instance.addObserver(this);
    // Как только зашли — мы онлайн!
    _api.updateUserPresence(_currentUser.id, true);
    _loadUsers();
  }

  @override
  void dispose() {
    // Говорим: "Я перестал следить"
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ЭТА ФУНКЦИЯ СРАБАТЫВАЕТ, КОГДА ТЫ СВОРАЧИВАЕШЬ ИЛИ ОТКРЫВАЕШЬ ПРИЛОЖЕНИЕ
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Приложение снова открыли
      _api.updateUserPresence(_currentUser.id, true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Приложение свернули или закрыли
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
    // Перед выходом ставим статус "Оффлайн"
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

  // ФУНКЦИЯ ДЛЯ КРАСИВОГО СТАТУСА (В сети или Был(а) тогда-то)
  String _getStatusText(UserModel user) {
    if (user.isOnline) return 'В сети';
    if (user.lastSeen == null) return 'Был(а) недавно';
    
    // Форматируем время, если человек оффлайн
    final time = DateFormat('HH:mm').format(user.lastSeen!.toLocal());
    return 'Был(а) в $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(_currentUser.username, style: const TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: Text(_currentUser.phoneNumber ?? 'Нет номера'),
              currentAccountPicture: _buildAvatar(_currentUser, radius: 40),
              decoration: const BoxDecoration(color: Colors.blue),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
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
                  ListTile(leading: const Icon(Icons.bookmark), title: const Text('Избранное'), onTap: () {}),
                  const Divider(),
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
                  ListTile(
                    leading: const Icon(Icons.chat),
                    title: const Text('Настройки чатов'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                    },
                  ),
                  ListTile(leading: const Icon(Icons.privacy_tip), title: const Text('Конфиденциальность'), onTap: () {}),
                  ListTile(leading: const Icon(Icons.notifications), title: const Text('Уведомления и звуки'), onTap: () {}),
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
      body: _isLoading
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
                      return ListTile(
                        leading: Stack(
                          children: [
                            _buildAvatar(user),
                            // ЗЕЛЕНАЯ ТОЧКА ОНЛАЙН!
                            if (user.isOnline)
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
                        title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                        // ВЫВОДИМ СТАТУС ВМЕСТО СТАРОГО ТЕКСТА
                        subtitle: Text(
                          _getStatusText(user),
                          style: TextStyle(color: user.isOnline ? Colors.blue : Colors.grey),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(currentUser: _currentUser, otherUser: user),
                            ),
                          ).then((_) => _loadUsers());
                        },
                      );
                    },
                  ),
                ),
    );
  }
}