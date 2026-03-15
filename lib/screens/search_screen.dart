import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';

class SearchScreen extends StatefulWidget {
  final UserModel currentUser;

  const SearchScreen({super.key, required this.currentUser});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  List<UserModel> _allUsers = [];
  List<UserModel> _searchResults = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
  }

  // Загружаем всех пользователей один раз, чтобы потом искать по ним мгновенно
  Future<void> _loadAllUsers() async {
    final api = ApiService();
    final users = await api.getUsers();
    
    if (mounted) {
      setState(() {
        // Убираем сами себя из списка поиска
        _allUsers = users.where((u) => u.id != widget.currentUser.id).toList();
        _isLoading = false;
      });
    }
  }

  // Функция самого поиска (ищет по совпадению букв в имени или цифр в номере)
  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    final lowerQuery = query.toLowerCase();

    setState(() {
      _searchResults = _allUsers.where((user) {
        final nameMatch = user.username.toLowerCase().contains(lowerQuery);
        final phoneMatch = user.phoneNumber?.contains(query) ?? false;
        return nameMatch || phoneMatch;
      }).toList();
    });
  }

  // Вспомогательная функция для аватарки
  Widget _buildAvatar(UserModel user) {
    if (user.avatarBase64 != null && user.avatarBase64!.isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(user.avatarBase64!);
        return CircleAvatar(backgroundImage: MemoryImage(bytes), backgroundColor: Colors.transparent);
      } catch (_) {}
    }
    return CircleAvatar(child: Text(user.username.isNotEmpty ? user.username[0].toUpperCase() : '?'));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtrl,
          autofocus: true, // Сразу открываем клавиатуру
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Поиск по имени или номеру...',
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          onChanged: _performSearch, // Ищем при каждом вводе буквы
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.blue,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _searchCtrl.text.isEmpty
              ? const Center(
                  child: Text(
                    'Введите имя или номер телефона\nдля поиска друзей',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : _searchResults.isEmpty
                  ? const Center(child: Text('Ничего не найдено 😔'))
                  : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final user = _searchResults[index];
                        return ListTile(
                          leading: _buildAvatar(user),
                          title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(user.phoneNumber ?? 'Нет номера'),
                          trailing: const Icon(Icons.chat_bubble_outline, color: Colors.blue),
                          onTap: () {
                            // При клике открываем чат с этим человеком!
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  currentUser: widget.currentUser,
                                  otherUser: user,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}