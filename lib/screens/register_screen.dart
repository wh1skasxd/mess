import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import 'login_screen.dart'; // Добавляем, чтобы экран видел соседа

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController(); // Заменили на Email
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _register() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final confirm = _confirmPasswordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Заполните все поля');
      return;
    }

    if (password != confirm) {
      setState(() => _errorMessage = 'Пароли не совпадают');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Создаем пользователя в системе авторизации Firebase
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 2. Если всё ок, сохраняем его в нашу базу данных Firestore,
      // чтобы другие пользователи могли его найти
      if (userCredential.user != null) {
        final newUser = UserModel(
          id: userCredential.user!.uid,
          username: email.split('@')[0], // Берем никнейм из почты
          isActive: true,
          createdAt: DateTime.now(),
        );

        final api = ApiService();
        await api.saveUser(newUser);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Регистрация успешна! Теперь войдите')),
          );
          Navigator.pop(context); // Возвращаемся на экран входа
        }
      }
    } on FirebaseAuthException catch (e) {
      // Обработка ошибок от Firebase
      String message = 'Ошибка регистрации';
      if (e.code == 'weak-password') {
        message = 'Пароль слишком простой (минимум 6 символов)';
      } else if (e.code == 'email-already-in-use') {
        message = 'Пользователь с таким email уже существует';
      } else if (e.code == 'invalid-email') {
        message = 'Некорректный формат email';
      }

      setState(() {
        _errorMessage = message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Регистрация')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email', // Поменяли текст
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(
                labelText: 'Пароль (минимум 6 символов)',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordCtrl,
              decoration: const InputDecoration(
                labelText: 'Повторите пароль',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              onSubmitted: (_) => _register(),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton(
                onPressed: _register,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Зарегистрироваться', style: TextStyle(fontSize: 16)),
              ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                // Жестко перекидываем на экран входа, заменяя текущий экран
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
              child: const Text('Уже есть аккаунт?\nВойти', textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}