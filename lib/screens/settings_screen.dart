import 'dart:io';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
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
  
  // 1. ДОБАВЛЯЕМ ПЕРЕМЕННУЮ СЮДА
  String _quickReaction = '❤️'; 

  @override
  void initState() {
    super.initState();
    _isDarkMode = themeNotifier.value == ThemeMode.dark;
    
    // 2. ВЫЗЫВАЕМ ЗАГРУЗКУ
    _loadQuickReaction(); 
  }

  // 3. ФУНКЦИЯ ЗАГРУЗКИ ИЗ ПАМЯТИ
  Future<void> _loadQuickReaction() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _quickReaction = prefs.getString('quick_reaction') ?? '❤️';
      });
    }
  }

  // 4. САМА ФУНКЦИЯ ОКНА (СМАЙЛИКОВ)
  void _showQuickReactionPicker() {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '🔥', '🎉', '👎', '🤡'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Быстрая реакция'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: emojis.map((emoji) => GestureDetector(
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('quick_reaction', emoji); 
              if (mounted) {
                setState(() => _quickReaction = emoji);
                Navigator.pop(context);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _quickReaction == emoji ? Colors.blue.withOpacity(0.3) : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 28)),
            ),
          )).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ],
      ),
    );
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
          activeColor: Colors.blue,
          onChanged: (value) async {
            // Переключаем тему во всем приложении
            themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
            // Сохраняем выбор в память телефона
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('isDarkMode', value);
            // Обновляем состояние кнопки
            setState(() => _isDarkMode = value);
          },
        ),
          ),
          const Divider(),
          // Задел на будущее для обоев
          ListTile(
            leading: const Icon(Icons.wallpaper),
            title: const Text('Обои для чата'),
            subtitle: const Text('Настроить цвета и фон'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: ()
             {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatThemeSettingsScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.red),
            title: const Text('Быстрая реакция'),
            subtitle: const Text('Двойной тап по сообщению'),
            trailing: Text(_quickReaction, style: const TextStyle(fontSize: 28)),
            onTap: _showQuickReactionPicker,
          ),
        ],
      ),
    );
  }
}

class ChatThemeSettingsScreen extends StatefulWidget {
  const ChatThemeSettingsScreen({super.key});

  @override
  State<ChatThemeSettingsScreen> createState() => _ChatThemeSettingsScreenState();
}

class _ChatThemeSettingsScreenState extends State<ChatThemeSettingsScreen> {
  Color _chatBgColor = Colors.blueGrey[50]!;
  Color _myBubbleColor = Colors.blue[700]!;
  Color _otherBubbleColor = Colors.grey[700]!;
  String? _bgImagePath;
  double _bgBlur = 0.0;
  String _quickReaction = '❤️'; // <--- ВОТ ТА САМАЯ ПЕРЕМЕННАЯ

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _chatBgColor = Color(prefs.getInt('chat_bg_color') ?? Colors.blueGrey[50]!.value);
      _myBubbleColor = Color(prefs.getInt('my_bubble_color') ?? Colors.blue[700]!.value);
      _otherBubbleColor = Color(prefs.getInt('other_bubble_color') ?? Colors.grey[700]!.value);
      _bgImagePath = prefs.getString('chat_bg_image');
      _bgBlur = prefs.getDouble('chat_bg_blur') ?? 0.0;
      _quickReaction = prefs.getString('quick_reaction') ?? '❤️';
    });
  }

  Future<void> _applyChanges() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('chat_bg_color', _chatBgColor.value);
    await prefs.setInt('my_bubble_color', _myBubbleColor.value);
    await prefs.setInt('other_bubble_color', _otherBubbleColor.value);
    await prefs.setDouble('chat_bg_blur', _bgBlur);
    await prefs.setString('quick_reaction', _quickReaction);
    
    if (_bgImagePath != null) {
      await prefs.setString('chat_bg_image', _bgImagePath!);
    } else {
      await prefs.remove('chat_bg_image');
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Тема успешно применена!')));
      Navigator.pop(context);
    }
  }

  Future<void> _resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chat_bg_color');
    await prefs.remove('my_bubble_color');
    await prefs.remove('other_bubble_color');
    await prefs.remove('chat_bg_image');
    await prefs.remove('chat_bg_blur');
    await prefs.remove('quick_reaction');
    
    if (mounted) {
      setState(() {
        _chatBgColor = Colors.blueGrey[50]!;
        _myBubbleColor = Colors.blue[700]!;
        _otherBubbleColor = Colors.grey[700]!;
        _bgImagePath = null;
        _bgBlur = 0.0;
        _quickReaction = '❤️';
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Возвращены стандартные настройки')));
      Navigator.pop(context);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _bgImagePath = pickedFile.path);
    }
  }

  void _clearImage() {
    setState(() => _bgImagePath = null);
  }

  void _showColorPicker(String title, Color currentColor, Function(Color) onColorChanged) {
    Color tempColor = currentColor;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: currentColor,
            onColorChanged: (color) => tempColor = color,
            pickerAreaHeightPercent: 0.8,
            enableAlpha: false,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(
            onPressed: () {
              onColorChanged(tempColor);
              Navigator.pop(context);
            },
            child: const Text('Выбрать'),
          ),
        ],
      ),
    );
  }

  // ВСПЛЫВАЮЩЕЕ ОКНО ЭМОДЗИ
  void _showQuickReactionPicker() {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '🔥', '🎉', '👎', '🤡'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Быстрая реакция'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: emojis.map((emoji) => GestureDetector(
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('quick_reaction', emoji); 
              if (mounted) {
                setState(() => _quickReaction = emoji);
                Navigator.pop(context); // Применяем и закрываем окно
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _quickReaction == emoji ? Colors.blue.withOpacity(0.3) : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 28)),
            ),
          )).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Оформление чатов'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Сбросить по умолчанию',
            onPressed: _resetToDefault,
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Цвет фона чата (и меню)'),
            trailing: CircleAvatar(backgroundColor: _chatBgColor),
            onTap: () => _showColorPicker('Фон чата', _chatBgColor, (color) {
              setState(() => _chatBgColor = color);
            }),
          ),
          ListTile(
            title: const Text('Цвет моих сообщений'),
            trailing: CircleAvatar(backgroundColor: _myBubbleColor),
            onTap: () => _showColorPicker('Мои сообщения', _myBubbleColor, (color) {
              setState(() => _myBubbleColor = color);
            }),
          ),
          ListTile(
            title: const Text('Цвет сообщений собеседника'),
            trailing: CircleAvatar(backgroundColor: _otherBubbleColor),
            onTap: () => _showColorPicker('Чужие сообщения', _otherBubbleColor, (color) {
              setState(() => _otherBubbleColor = color);
            }),
          ),
          const Divider(),
          
         

          ListTile(
            leading: const Icon(Icons.image),
            title: const Text('Установить фото на фон'),
            subtitle: _bgImagePath != null ? const Text('Фото выбрано') : const Text('Фото не выбрано'),
            onTap: _pickImage,
          ),
          
          if (_bgImagePath != null) ...[
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 16, right: 16),
              child: Text('Степень размытия фона:'),
            ),
            Slider(
              value: _bgBlur,
              min: 0.0,
              max: 15.0,
              divisions: 15,
              activeColor: Colors.blue,
              label: _bgBlur.round().toString(),
              onChanged: (value) {
                setState(() => _bgBlur = value);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Удалить фото обоев', style: TextStyle(color: Colors.red)),
              onTap: _clearImage,
            ),
          ],
            
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _applyChanges,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Применить изменения', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _resetToDefault,
            child: const Text('Вернуть стандартные настройки', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}