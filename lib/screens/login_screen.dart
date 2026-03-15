import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import 'chat_list_screen.dart';

enum AuthState { enterPhone, enterCode, enterName }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  AuthState _currentState = AuthState.enterPhone;
  bool _isLoading = false;
  
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  
  String _verificationId = ''; 
  User? _firebaseUser; 

  // 1. ОТПРАВЛЯЕМ СМС
  Future<void> _sendSms() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;

    setState(() => _isLoading = true);

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      // Если Android сам прочитал СМС
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _signInWithCredential(credential);
      },
      // Если произошла ошибка (неверный номер и тд)
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return; // ЗАЩИТА ОТ ОШИБКИ
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки СМС: ${e.message}')),
        );
      },
      // Когда СМС успешно ушла
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return; // ЗАЩИТА ОТ ОШИБКИ
        setState(() {
          _isLoading = false;
          _verificationId = verificationId;
          _currentState = AuthState.enterCode;
        });
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  // 2. ПРОВЕРЯЕМ ВВЕДЕННЫЙ КОД ИЗ СМС
  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: code,
      );
      await _signInWithCredential(credential);
    } catch (e) {
      if (!mounted) return; // ЗАЩИТА ОТ ОШИБКИ
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Неверный код из СМС!')),
      );
    }
  }

  // 3. АВТОРИЗАЦИЯ И ПРОВЕРКА БАЗЫ ДАННЫХ
  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      _firebaseUser = userCredential.user;

      if (_firebaseUser != null) {
        final api = ApiService();
        final allUsers = await api.getUsers();
        
        UserModel? existingUser;
        try {
          existingUser = allUsers.firstWhere((u) => u.id == _firebaseUser!.uid);
        } catch (_) {
          existingUser = null; 
        }

        if (!mounted) return; // ЗАЩИТА ОТ ОШИБКИ

        if (existingUser != null) {
          // ЮЗЕР УЖЕ ЕСТЬ! Сразу кидаем в чаты
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => ChatListScreen(currentUser: existingUser!)),
          );
        } else {
          // НОВЕНЬКИЙ! Просим ввести Имя
          setState(() {
            _isLoading = false;
            _currentState = AuthState.enterName;
          });
        }
      }
    } catch (e) {
      if (!mounted) return; // ЗАЩИТА ОТ ОШИБКИ
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка авторизации')),
      );
    }
  }

  // 4. ФИНАЛЬНАЯ РЕГИСТРАЦИЯ
  Future<void> _completeRegistration() async {
    final name = _usernameCtrl.text.trim();
    if (name.isEmpty || _firebaseUser == null) return;

    setState(() => _isLoading = true);

    final newUser = UserModel(
      id: _firebaseUser!.uid,
      username: name,
      phoneNumber: _firebaseUser!.phoneNumber, 
      isActive: true,
      createdAt: DateTime.now(),
    );

    final api = ApiService();
    await api.saveUser(newUser);

    if (!mounted) return; // ЗАЩИТА ОТ ОШИБКИ

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ChatListScreen(currentUser: newUser)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в MessApp')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_currentState == AuthState.enterPhone) ...[
              const Text('Введите номер телефона', style: TextStyle(fontSize: 18), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Номер телефона (например: +79991112233)', border: OutlineInputBorder()),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 24),
              if (_isLoading) const Center(child: CircularProgressIndicator())
              else ElevatedButton(onPressed: _sendSms, child: const Text('Получить код')),
            ],

            if (_currentState == AuthState.enterCode) ...[
              Text('Код отправлен на номер\n${_phoneCtrl.text}', style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(
                controller: _codeCtrl,
                decoration: const InputDecoration(labelText: 'Код из СМС', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
              ),
              const SizedBox(height: 24),
              if (_isLoading) const Center(child: CircularProgressIndicator())
              else ElevatedButton(onPressed: _verifyCode, child: const Text('Подтвердить')),
              TextButton(
                onPressed: () => setState(() => _currentState = AuthState.enterPhone),
                child: const Text('Изменить номер'),
              ),
            ],

            if (_currentState == AuthState.enterName) ...[
              const Text('Добро пожаловать!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Придумайте имя пользователя, чтобы другие могли вас найти', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(
                controller: _usernameCtrl,
                decoration: const InputDecoration(labelText: 'Имя пользователя', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 24),
              if (_isLoading) const Center(child: CircularProgressIndicator())
              else ElevatedButton(onPressed: _completeRegistration, child: const Text('Войти в чаты')),
            ],
          ],
        ),
      ),
    );
  }
}