import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Подключаем наш main.dart, чтобы дергать рубильник themeNotifier

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    // Проверяем, в каком положении рубильник сейчас
    _isDarkMode = themeNotifier.value == ThemeMode.dark;
  }

  // Функция, которая делает магию при нажатии на переключатель
  Future<void> _toggleTheme(bool value) async {
    setState(() {
      _isDarkMode = value; // Меняем анимацию тумблера
    });

    // 1. Меняем цвета во всем приложении мгновенно!
    themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;

    // 2. Сохраняем твой выбор в память телефона навсегда
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки чатов'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Оформление',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(_isDarkMode ? Icons.dark_mode : Icons.light_mode),
            title: const Text('Ночной режим'),
            subtitle: const Text('Темная тема для экономии заряда и зрения'),
            trailing: Switch(
              value: _isDarkMode,
              onChanged: _toggleTheme,
              activeColor: Colors.blue,
            ),
          ),
          const Divider(),
          // Задел на будущее для обоев
          ListTile(
            leading: const Icon(Icons.wallpaper),
            title: const Text('Обои для чата'),
            subtitle: const Text('В разработке...'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Скоро добавим выбор крутых обоев! 😎')),
              );
            },
          ),
        ],
      ),
    );
  }
}