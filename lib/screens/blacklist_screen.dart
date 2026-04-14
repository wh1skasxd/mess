import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_service.dart'; // Проверь правильность пути к твоему ApiService

class BlacklistScreen extends StatelessWidget {
  const BlacklistScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Черный список'),
      ),
      // Слушаем твой документ в реальном времени
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(currentUserUid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Ошибка загрузки данных'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          List blockedUsers = data != null && data.containsKey('blockedUsers') ? data['blockedUsers'] : [];

          if (blockedUsers.isEmpty) {
            return const Center(
              child: Text('Ваш черный список пуст', style: TextStyle(fontSize: 16, color: Colors.grey)),
            );
          }

          return ListView.builder(
            itemCount: blockedUsers.length,
            itemBuilder: (context, index) {
              String blockedUid = blockedUsers[index];

              // Загружаем данные заблокированного пользователя по его ID
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(blockedUid).get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const ListTile(title: Text('Загрузка...'));
                  }

                  var userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                  // Подставь 'name' или 'username', смотря как у тебя в базе называется поле с именем
                  String name = userData?['name'] ?? 'Неизвестный пользователь'; 

                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.redAccent,
                      child: Icon(Icons.person_off, color: Colors.white),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: TextButton(
                      onPressed: () async {
                        // Разблокируем! Передаем isBlocked = true, чтобы метод удалил его из списка
                        await ApiService().toggleBlockUser(currentUserUid, blockedUid, true);
                      },
                      child: const Text('Разблокировать', style: TextStyle(color: Colors.green)),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}