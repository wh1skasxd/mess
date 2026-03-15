import 'dart:convert'; // Для кодирования картинки в текст
import 'dart:typed_data'; // Для декодирования текста обратно в картинку
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // Галерея
import '../models/user.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  final UserModel currentUser;

  const ProfileScreen({super.key, required this.currentUser});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _usernameCtrl;
  String? _newAvatarBase64; // Временное хранилище для новой фотки
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Предзаполняем текущее имя пользователя
    _usernameCtrl = TextEditingController(text: widget.currentUser.username);
    // Берем текущую аватарку из профиля
    _newAvatarBase64 = widget.currentUser.avatarBase64;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  // ФУНКЦИЯ МАГИИ: открывает галерею, сжимает фотку и делает из неё текст
  Future<void> _pickAndConvertImage() async {
    final picker = ImagePicker();
    // Открываем галерею.maxWidth и maxHeigh обязательны, чтобы база не лопнула
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400, // Сжимаем до 400px по ширине
      maxHeight: 400, // Сжимаем до 400px по высоте
      imageQuality: 70, // Уменьшаем качество до 70%
    );

    if (image != null) {
      setState(() => _isLoading = true);

      // Читаем фотку как набор байтов (цифр)
      final Uint8List imageBytes = await image.readAsBytes();
      // ХАКЕРСКИЙ ХОД: превращаем байты в длинную строку текста
      final String base64String = base64Encode(imageBytes);

      setState(() {
        _newAvatarBase64 = base64String; // Сохраняем текст для превью на экране
        _isLoading = false;
      });
    }
  }

  // Функция сохранения изменений
  Future<void> _saveProfile() async {
    final newUsername = _usernameCtrl.text.trim();
    if (newUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Имя не может быть пустым')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Собираем обновленного пользователя
    final updatedUser = UserModel(
      id: widget.currentUser.id,
      username: newUsername,
      avatarBase64: _newAvatarBase64, // Наш текст-картинка
      isActive: widget.currentUser.isActive,
      createdAt: widget.currentUser.createdAt,
    );

    final api = ApiService();
    // Сохраняем в Firestore
    await api.saveUser(updatedUser);

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль обновлен! 🎉')),
      );
      // Возвращаемся в чаты.ВАЖНО: мы передаем обновленного юзера обратно,
      // чтобы шторка сразу обновилась!
      Navigator.pop(context, updatedUser);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Вспомогательная функция для отображения аватарки
    Widget _buildAvatar() {
      // Если текста аватарки нет, показываем иконку
      if (_newAvatarBase64 == null) {
        return const Icon(Icons.person, size: 80, color: Colors.grey);
      }
      
      try {
        // Декодируем текст обратно в байты для отображения
        final Uint8List bytes = base64Decode(_newAvatarBase64!);
        return ClipOval(
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: 160,
            height: 160,
          ),
        );
      } catch (e) {
        // Если текст битый, показываем ошибку
        return const Icon(Icons.error, size: 80, color: Colors.red);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Аккаунт')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Центр с аватаркой и кнопкой смены
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue[100]!, width: 2),
                    ),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildAvatar(),
                  ),
                  // Кнопка галереи поверх аватарки
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.add_a_photo, color: Colors.white),
                        onPressed: _pickAndConvertImage,
                        iconSize: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Поле ввода имени
            TextField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Имя пользователя',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_circle),
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),
            // Заглушка для номера (его пока нет в нашей модели)
            // УБРАЛИ слово const вот отсюда:
            TextField(
              decoration: InputDecoration(
                labelText: 'Номер телефона',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.phone),
                hintText: widget.currentUser.phoneNumber ?? 'Не привязан', 
              ),
              enabled: false, 
            ),
            const SizedBox(height: 40),
            // Кнопка сохранения
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56), // Широкая кнопка
                ),
                child: const Text('Сохранить изменения', style: TextStyle(fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }
}