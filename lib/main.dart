import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/passcode_screen.dart';
import 'models/user.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// --- НОВОЕ: ИМПОРТ ПЛАГИНА ---
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; 

// ГЛОБАЛЬНЫЙ РУБИЛЬНИК ТЕМЫ
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

// Создаем глобальный объект для управления каналами
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// Эта штука ловит уведомления, когда приложение закрыто
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Ура! Пришло фоновое сообщение: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ==========================================
  // 🔔 СОЗДАЕМ НОВЫЙ "КАНАЛ" ДЛЯ ЗВУКА
  // ==========================================
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'meowly_channel_v2', // УНИКАЛЬНЫЙ ID (если потом захочешь другой звук, назовешь v3)
    'Уведомления чата', // Название в настройках телефона
    description: 'Канал со звуком мяуканья',
    importance: Importance.max,
    playSound: true,
    // ВАЖНО: Здесь пишем имя файла БЕЗ расширения .mp3!
    sound: RawResourceAndroidNotificationSound('meow_sound'), 
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
  // ==========================================

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'MessApp',
          debugShowCheckedModeBanner: false,
          
          theme: ThemeData(
            brightness: Brightness.light,
            colorSchemeSeed: Colors.blue,
            useMaterial3: true,
          ),
          
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.blue,
            useMaterial3: true,
          ),
          
          themeMode: currentMode,
          
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              
              if (snapshot.hasData && snapshot.data != null) {
                final firebaseUser = snapshot.data!;
                
                return FutureBuilder<SharedPreferences>(
                  future: SharedPreferences.getInstance(),
                  builder: (context, prefSnapshot) {
                    if (!prefSnapshot.hasData) {
                      return const Scaffold(body: Center(child: CircularProgressIndicator()));
                    }
                    
                    final prefs = prefSnapshot.data!;
                    final savedName = prefs.getString('username');
                    final savedAvatar = prefs.getString('avatarBase64');
                    final savedBio = prefs.getString('bio'); 

                    // --- МАГИЯ ПАРОЛЯ ---
                    // Проверяем, есть ли у нас сохраненный ПИН-код
                    final hasPasscode = prefs.getString('app_passcode') != null;
                    // -------------------

                    final myAppUser = UserModel(
                      id: firebaseUser.uid,
                      username: savedName ?? firebaseUser.email?.split('@')[0] ?? 'Без имени', // Заменил phoneNumber на email, так как у нас теперь вход по почте
                      avatarBase64: savedAvatar, 
                      bio: savedBio, 
                      isActive: true,
                    );

                    // Если пароль ЕСТЬ -> отправляем в нашу обертку, которая сначала спросит ПИН
                    if (hasPasscode) {
                      return PasscodeLockWrapper(user: myAppUser);
                    } 
                    
                    // Если пароля НЕТ -> сразу пускаем в чаты
                    return ChatListScreen(currentUser: myAppUser);
                  },
                );
              }
              
              // Если пользователь не авторизован - кидаем на экран входа
              return const LoginScreen();
            },
          ),
        );
      },
    );
  } 
}

// --- НОВЫЙ КЛАСС: ОБЕРТКА ДЛЯ БЛОКИРОВКИ ЭКРАНА ---
// Этот виджет сначала показывает экран ввода пароля, а после успеха - показывает чаты
class PasscodeLockWrapper extends StatefulWidget {
  final UserModel user;
  const PasscodeLockWrapper({super.key, required this.user});

  @override
  State<PasscodeLockWrapper> createState() => _PasscodeLockWrapperState();
}

class _PasscodeLockWrapperState extends State<PasscodeLockWrapper> {
  bool _isUnlocked = false; // По умолчанию заблокировано

  @override
  Widget build(BuildContext context) {
    // Если ввели правильный пароль - показываем сами чаты
    if (_isUnlocked) {
      return ChatListScreen(currentUser: widget.user);
    }
    
    // Иначе показываем экран ввода ПИН-кода
    return PasscodeScreen(
      isSetup: false, // Мы проверяем пароль, а не создаем его
      onSuccess: () {
        // Как только ввели верный пароль, говорим виджету обновиться!
        setState(() {
          _isUnlocked = true;
        });
      },
    );
  }
}