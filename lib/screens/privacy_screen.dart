import 'package:flutter/material.dart';
import 'package:messapp1/screens/blacklist_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'passcode_screen.dart'; // Подключаем наш экран пароля
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_service.dart';
import 'register_screen.dart'; // Чтобы перекинуть пользователя сюда после удаления

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _hasPasscode = false;

  @override
  void initState() {
    super.initState();
    _loadPasscodeStatus();
  }

  Future<void> _loadPasscodeStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hasPasscode = prefs.getString('app_passcode') != null;
    });
  }
// --- ЛОГИКА УДАЛЕНИЯ АККАУНТА ---
  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text(
          'Это действие необратимо. Все ваши данные, настройки и доступ к аккаунту будут удалены навсегда.\n\nВы точно уверены?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Закрываем диалог
              _performAccountDeletion(); // Запускаем удаление
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _performAccountDeletion() async {
    // Показываем крутилку загрузки поверх всего экрана
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final success = await ApiService().deleteAccount(userId);

    // Убираем крутилку загрузки
    if (mounted) Navigator.pop(context);

    if (success) {
      // Полностью очищаем память телефона (кэш, ПИН-код, темы и т.д.)
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) {
        // Перекидываем на экран регистрации и сносим историю навигации (чтобы нельзя было вернуться кнопкой "Назад")
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const RegisterScreen()),
          (route) => false,
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка! В целях безопасности выйдите из аккаунта и войдите заново, чтобы подтвердить удаление.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }
  // --- КОНЕЦ ЛОГИКИ УДАЛЕНИЯ ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Конфиденциальность')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Безопасность',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('ПИН-код приложения'),
            subtitle: Text(_hasPasscode ? 'Включен' : 'Выключен'),
            trailing: Switch(
              value: _hasPasscode,
              activeColor: Colors.blue,
              onChanged: (val) async {
                if (val) {
                  // Если включаем тумблер -> просим придумать пароль
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => PasscodeScreen(
                    isSetup: true,
                    onSuccess: () {
                      Navigator.pop(context); // Закрываем экран ввода пароля
                      setState(() => _hasPasscode = true);
                    }
                  )));
                } else {
                  // Если выключаем тумблер -> удаляем пароль
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('app_passcode');
                  setState(() => _hasPasscode = false);
                }
              },
            ), // Switch
            ), // <-- ВОТ ОНА! Закрываем кнопку с паролем ЗДЕСЬ

            // --- ТЕПЕРЬ НАЧИНАЕТСЯ НАША НОВАЯ КНОПКА ---
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Черный список'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BlacklistScreen()),
                );
              },
            ),
            const Divider(), // Полоска-разделитель для красоты

            // --- КНОПКА УДАЛЕНИЯ АККАУНТА ---
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Удалить аккаунт', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () => _showDeleteAccountDialog(context),
            ),
            // -------------------------------------------
          ],
      ),
    );
  }
}