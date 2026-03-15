import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Наша новая память
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/chat_list_screen.dart';
import 'models/user.dart';

// ГЛОБАЛЬНЫЙ РУБИЛЬНИК ТЕМЫ (виден из любой точки приложения)
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Прямо перед запуском проверяем, какую тему ты ставил в прошлый раз
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder следит за рубильником. Как только он переключится — перерисует всё!
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'MessApp',
          debugShowCheckedModeBanner: false,
          
          // НАСТРОЙКА СВЕТЛОЙ ТЕМЫ
          theme: ThemeData(
            brightness: Brightness.light,
            colorSchemeSeed: Colors.blue,
            useMaterial3: true,
          ),
          
          // НАСТРОЙКА ТЕМНОЙ ТЕМЫ
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.blue, // Оставляем синие акценты, они круто смотрятся на черном
            useMaterial3: true,
          ),
          
          themeMode: currentMode, // Слушаем наш переключатель
          
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasData && snapshot.data != null) {
                final firebaseUser = snapshot.data!;
                final myAppUser = UserModel(
                  id: firebaseUser.uid,
                  username: firebaseUser.phoneNumber ?? 'Без имени',
                  isActive: true,
                );
                return ChatListScreen(currentUser: myAppUser);
              }
              return const LoginScreen();
            },
          ),
        );
      },
    );
  }
}