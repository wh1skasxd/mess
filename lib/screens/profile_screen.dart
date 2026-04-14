import 'dart:convert'; 
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import '../models/user.dart';
import '../services/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'register_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  final UserModel currentUser;

  const ProfileScreen({super.key, required this.currentUser});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _usernameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _bioCtrl; 
  
  String? _newAvatarBase64; 
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.currentUser.username);
    _phoneCtrl = TextEditingController(text: widget.currentUser.phoneNumber ?? '');
    _bioCtrl = TextEditingController(text: widget.currentUser.bio ?? '');
    _newAvatarBase64 = widget.currentUser.avatarBase64;
    _loadFreshData();
  }

  // --- ТВОЯ ЛОГИКА ЗАГРУЗКИ ---
  Future<void> _loadFreshData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _usernameCtrl.text = data['username'] ?? '';
          _phoneCtrl.text = data['phoneNumber'] ?? '';
          _bioCtrl.text = data['bio'] ?? '';
          _newAvatarBase64 = data['avatarBase64'];
        });
      }
    } catch (e) {
      print('Ошибка при загрузке свежих данных профиля: $e');
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _phoneCtrl.dispose(); 
    _bioCtrl.dispose();
    super.dispose();
  }

  // --- ТВОЯ ЛОГИКА ФОТО ---
  Future<void> _pickAndConvertImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400, 
      maxHeight: 400, 
      imageQuality: 70, 
    );
    if (image != null) {
      setState(() => _isLoading = true);
      final Uint8List imageBytes = await image.readAsBytes();
      final String base64String = base64Encode(imageBytes);
      setState(() {
        _newAvatarBase64 = base64String; 
        _isLoading = false;
      });
    }
  }

  // --- ТВОЯ ЛОГИКА СОХРАНЕНИЯ ---
  Future<void> _saveProfile() async {
    final newUsername = _usernameCtrl.text.trim();
    final newPhone = _phoneCtrl.text.trim();
    final newBio = _bioCtrl.text.trim(); 

    if (newUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Имя не может быть пустым')));
      return;
    }

    setState(() => _isLoading = true);
    final updatedUser = UserModel(
      id: widget.currentUser.id,
      username: newUsername,
      avatarBase64: _newAvatarBase64, 
      isActive: widget.currentUser.isActive,
      createdAt: widget.currentUser.createdAt,
      phoneNumber: newPhone.isEmpty ? null : newPhone,
      bio: newBio.isEmpty ? null : newBio, 
    );
    
    final api = ApiService();
    await api.saveUser(updatedUser);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', newUsername);
    await prefs.setString('phoneNumber', newPhone); 
    await prefs.setString('bio', newBio);
    if (_newAvatarBase64 != null) {
      await prefs.setString('avatarBase64', _newAvatarBase64!);
    }

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Профиль обновлен! 🎉')));
      Navigator.pop(context, updatedUser);
    }
  }
  
  // --- ТВОЯ ЛОГИКА ВЫХОДА ---
  Future<void> _logOut() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Вы сможете войти снова в любое время.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirm != true) return;
    
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); 

    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const RegisterScreen()), (route) => false);
    }
  }

  // ==========================================
  // 🎨 НОВЫЙ КРАСИВЫЙ ДИЗАЙН (UI)
  // ==========================================
  @override
  Widget build(BuildContext context) {
    // Функция для отрисовки самой фотки внутри кружка
    Widget buildAvatarImage() {
      if (_newAvatarBase64 == null) {
        return const Icon(Icons.person, size: 65, color: Colors.blue);
      }
      try {
        final Uint8List bytes = base64Decode(_newAvatarBase64!);
        return Image.memory(bytes, fit: BoxFit.cover, width: 130, height: 130);
      } catch (e) {
        return const Icon(Icons.error, size: 65, color: Colors.red);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой профиль'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          children: [
            // --- 📸 КРАСИВЫЙ БЛОК АВАТАРКИ ---
            GestureDetector(
              onTap: _pickAndConvertImage, 
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.withOpacity(0.3), width: 3),
                    ),
                    child: ClipOval(
                      child: _isLoading 
                        ? const Center(child: CircularProgressIndicator()) 
                        : buildAvatarImage()
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3),
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // --- 📝 КРАСИВЫЕ ПОЛЯ ВВОДА ---
            TextField(
              controller: _usernameCtrl,
              decoration: InputDecoration(
                labelText: 'Имя',
                prefixIcon: const Icon(Icons.person_outline, color: Colors.blue),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.blue, width: 2)),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Телефон',
                prefixIcon: const Icon(Icons.phone_outlined, color: Colors.blue),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.blue, width: 2)),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _bioCtrl,
              maxLength: 30,
              decoration: InputDecoration(
                labelText: 'О себе',
                hintText: 'Расскажите немного о себе...',
                prefixIcon: const Icon(Icons.info_outline, color: Colors.blue),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.blue, width: 2)),
              ),
            ),
            const SizedBox(height: 32),

            // --- 💾 КНОПКИ ---
            if (_isLoading)
              const CircularProgressIndicator()
            else
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 2,
                  ),
                  onPressed: _saveProfile,
                  child: const Text('Сохранить изменения', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton.icon(
                onPressed: _logOut,
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                label: const Text('Выйти из аккаунта', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent, width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}