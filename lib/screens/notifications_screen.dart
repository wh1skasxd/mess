import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // --- ПЕРЕМЕННЫЕ ДЛЯ НАСТРОЕК ---
  // Глобальные Push-уведомления
  bool _pushEnabled = true;
  bool _pushSound = true;
  bool _pushVibrate = true;
  bool _pushPreview = true; // Показывать ли текст сообщения на заблокированном экране

  // Уведомления внутри приложения (когда чат открыт)
  bool _inAppSounds = true;
  bool _inAppVibrate = true;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // --- ЗАГРУЗКА НАСТРОЕК ИЗ ПАМЯТИ ---
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pushEnabled = prefs.getBool('push_enabled') ?? true;
      _pushSound = prefs.getBool('push_sound') ?? true;
      _pushVibrate = prefs.getBool('push_vibrate') ?? true;
      _pushPreview = prefs.getBool('push_preview') ?? true;
      
      _inAppSounds = prefs.getBool('inapp_sounds') ?? true;
      _inAppVibrate = prefs.getBool('inapp_vibrate') ?? true;
      
      _isLoading = false;
    });
  }

  // --- СОХРАНЕНИЕ НАСТРОЙКИ ПРИ КЛИКЕ ---
  Future<void> _updateSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления и звуки'),
      ),
      body: ListView(
        children: [
          // ==========================================
          // РАЗДЕЛ 1: PUSH-УВЕДОМЛЕНИЯ
          // ==========================================
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 24, bottom: 8),
            child: Text(
              'PUSH-УВЕДОМЛЕНИЯ',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          
          // Главный рубильник
          SwitchListTile(
            title: const Text('Показывать уведомления', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Уведомления о новых сообщениях'),
            value: _pushEnabled,
            activeColor: Colors.blue,
            onChanged: (val) {
              setState(() => _pushEnabled = val);
              _updateSetting('push_enabled', val);
            },
          ),
          
          // Если главный рубильник включен, показываем детальные настройки
          if (_pushEnabled) ...[
            SwitchListTile(
              title: const Text('Предпросмотр сообщений'),
              subtitle: const Text('Показывать текст сообщения в уведомлении'),
              value: _pushPreview,
              activeColor: Colors.blue,
              onChanged: (val) {
                setState(() => _pushPreview = val);
                _updateSetting('push_preview', val);
              },
            ),
            SwitchListTile(
              title: const Text('Звук'),
              value: _pushSound,
              activeColor: Colors.blue,
              onChanged: (val) {
                setState(() => _pushSound = val);
                _updateSetting('push_sound', val);
              },
            ),
            SwitchListTile(
              title: const Text('Вибрация'),
              value: _pushVibrate,
              activeColor: Colors.blue,
              onChanged: (val) {
                setState(() => _pushVibrate = val);
                _updateSetting('push_vibrate', val);
              },
            ),
          ],

          const Divider(height: 32),

          // ==========================================
          // РАЗДЕЛ 2: В ПРИЛОЖЕНИИ
          // ==========================================
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text(
              'В ПРИЛОЖЕНИИ',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          
          SwitchListTile(
            title: const Text('Звуки в приложении'),
            subtitle: const Text('Звук отправки и получения сообщений'),
            value: _inAppSounds,
            activeColor: Colors.blue,
            onChanged: (val) {
              setState(() => _inAppSounds = val);
              _updateSetting('inapp_sounds', val);
            },
          ),
          SwitchListTile(
            title: const Text('Вибрация в приложении'),
            subtitle: const Text('Отклик при отправке и лайках'),
            value: _inAppVibrate,
            activeColor: Colors.blue,
            onChanged: (val) {
              setState(() => _inAppVibrate = val);
              _updateSetting('inapp_vibrate', val);
            },
          ),
          
          const Divider(height: 32),

          // ==========================================
          // РАЗДЕЛ 3: СБРОС НАСТРОЕК
          // ==========================================
          ListTile(
            leading: const Icon(Icons.restore, color: Colors.redAccent),
            title: const Text('Сбросить все настройки', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              // Возвращаем все как было по умолчанию
              setState(() {
                _pushEnabled = true;
                _pushSound = true;
                _pushVibrate = true;
                _pushPreview = true;
                _inAppSounds = true;
                _inAppVibrate = true;
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('push_enabled', true);
              await prefs.setBool('push_sound', true);
              await prefs.setBool('push_vibrate', true);
              await prefs.setBool('push_preview', true);
              await prefs.setBool('inapp_sounds', true);
              await prefs.setBool('inapp_vibrate', true);
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Настройки уведомлений сброшены'))
                );
              }
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}