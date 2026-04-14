import 'dart:async';
import 'dart:convert'; 
import 'dart:io';
import 'dart:typed_data'; 
import 'dart:math' as math; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:intl/intl.dart'; 
import 'package:scroll_to_index/scroll_to_index.dart'; 
import 'package:image_picker/image_picker.dart'; 
import 'package:image_cropper/image_cropper.dart'; 
import 'package:record/record.dart'; 
import 'package:audioplayers/audioplayers.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:permission_handler/permission_handler.dart'; 
import '../models/user.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import 'user_profile_screen.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'package:confetti/confetti.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class ChatScreen extends StatefulWidget {
  final UserModel currentUser;
  final UserModel otherUser;

  const ChatScreen({super.key, required this.currentUser, required this.otherUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final AutoScrollController _scrollController = AutoScrollController();
  late ConfettiController _confettiController;
  bool _iBlockedHim = false; // Я заблокировал его
  bool _heBlockedMe = false; // Он заблокировал меня
  
bool _isVideoUploading = false; // <--- ДОБАВИТЬ ЭТО

  // Чат заблокирован, если хотя бы один из нас в черном списке
  bool get _isBlocked => _iBlockedHim || _heBlockedMe; 

  StreamSubscription<DocumentSnapshot>? _myBlockSubscription;
  StreamSubscription<DocumentSnapshot>? _otherBlockSubscription;

int _currentPinnedIndex = 0;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

bool _showCustomEmojiPanel = false; // Открыта ли панель
  final FocusNode _messageInputFocusNode = FocusNode(); // Следит за клавиатурой

 List<Message> _messages = [];
  bool _isLoading = true;
  bool _isThemeLoaded = false;
  double _bgBlur = 0.0; // <--- ДОБАВЬ ВОТ ЭТУ СТРОЧКУ
  Map<String, String> _localReactions = {}; // <--- НОВАЯ ПЕРЕМЕННАЯ ДЛЯ РЕАКЦИЙ
String _quickReaction = '❤️';
  Timer? _refreshTimer;
  Timer? _typingTimer;
  bool _isTyping = false;
  Message? _replyingTo;
  bool _showScrollToBottomBtn = false;
  Message? _editingMessage; // Сообщение, которое мы сейчас редактируем

// --- НАСТРОЙКИ ТЕМЫ ЧАТА ---
  // --- НАСТРОЙКИ ТЕМЫ ЧАТА ---
  Color _myBubbleColor = Colors.blue[700]!;
  Color _otherBubbleColor = Colors.grey[700]!; 
  Color? _chatBgColor; // <--- ДОБАВИЛИ ЭТУ СТРОЧКУ ДЛЯ ФОНА
  String? _backgroundImagePath;

  final Set<String> _animatedMessageIds = {};
  final Set<String> _selectedMessageIds = {}; // <--- ДОБАВИТЬ ЭТО
// ТОЧЕЧНЫЙ ФИКС: Память для расшифрованных фоток, чтобы не грузить телефон при скролле!
  
  // ТОЧЕЧНЫЙ ФИКС: Память для расшифрованных фоток, чтобы не грузить телефон при скролле!
  final Map<String, Uint8List> _decodedImageCache = {};

  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _recordTimer;

  bool get isSavedMessages => widget.currentUser.id == widget.otherUser.id;
  bool get _isTextFieldEmpty => _messageController.text.trim().isEmpty;

 @override
  void initState() {
    super.initState();
    _loadTheme(); // <--- ВОТ ЭТА НОВАЯ СТРОЧКА
    _loadReactions();
    _loadMessages();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    _messageController.addListener(_onTextChanged);
    _scrollController.addListener(_scrollListener);

   _myBlockSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUser.id)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>?;
        final blockedUsers = data?['blockedUsers'] as List<dynamic>? ?? [];
        setState(() {
          _iBlockedHim = blockedUsers.contains(widget.otherUser.id);
        });
      }
    });

    // --- 2. СЛУШАЕМ ЕГО ЧЕРНЫЙ СПИСОК (Вдруг он заблокировал меня) ---
    _otherBlockSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUser.id)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>?;
        final blockedUsers = data?['blockedUsers'] as List<dynamic>? ?? [];
        setState(() {
          _heBlockedMe = blockedUsers.contains(widget.currentUser.id);
        });
      }
    });
    
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _loadMessages();
    });

    // --- МАГИЯ КЛАВИАТУРЫ (Вот куда нужно было вставить) ---
    _messageInputFocusNode.addListener(() {
      if (_messageInputFocusNode.hasFocus && mounted) {
        // Если мы кликнули в поле ввода - прячем панель эмодзи
        setState(() => _showCustomEmojiPanel = false);
      }
    });
  }
  
Future<void> _loadReactions() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Загружаем уже поставленные реакции на сообщениях
    final String? reactionsJson = prefs.getString('saved_reactions');
    
    // 2. ЗАГРУЖАЕМ НАШ НОВЫЙ ВЫБРАННЫЙ ЭМОДЗИ ДЛЯ ДВОЙНОГО ТАПА
    final String? savedQuickReaction = prefs.getString('quick_reaction'); 

    if (mounted) {
      setState(() {
        if (reactionsJson != null) {
          _localReactions = Map<String, String>.from(jsonDecode(reactionsJson));
        }
        
        // Если в настройках что-то выбрано - берем это. Если пусто - ставим ❤️
        _quickReaction = savedQuickReaction ?? '❤️'; 
      });
    }
  }

  // Ставим или убираем реакцию
  Future<void> _setReaction(String msgId, String emoji) async {
    setState(() {
      if (_localReactions[msgId] == emoji) {
         _localReactions.remove(msgId); // Убираем, если нажали на ту же самую
      } else {
         _localReactions[msgId] = emoji; // Ставим новую
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_reactions', jsonEncode(_localReactions));
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final imagePath = prefs.getString('chat_bg_image');

    // Предзагрузка картинки, чтобы не было белого моргания!
    if (imagePath != null && mounted) {
      try {
        await precacheImage(FileImage(File(imagePath)), context);
      } catch (e) {
        print('Ошибка загрузки фона: $e');
      }
    }

    if (mounted) {
      setState(() {
        _myBubbleColor = Color(prefs.getInt('my_bubble_color') ?? Colors.blue[700]!.value);
        _otherBubbleColor = Color(prefs.getInt('other_bubble_color') ?? Colors.grey[700]!.value);
        
        final bgColorInt = prefs.getInt('chat_bg_color');
        if (bgColorInt != null) {
          _chatBgColor = Color(bgColorInt);
        } else {
          _chatBgColor = null;
        }
        
        _backgroundImagePath = imagePath;
        _bgBlur = prefs.getDouble('chat_bg_blur') ?? 0.0; // <--- ДОБАВЬ ВОТ ЭТУ СТРОЧКУ
        _isThemeLoaded = true; // <--- Экран готов к показу!
      });
    }
  }

  @override
  void dispose() {
    _myBlockSubscription?.cancel();     // <--- ДОБАВИТЬ
    _otherBlockSubscription?.cancel();  // <--- ДОБАВИТЬ
    _refreshTimer?.cancel();
    _typingTimer?.cancel();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _messageController.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    ApiService().setTypingStatus(widget.currentUser.id, widget.otherUser.id, false);
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {}); 
    if (isSavedMessages) return; 
    if (_messageController.text.isNotEmpty && !_isTyping) {
      _isTyping = true;
      ApiService().setTypingStatus(widget.currentUser.id, widget.otherUser.id, true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _isTyping = false;
      ApiService().setTypingStatus(widget.currentUser.id, widget.otherUser.id, false);
    });
  }

Future<void> _loadMessages() async {
    final api = ApiService();
    if (!isSavedMessages) await api.markMessagesAsRead(widget.currentUser.id, widget.otherUser.id);
    final newMessages = await api.getMessages(widget.currentUser.id, widget.otherUser.id);
    
    if (mounted) {
      if (_messages.isNotEmpty && newMessages.length > _messages.length) {
        final lastMsg = newMessages.last;
        if (lastMsg.senderId == widget.otherUser.id) {
          
          // --- УМНАЯ ПРОВЕРКА НАСТРОЕК УВЕДОМЛЕНИЙ ---
          final prefs = await SharedPreferences.getInstance();
          final bool playSound = prefs.getBool('inapp_sounds') ?? true;
          final bool playVibrate = prefs.getBool('inapp_vibrate') ?? true;

          // Играем звук и вибрируем ТОЛЬКО если рубильники включены
          if (playSound) SystemSound.play(SystemSoundType.click);
          if (playVibrate) HapticFeedback.mediumImpact();
          // ------------------------------------------
          
        }
      }
      
      setState(() { 
        _messages = newMessages; 
        _isLoading = false; 
      });
    }
  }
  

Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final lowerText = text.toLowerCase();
    _messageController.clear();
    _isTyping = false;
    ApiService().setTypingStatus(widget.currentUser.id, widget.otherUser.id, false);
    
    // --- 1. ЛОГИКА РЕДАКТИРОВАНИЯ СООБЩЕНИЯ ---
    if (_editingMessage != null) {
      // Здесь вызываем именно editMessage, а не sendMessage!
      final success = await ApiService().editMessage(widget.currentUser.id, widget.otherUser.id, _editingMessage!.id, text);
      
      setState(() => _editingMessage = null); // Сбрасываем плашку редактирования
      
      if (success) _loadMessages(); 
      
      return; // ЖЕСТКО ОСТАНАВЛИВАЕМ ФУНКЦИЮ, чтобы не отправилось новое сообщение
    }
    // -----------------------------------------

    // --- 2. ЛОГИКА ОТПРАВКИ НОВОГО СООБЩЕНИЯ ---
    final replyId = _replyingTo?.id;
    setState(() => _replyingTo = null);
    
    // Триггеры для конфетти
    if (lowerText.contains('поздравляю') || 
        lowerText.contains('с днем рождения') || 
        lowerText.contains('ура') || 
        lowerText.contains('с новым годом')) {
      _confettiController.play();
    }

    // Отправляем в базу
    // Отправляем в базу
    final success = await ApiService().sendMessage(widget.currentUser.id, widget.otherUser.id, text, replyToId: replyId);
    
    if (success) { 
      // ==========================================
      // 🚀 ПУШ ТОЛЬКО ДЛЯ ТЕКСТА
      // ==========================================
      ApiService().sendPushNotification(
        widget.otherUser.id,       
        widget.currentUser.username,   
        text                       
      );
      // ==========================================

      // --- УМНАЯ ПРОВЕРКА ВИБРАЦИИ ---
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('inapp_vibrate') ?? true) {
        HapticFeedback.lightImpact(); 
      }
      
      await _loadMessages(); 
      _scrollToBottom();

    } else { 
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка')));
    }
  } // Конец функции _sendMessage

// ==========================================
  // 📎 КРАСИВОЕ МЕНЮ ВЛОЖЕНИЙ (Шторка скрепки)
  // ==========================================
  void _showAttachmentMenu() {
    // Скрываем клавиатуру перед открытием меню (чтобы было красиво)
    FocusScope.of(context).unfocus(); 

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Для красивых закругленных краев
      builder: (context) => Container(
        padding: const EdgeInsets.only(top: 10, bottom: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor, // Цвет под тему телефона
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Wrap(
            children: [
              // Полосочка сверху (как ручка для перетаскивания)
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              
              // --- КНОПКА ФОТО ---
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.image, color: Colors.white),
                ),
                title: const Text('Фотографии', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                subtitle: const Text('Отправить картинки из галереи'),
                onTap: () {
                  Navigator.pop(context); // Сначала закрываем шторку
                  _pickAndSendImage();    // Запускаем твою функцию фото
                },
              ),
              
              const Divider(height: 1, indent: 70), // Тонкая линия между кнопками
              
              // --- КНОПКА ВИДЕО ---
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.purple,
                  child: Icon(Icons.videocam, color: Colors.white),
                ),
                title: const Text('Видео', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                subtitle: const Text('Отправить тяжелое видео в облако'),
                onTap: () {
                  Navigator.pop(context); // Сначала закрываем шторку
                  _pickAndSendVideo();    // Запускаем твою новую функцию видео
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

// ==========================================
  // 🎬 ОТПРАВКА ВИДЕО
  // ==========================================
  Future<void> _pickAndSendVideo() async {
    final picker = ImagePicker();
    // Открываем галерею специально для видео
    final XFile? pickedFile = await picker.pickVideo(source: ImageSource.gallery);

    if (pickedFile != null) {
      // Показываем пользователю, что нужно подождать
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Загрузка видео... Это может занять минутку ⏳')));

      final videoFile = File(pickedFile.path);
      setState(() => _isVideoUploading = true); 

      // 1. Грузим в Cloudinary
      final videoUrl = await ApiService().uploadVideoToCloudinary(videoFile);
      if (!mounted) return;

      // Выключаем плашку, так как видео загрузилось (или выдало ошибку)
      setState(() => _isVideoUploading = false);

      if (videoUrl != null) {
      // 1. Грузим в Cloudinary
      final videoUrl = await ApiService().uploadVideoToCloudinary(videoFile);

if (!mounted) return;

      if (videoUrl != null) {
        // 2. Если загрузилось, отправляем ссылку в чат
        final currentReplyId = _replyingTo?.id;
        setState(() => _replyingTo = null);

        final success = await ApiService().sendMessage(
          widget.currentUser.id, 
          widget.otherUser.id, 
          '🎬 Видео', 
          replyToId: currentReplyId,
          videoUrl: videoUrl, // Передаем ссылку!
        );

        if (success) { 
          // 3. Отправляем пуш-уведомление
          ApiService().sendPushNotification(
            widget.otherUser.id,       
            widget.currentUser.username,   
            '🎬 Видео' 
          );

          await _loadMessages(); 
          _scrollToBottom(); 
        } else if (mounted) { 
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка отправки сообщения.'))); 
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка загрузки видео в облако ☁️')));
      }
    }
  }
  }

Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    // 1. УБРАЛИ ЖЕСТКИЕ ОГРАНИЧЕНИЯ РАЗМЕРА И УЛУЧШИЛИ КАЧЕСТВО
    final List<XFile> pickedFiles = await picker.pickMultiImage(
      imageQuality: 80, // Было 25, стало 80!
    );

    if (pickedFiles.isNotEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Загрузка HD фото... 🚀')));

      List<String> uploadedUrls = []; // Сюда будем складывать ссылки из облака
      final images = pickedFiles.take(10).toList();

      if (images.length == 1) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: images.first.path, 
          compressQuality: 80, // Здесь тоже улучшили качество
          // Твои настройки дизайна остались нетронутыми:
          uiSettings: [ 
            AndroidUiSettings(
              toolbarTitle: 'Редактировать', 
              toolbarColor: const Color(0xFF1C1C1E), 
              toolbarWidgetColor: Colors.white, 
              backgroundColor: Colors.black, 
              activeControlsWidgetColor: Colors.blue, 
              dimmedLayerColor: Colors.black87, 
              hideBottomControls: false
            ) 
          ],
        );
        if (croppedFile != null) {
          // 2. ГРУЗИМ ФОТО В CLOUDINARY
          final url = await ApiService().uploadImageToCloudinary(File(croppedFile.path));
          if (url != null) uploadedUrls.add(url);
        } else {
          return; 
        }
      } 
      else {
        if (pickedFiles.length > 10 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Максимум 10 фото! Остальные проигнорированы.')));
        }
        for (var img in images) {
          // 3. ГРУЗИМ НЕСКОЛЬКО ФОТО В CLOUDINARY ПО ОЧЕРЕДИ
          final url = await ApiService().uploadImageToCloudinary(File(img.path));
          if (url != null) uploadedUrls.add(url);
        }
      }

      if (uploadedUrls.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка загрузки в облако.')));
        return;
      }

      final caption = _messageController.text.isNotEmpty ? _messageController.text : '📸 Фото';
      _messageController.clear();
      final currentReplyId = _replyingTo?.id;
      setState(() => _replyingTo = null);

      // 4. ОТПРАВЛЯЕМ ССЫЛКИ В БАЗУ ДАННЫХ
      final success = await ApiService().sendMessage(
        widget.currentUser.id, 
        widget.otherUser.id, 
        caption, 
        imageUrls: uploadedUrls, // <--- ВОТ ОНО! Передаем ссылки вместо Base64
        replyToId: currentReplyId
      );

      if (success) { 
        // Твои пуши и прокрутка работают как швейцарские часы
        ApiService().sendPushNotification(
          widget.otherUser.id,       
          widget.currentUser.username,   
          caption 
        );

        await _loadMessages(); 
        _scrollToBottom(); 
      } else if (mounted) { 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка при отправке.'))); 
      }
    }
  } // Конец функции _pickAndSendImage

  Future<void> _startRecording() async {
    try {
      if (await Permission.microphone.request().isGranted) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/temp_record.m4a';
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        setState(() { 
          _isRecording = true; 
          _recordDuration = 0; 
        });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) => setState(() => _recordDuration++));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нужно разрешение!')));
      }
    } catch (e) { 
      print(e); 
    }
  }

Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    final path = await _audioRecorder.stop();
    setState(() => _isRecording = false);
    
    if (path != null && _recordDuration > 0) {
      final bytes = await File(path).readAsBytes();
      final replyId = _replyingTo?.id;
      setState(() => _replyingTo = null);
      
      final success = await ApiService().sendMessage(
        widget.currentUser.id, 
        widget.otherUser.id, 
        '🎤 Голосовое сообщение', 
        replyToId: replyId, 
        audioBase64: base64Encode(bytes)
      );
      
      if (success) { 
        // ==========================================
        // 🚀 ПУШ ТОЛЬКО ДЛЯ ГОЛОСОВОГО СООБЩЕНИЯ
        // ==========================================
        ApiService().sendPushNotification(
          widget.otherUser.id,       
          widget.currentUser.username,   
          '🎤 Голосовое сообщение' 
        );
        // ==========================================

        await _loadMessages(); 
        _scrollToBottom(); 
      }
    }
  }

  Future<void> _cancelRecording() async { 
    _recordTimer?.cancel(); 
    await _audioRecorder.stop(); 
    setState(() { 
      _isRecording = false; 
      _recordDuration = 0; 
    }); 
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0, // <-- ТЕПЕРЬ НИЗ ЭТО 0.0! (Никаких вычислений длины списка)
          duration: const Duration(milliseconds: 300), 
          curve: Curves.easeOut
        );
      }
    });
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    final currentScroll = _scrollController.position.pixels;
    // В перевернутом списке мы скроллим вверх (pixels растут от 0).
    if (currentScroll > 200) {
      if (!_showScrollToBottomBtn) setState(() => _showScrollToBottomBtn = true);
    } else {
      if (_showScrollToBottomBtn) setState(() => _showScrollToBottomBtn = false);
    }
  }

  void _scrollToMessage(String msgId) {
    // Ищем индекс в ПЕРЕВЕРНУТОМ списке!
    final reversedList = _messages.reversed.toList();
    final index = reversedList.indexWhere((m) => m.id == msgId);
    if (index != -1) {
      _scrollController.scrollToIndex(
        index, 
        preferPosition: AutoScrollPosition.middle, 
        duration: const Duration(milliseconds: 500)
      );
    }
  }

 

  String _getStatusText(UserModel user) {
    if (user.isOnline) return 'В сети';
    if (user.lastSeen == null) return 'Был(а) недавно';
    final time = DateFormat('HH:mm').format(user.lastSeen!.toLocal());
    return 'Был(а) в $time';
  }
void _toggleSelection(String msgId) {
    setState(() {
      if (_selectedMessageIds.contains(msgId)) {
        _selectedMessageIds.remove(msgId);
      } else {
        if (_selectedMessageIds.length >= 100) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Можно выбрать не более 100 сообщений 😅')));
          return;
        }
        _selectedMessageIds.add(msgId);
      }
    });
  }

  void _showBulkDeleteDialog() {
    bool deleteForEveryone = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Удалить ${_selectedMessageIds.length} сообщений?'),
          content: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Вы уверены?'), const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(value: deleteForEveryone, onChanged: (val) => setDialogState(() => deleteForEveryone = val ?? false)),
                  Expanded(child: Text('Удалить для ${widget.otherUser.username}'))
                ]
              )
            ]
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                for (String id in _selectedMessageIds.toList()) {
                  await ApiService().deleteMessage(widget.currentUser.id, widget.otherUser.id, id, deleteForEveryone);
                }
                setState(() => _selectedMessageIds.clear());
                _loadMessages();
              },
              child: const Text('Удалить', style: TextStyle(color: Colors.red))
            ),
          ],
        )
      ),
    );
  }

  Future<void> _bulkForwardMessages() async {
    final messenger = ScaffoldMessenger.of(context);
    final messagesToForward = _messages.where((m) => _selectedMessageIds.contains(m.id)).toList();
    
    for (var msg in messagesToForward) {
      String textToForward = msg.messageText;
      if ((msg.imagesBase64 != null && msg.imagesBase64!.isNotEmpty) || msg.imageBase64 != null || msg.audioBase64 != null) {
        if (textToForward == '📸 Фото' || textToForward == '🎤 Голосовое сообщение') textToForward = '';
      } else {
        textToForward = '[Переслано]: \n$textToForward';
      }
      await ApiService().sendMessage(
        widget.currentUser.id, widget.currentUser.id, textToForward,
        imageBase64: msg.imageBase64, imagesBase64: msg.imagesBase64, audioBase64: msg.audioBase64
      );
    }
    setState(() => _selectedMessageIds.clear());
    messenger.showSnackBar(SnackBar(content: Text('Сохранено ${messagesToForward.length} в Избранное 🐾')));
  }
  void _showDeleteDialog(Message msg) {
    final isMyMsg = msg.senderId == widget.currentUser.id;
    final diffMinutes = DateTime.now().toUtc().difference(msg.sentAt.toUtc()).inMinutes;
    final canDeleteForEveryone = isMyMsg || diffMinutes <= 10;
    bool deleteForEveryone = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Удалить?'),
          content: Column(
            mainAxisSize: MainAxisSize.min, 
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              const Text('Вы уверены?'), 
              const SizedBox(height: 16),
              if (canDeleteForEveryone) 
                Row(
                  children: [
                    Checkbox(
                      value: deleteForEveryone, 
                      onChanged: (val) => setDialogState(() => deleteForEveryone = val ?? false)
                    ), 
                    Expanded(child: Text('Удалить для ${widget.otherUser.username}'))
                  ]
                )
            ]
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('Отмена')
            ),
            TextButton(
              onPressed: () async { 
                Navigator.pop(context); 
                final success = await ApiService().deleteMessage(
                  widget.currentUser.id, 
                  widget.otherUser.id, 
                  msg.id, 
                  deleteForEveryone
                ); 
                if (success) _loadMessages(); 
              }, 
              child: const Text('Удалить', style: TextStyle(color: Colors.red))
            ),
          ],
        )
      ),
    );
  }

  void _showMessageOptions(Message msg) {
    // Список доступных реакций
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
        child: Wrap(
          children: [
            // --- ПАНЕЛЬ РЕАКЦИЙ ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: emojis.map((emoji) => GestureDetector(
                  onTap: () {
                    Navigator.pop(context); // Закрываем меню
                    _setReaction(msg.id, emoji); // Ставим реакцию
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      // Подсвечиваем синим, если реакция уже стоит
                      color: _localReactions[msg.id] == emoji ? Colors.blue.withOpacity(0.3) : Colors.grey.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                )).toList(),
              ),
            ),
        
            const Divider(height: 1),
            
            const Padding(
              padding: EdgeInsets.all(16.0), 
              child: Text('Действия', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
            ),

            // --- НОВАЯ КНОПКА ДЛЯ ВЫДЕЛЕНИЯ СООБЩЕНИЙ ---
            ListTile(
              leading: const Icon(Icons.check_circle_outline, color: Colors.blue), 
              title: const Text('Выбрать'), 
              onTap: () { 
                Navigator.pop(context); 
                _toggleSelection(msg.id); // Включаем режим массового выделения
              }
            ),
// --- НОВАЯ КНОПКА ЗАКРЕПА ---
            ListTile(
              leading: Icon(msg.isPinned ? Icons.push_pin_outlined : Icons.push_pin, color: Colors.blue), 
              title: Text(msg.isPinned ? 'Открепить' : 'Закрепить'), 
              onTap: () async { 
                // 1. ЖЕСТКО ГАСИМ ФОКУС И КЛАВИАТУРУ:
                FocusScope.of(context).unfocus();
                Navigator.pop(context); // Закрываем меню
                // Отправляем в базу новый статус (меняем на противоположный)
                final success = await ApiService().togglePinMessage(
                  widget.currentUser.id, 
                  widget.otherUser.id, 
                  msg.id, 
                  !msg.isPinned
                );
                if (success) _loadMessages(); // Перезагружаем чат, чтобы плашка появилась
              }
            ),
            // -----------------------------
            // --- ТВОИ СТАРЫЕ КНОПКИ ---
            
            // --- НОВАЯ КНОПКА: СКОПИРОВАТЬ ---
            // Показываем кнопку только если это реально текст (а не фото/гс/стикер)
            if (msg.messageText.isNotEmpty && 
                msg.messageText != '📸 Фото' && 
                msg.messageText != '🎤 Голосовое сообщение' && 
                !msg.messageText.startsWith('[STICKER]'))
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.blue), 
                title: const Text('Скопировать'), 
                onTap: () { 
                  Navigator.pop(context); // Закрываем меню
                  Clipboard.setData(ClipboardData(text: msg.messageText)); // Копируем!
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Текст скопирован')));
                }
              ),
            // ---------------------------------
            // --- ТВОИ СТАРЫЕ КНОПКИ ---
            ListTile(
              leading: const Icon(Icons.reply, color: Colors.blue), 
              title: const Text('Ответить'), 
              onTap: () { 
                Navigator.pop(context); 
                setState(() => _replyingTo = msg); 
              }
            ),
            ListTile(
              leading: const Icon(Icons.pets, color: Colors.blue), 
              title: const Text('В Избранное'), 
              onTap: () async {
                Navigator.pop(context);
                final messenger = ScaffoldMessenger.of(context);
                String textToForward = msg.messageText;
                
                if ((msg.imagesBase64 != null && msg.imagesBase64!.isNotEmpty) || msg.imageBase64 != null || msg.audioBase64 != null) {
                  if (textToForward == '📸 Фото' || textToForward == '🎤 Голосовое сообщение') {
                    textToForward = '';
                  }
                } else {
                  textToForward = '[Переслано]: \n$textToForward';
                }
                
                final success = await ApiService().sendMessage(
                  widget.currentUser.id, 
                  widget.currentUser.id, 
                  textToForward, 
                  imageBase64: msg.imageBase64, 
                  imagesBase64: msg.imagesBase64, 
                  audioBase64: msg.audioBase64
                );
                if (success) messenger.showSnackBar(const SnackBar(content: Text('Сохранено в Избранное 🐾')));
              }
            ),
            // --- НОВАЯ КНОПКА: ИЗМЕНИТЬ ---
            if (msg.senderId == widget.currentUser.id && // Только мои
                msg.messageText.isNotEmpty && 
                msg.messageText != '📸 Фото' && 
                msg.messageText != '🎤 Голосовое сообщение' && 
                !msg.messageText.startsWith('[STICKER]'))
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue), 
                title: const Text('Изменить'), 
                onTap: () { 
                  Navigator.pop(context); // Закрываем меню
                  setState(() {
                    _editingMessage = msg; // Запоминаем, что редактируем
                    _replyingTo = null; // Сбрасываем "ответ", если он был
                    _messageController.text = msg.messageText; // Вставляем старый текст в поле
                  });
                  _messageInputFocusNode.requestFocus(); // Автоматически открываем клавиатуру
                }
              ),
            // ---------------------------------
           ListTile(
              leading: const Icon(Icons.delete, color: Colors.red), 
              title: const Text('Удалить', style: TextStyle(color: Colors.red)), 
              onTap: () { 
                Navigator.pop(context); 
                _showDeleteDialog(msg);
              }
            ),
         ], // Закрываем children
            ), // Закрываем Wrap
          ), // Закрываем SingleChildScrollView
        ), // Закрываем SafeArea
      ); // Закрываем showModalBottomSheet!
  }
  

  Widget _buildReplyBubble(String replyId, bool isDarkMode, bool isMe) {
    final originalMsg = _messages.where((m) => m.id == replyId).firstOrNull;
  final bubbleColor = isMe ? _myBubbleColor : _otherBubbleColor;
  
    if (originalMsg == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6), 
        padding: const EdgeInsets.all(8), 
        decoration: BoxDecoration(
          color: bubbleColor.withOpacity(0.5), 
          border: const Border(left: BorderSide(color: Colors.grey, width: 3)), 
          borderRadius: BorderRadius.circular(4)
        ), 
        child: const Text('Сообщение удалено', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
      );
    }
    
    return GestureDetector(
      onTap: () => _scrollToMessage(replyId), 
      child: Container(
        margin: const EdgeInsets.only(bottom: 6), 
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bubbleColor.withOpacity(0.5), 
          border: const Border(left: BorderSide(color: Colors.blue, width: 3)), 
          borderRadius: BorderRadius.circular(4)
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              originalMsg.senderId == widget.currentUser.id ? 'Вы' : widget.otherUser.username, 
              style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)
            ),
            const SizedBox(height: 2),
            Text(
              originalMsg.messageText, 
              maxLines: 1, 
              overflow: TextOverflow.ellipsis, 
              style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black54, fontSize: 13)
            ),
          ],
        ),
      ),
    );
  }

Widget _buildMessageAlbum(Message msg) {
    // 1. Проверяем, есть ли у нас HD-ссылки или старый Base64
    final List<String> images = msg.imageUrls ?? msg.imagesBase64 ?? (msg.imageBase64 != null ? [msg.imageBase64!] : []);
    final bool isNetwork = msg.imageUrls != null;

    if (images.isEmpty) return const SizedBox.shrink();

    // Одиночное фото
    if (images.length == 1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: GestureDetector(
          onTap: () => _openGallery(msg.id, 0),
          child: Hero(
            tag: '${msg.id}_0',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: isNetwork 
                ? Image.network(images[0], width: 220, fit: BoxFit.cover) 
                : Image.memory(base64Decode(images[0]), width: 220, fit: BoxFit.cover),
            ),
          ),
        ),
      );
    }

    // Сетка для нескольких фото
    int crossAxisCount = images.length == 2 ? 2 : 3;
    if (images.length == 4) crossAxisCount = 2;

    return Container(
      width: 260,
      padding: const EdgeInsets.only(bottom: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: images.length > 9 ? 9 : images.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => _openGallery(msg.id, index),
              child: Hero(
                tag: '${msg.id}_$index',
                child: isNetwork 
                  ? Image.network(images[index], fit: BoxFit.cover) 
                  : Image.memory(base64Decode(images[index]), fit: BoxFit.cover),
              ),
            );
          },
        ),
      ),
    );
  }

void _openGallery(String messageId, int innerIndex) {
    List<Map<String, dynamic>> allMedia = [];
    int tappedIndex = 0;

    for (var m in _messages) {
      // Собираем ссылки (HD)
      if (m.imageUrls != null && m.imageUrls!.isNotEmpty) {
        for (int i = 0; i < m.imageUrls!.length; i++) {
          if (m.id == messageId && i == innerIndex) tappedIndex = allMedia.length;
          allMedia.add({'url': m.imageUrls![i], 'tag': '${m.id}_$i'});
        }
      } 
      // Собираем старый Base64
      else if (m.imagesBase64 != null && m.imagesBase64!.isNotEmpty) {
        for (int i = 0; i < m.imagesBase64!.length; i++) {
          if (m.id == messageId && i == innerIndex) tappedIndex = allMedia.length;
          allMedia.add({'base64': m.imagesBase64![i], 'tag': '${m.id}_$i'});
        }
      }
    }

    Navigator.push(context, PageRouteBuilder(
      opaque: false,
      pageBuilder: (context, a1, a2) => FullScreenImageScreen(
        mediaList: allMedia, 
        initialIndex: tappedIndex
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // --- ДОБАВЛЯЕМ ФИЛЬТРАЦИЮ ---
    final filteredMessages = _isSearching && _searchController.text.isNotEmpty
        ? _messages.where((m) => m.messageText.toLowerCase().contains(_searchController.text.toLowerCase())).toList()
        : _messages;
        final reversedMessages = filteredMessages.reversed.toList();
    // ----------------------------
    if (!_isThemeLoaded) {
      return Scaffold(backgroundColor: Theme.of(context).scaffoldBackgroundColor);
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

   // 1. Собираем все закрепленные сообщения
    final pinnedMessages = _messages.where((m) => m.isPinned).toList();
    
    // 2. ЖЕСТКО СОРТИРУЕМ их по времени отправки (от самых старых к новым)
    pinnedMessages.sort((a, b) => a.sentAt.compareTo(b.sentAt));

    Message? currentPinnedMsg;
    if (pinnedMessages.isNotEmpty) {
      // 3. Логика как в Telegram: показываем сначала самое НОВОЕ закрепленное сообщение (которое ниже в чате). 
      // При клике по плашке листаем вверх к более старым закрепам.
      currentPinnedMsg = pinnedMessages[pinnedMessages.length - 1 - (_currentPinnedIndex % pinnedMessages.length)];
    }

    return Scaffold(
      appBar: _selectedMessageIds.isNotEmpty
          ? AppBar(
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedMessageIds.clear())),
              title: Text('Выбрано: ${_selectedMessageIds.length}'),
              actions: [
                // --- НОВАЯ КНОПКА КОПИРОВАНИЯ (МАССОВАЯ) ---
                IconButton(
                  icon: const Icon(Icons.copy), 
                  onPressed: () {
                    // 1. Собираем выбранные сообщения и сортируем по времени
                    final selectedMessages = _messages.where((m) => _selectedMessageIds.contains(m.id)).toList();
                    selectedMessages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
                    
                    // 2. Склеиваем текст (игнорируем фотки, гс и стикеры)
                    final textToCopy = selectedMessages
                        .where((m) => m.messageText.isNotEmpty && 
                                      m.messageText != '📸 Фото' && 
                                      m.messageText != '🎤 Голосовое сообщение' &&
                                      !m.messageText.startsWith('[STICKER]'))
                        .map((m) => m.messageText)
                        .join('\n\n'); // Разделяем сообщения пустой строкой
                        
                    // 3. Копируем в буфер и закрываем выделение
                    if (textToCopy.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: textToCopy));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Текст скопирован')));
                    }
                    setState(() => _selectedMessageIds.clear());
                  }
                ),
                // Твои старые кнопки
                IconButton(icon: const Icon(Icons.pets), onPressed: _bulkForwardMessages),
                IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: _showBulkDeleteDialog),
              ],
            )
          : AppBar(
              titleSpacing: 0, 
              
              // --- 1. МЕНЯЕМ ЗАГОЛОВОК (ПОИСК ИЛИ ИМЯ) ---
              title: _isSearching
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: const InputDecoration(
                        hintText: 'Поиск...',
                        hintStyle: TextStyle(color: Colors.white70),
                        border: InputBorder.none,
                      ),
                      onChanged: (value) => setState(() {}),
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque, 
                      onTap: () { 
                        if (!isSavedMessages) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(
                            user: widget.otherUser, 
                            chatMessages: _messages
                          )));
                        }
                      },
                      child: Row(
                        children: [
                          const SizedBox(width: 10), 
                          
                          Expanded( 
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isSavedMessages ? 'Избранное' : widget.otherUser.username, 
                                  style: const TextStyle(fontSize: 18)
                                ),
                                if (!isSavedMessages)
                                  StreamBuilder<bool>(
                                    stream: ApiService().getTypingStatus(widget.currentUser.id, widget.otherUser.id),
                                    builder: (context, snapshot) {
                                      if (snapshot.data == true) {
                                        return const Row(
                                          children: [
                                            Text('Печатает', style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)), 
                                            SizedBox(width: 4), 
                                            TypingIndicator()
                                          ]
                                        );
                                      }
                                      return Text(
                                        _getStatusText(widget.otherUser), 
                                        style: TextStyle(
                                          fontSize: 12, 
                                          fontWeight: FontWeight.normal, 
                                          color: widget.otherUser.isOnline ? Colors.green[400] : Colors.grey[400]
                                        )
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
              // --- 2. ДОБАВЛЯЕМ КНОПКУ-ЛУПУ СПРАВА ---
              actions: [
                IconButton(
                  icon: Icon(_isSearching ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) _searchController.clear();
                    });
                  },
                ),
              ],
            ),
      body: Stack(
      alignment: Alignment.topCenter,
      children: [
        Container(
        decoration: BoxDecoration(
          // Если мы выбрали цвет, ставим его, иначе стандартный (с учетом ночного режима)
          color: _chatBgColor ?? Theme.of(context).scaffoldBackgroundColor, 
          image: _backgroundImagePath != null && _backgroundImagePath!.isNotEmpty
              ? DecorationImage(
                  image: FileImage(File(_backgroundImagePath!)),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        // --- ВМЕСТО child: Column( ВСТАВЛЯЕМ ЭТО ---
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _bgBlur, sigmaY: _bgBlur), // Берем значение с ползунка
          child: Container(
            // Если стоит фото, слегка затемняем его для читаемости
            color: _backgroundImagePath != null ? Colors.black.withOpacity(0.2) : Colors.transparent,
            child: Column(
        children: [
          if (currentPinnedMsg != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: GestureDetector(
                        onTap: () {
                          // Прыгаем к сообщению
                          _scrollToMessage(currentPinnedMsg!.id);
                          
                          // Если закрепов больше одного - листаем плашку на следующий
                          if (pinnedMessages.length > 1) {
                            setState(() {
                              _currentPinnedIndex++;
                            });
                          }
                        },
                        child: Material(
                          elevation: 4, 
                          borderRadius: BorderRadius.circular(15), 
                          color: isDarkMode ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.7), 
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                // СЛЕВА: Иконка закрепа и Текст
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.push_pin, color: Colors.blueAccent, size: 18),
                                          const SizedBox(width: 8),
                                          const Text('Закрепленное сообщение', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        currentPinnedMsg.messageText.isEmpty && currentPinnedMsg.imagesBase64 != null ? '📸 Фото' : currentPinnedMsg.messageText, 
                                        maxLines: 1, 
                                        overflow: TextOverflow.ellipsis, 
                                        style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black87, fontSize: 13)
                                      ),
                                    ],
                                  ),
                                ),
                                
                                const SizedBox(width: 12), // Отступ до котика

                                // СПРАВА: КОТИК-ДЕРЖАТЕЛЬ! 🐈
                                Image.asset(
                                  'assets/images/cat_hold.png', 
                                  height: 40, 
                                  color: isDarkMode ? Colors.white : Colors.black, 
                                  colorBlendMode: BlendMode.srcIn, 
                                ),

                                // КНОПКА ОТКРЕПЛЕНИЯ
                                IconButton(
                                  icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                                  onPressed: () async {
                                    await ApiService().togglePinMessage(widget.currentUser.id, widget.otherUser.id, currentPinnedMsg!.id, false);
                                    // Сбрасываем индекс, чтобы плашка не перепрыгнула через одно сообщение после удаления
                                    setState(() { _currentPinnedIndex = 0; });
                                    _loadMessages();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // --- КОНЕЦ ПЛАШКИ С КОТИКОМ ---
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty 
                      ? Center(child: Text(isSavedMessages ? 'Здесь можно хранить заметки' : 'Сообщений пока нет'))
                      : ListView.builder(
                          reverse: true, // <--- САМАЯ ВАЖНАЯ СТРОЧКА! (Включает механику Telegram)
                          controller: _scrollController, 
                          cacheExtent: 3000, 
                          itemCount: reversedMessages.length, // <--- БЕРЕМ ПЕРЕВЕРНУТЫЙ СПИСОК
                          itemBuilder: (context, index) {
  // 1. Возвращаем потерянные строчки:
  // 2. БЕРЕМ СООБЩЕНИЕ ИЗ ОТФИЛЬТРОВАННОГО СПИСКА
  final msg = reversedMessages[index];
  final isMe = isSavedMessages ? true : msg.senderId == widget.currentUser.id;

  // 2. Оставляем ТОЛЬКО новые цвета:
  final bubbleColor = isMe ? _myBubbleColor : _otherBubbleColor;
  final textColor = bubbleColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

  // Проверяем, новое ли это сообщение
                            // Проверяем, новое ли это сообщение
                            bool isNewMessage = !_animatedMessageIds.contains(msg.id);
                            if (isNewMessage) {
                              _animatedMessageIds.add(msg.id);
                            }

                            Widget messageContent = Align( 
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: CustomSwipeToReply(
                                onReply: () => setState(() => _replyingTo = msg),
                                child: GestureDetector(
                                  onDoubleTap: () {
                                    if (_selectedMessageIds.isEmpty) {
                                      _setReaction(msg.id, _quickReaction); // Ставим быструю реакцию
                                    }
                                  },
                                  onLongPress: () {
                                    // Теперь долгое нажатие просто выделяет сообщение (включает режим массовых действий)
                                    _toggleSelection(msg.id);
                                  },
                                  onTap: () {
                                    if (_selectedMessageIds.isNotEmpty) {
                                      // Если режим выделения УЖЕ включен, клик просто выделяет/снимает выделение с сообщения
                                      _toggleSelection(msg.id);
                                    } else {
                                      // Если режим выделения ВЫКЛЮЧЕН, обычный быстрый клик открывает меню (закрепить, удалить и т.д.)
                                      _showMessageOptions(msg);
                                    }
                                  },

                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      
                                      // 1. Твой стандартный пузырь сообщения
                                      Container(
                                        foregroundDecoration: _selectedMessageIds.contains(msg.id)
                                            ? BoxDecoration(
                                                color: Colors.blue.withOpacity(0.3),
                                                borderRadius: BorderRadius.circular(16),
                                              )
                                            : null,
                                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8), 
                                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                        decoration: BoxDecoration(
                                          color: bubbleColor, 
                                          borderRadius: BorderRadius.circular(16)
                                        ),
                                        // ВЕСЬ ТВОЙ СТАРЫЙ child: Column(...) ОСТАЕТСЯ ЗДЕСЬ БЕЗ ИЗМЕНЕНИЙ
                                        child: Column(
                                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                          children: [
       _buildMessageAlbum(msg),
if (msg.audioBase64 != null) VoiceMessagePlayer(base64Audio: msg.audioBase64!, messageId: msg.id, isMe: isMe, isDarkMode: isDarkMode),

// --- ВОТ ЭТУ СТРОКУ МЫ ДОБАВИЛИ ДЛЯ ВИДЕО ---
if (msg.videoUrl != null) VideoMessagePlayer(videoUrl: msg.videoUrl!, messageId: msg.id),

// --- А ТУТ ДОБАВИЛИ ПРОВЕРКУ '🎬 Видео', ЧТОБЫ СКРЫТЬ ДУБЛИРУЮЩИЙСЯ ТЕКСТ ---
if (msg.messageText.isNotEmpty && msg.messageText != '📸 Фото' && msg.messageText != '🎤 Голосовое сообщение' && msg.messageText != '🎬 Видео' && msg.messageText != '📷 Фото')
          
          // --- ПРОВЕРЯЕМ: ЭТО СТИКЕР ИЛИ ОБЫЧНЫЙ ТЕКСТ? ---
          msg.messageText.startsWith('[STICKER]')
              ? Image.asset(
                  // Убираем слово [STICKER], оставляя только путь к картинке
                  msg.messageText.replaceAll('[STICKER]', ''),
                  width: 140, // Размер стикера в чате
                  height: 140,
                  fit: BoxFit.contain,
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: SmartMessageText(text: msg.messageText, baseStyle: TextStyle(fontSize: 16, color: textColor)),
                ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                              children: [
                                                Text(msg.time, style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white70 : Colors.black54)),
                                                if (msg.isEdited)
                                                  Text(' изм.', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: isDarkMode ? Colors.white54 : Colors.black45)),
                                                if (isMe && !isSavedMessages) ...[
                                                  const SizedBox(width: 4),
                                                  Icon(msg.isRead ? Icons.done_all : Icons.done, size: 16, color: msg.isRead ? (isDarkMode ? Colors.lightBlueAccent : Colors.blue[700]) : (isDarkMode ? Colors.white54 : Colors.black45)),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      
                                      // 2. ОТОБРАЖЕНИЕ РЕАКЦИИ С АНИМАЦИЕЙ
                                      if (_localReactions.containsKey(msg.id))
                                        Positioned(
                                          bottom: -4,
                                          right: isMe ? 12 : null,
                                          left: isMe ? null : 12,
                                          // --- ВОТ ОНА, МАГИЯ АНИМАЦИИ ---
                                          child: TweenAnimationBuilder<double>(
                                            // Анимируем размер от 0.0 (невидимый) до 1.0 (нормальный)
                                            tween: Tween<double>(begin: 0.0, end: 1.0), 
                                            // Длительность прыжка (400 миллисекунд)
                                            duration: const Duration(milliseconds: 400),
                                            // Эффект пружинки!
                                            curve: Curves.elasticOut, 
                                            builder: (context, scale, child) {
                                              return Transform.scale(
                                                scale: scale,
                                                child: child,
                                              );
                                            },
                                            // А вот и сам наш контейнер со смайликом
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: isDarkMode ? Colors.grey[800] : Colors.white,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, spreadRadius: 1)
                                                ]
                                              ),
                                              child: Text(_localReactions[msg.id]!, style: const TextStyle(fontSize: 16)),
                                            ),
                                          ),
                                        ),
                    
                                    ],
                                  ),
                                ),
                              ),
                            );
                           return AutoScrollTag(
                              key: ValueKey(msg.id), // ФИКС: Ключ по ID сообщения, а не по индексу. Это убивает прыжки навсегда.
                              controller: _scrollController, 
                              index: index,
                              child: isNewMessage 
                                ? TweenAnimationBuilder<double>(
                                    tween: Tween<double>(begin: 0.0, end: 1.0), 
                                    duration: const Duration(milliseconds: 300), 
                                    curve: Curves.easeOutBack, 
                                    builder: (context, double val, child) => Transform.scale(
                                      scale: val, 
                                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft, 
                                      child: child
                                    ),
                                    child: messageContent,
                                  )
                                : messageContent,
                            );
                           
                          },
                        ),
                        
                ),
                if (_showScrollToBottomBtn) 
                  Positioned(
                    right: 16, 
                    bottom: 16, 
                    child: FloatingActionButton(
                      mini: true, 
                      backgroundColor: Colors.blue.withOpacity(0.85), 
                      onPressed: _scrollToBottom, 
                      child: const Icon(Icons.keyboard_double_arrow_down, color: Colors.white)
                    )
                  ),
              ],
            ),
          ),
          
// --- ПЛАШКА ЗАГРУЗКИ ВИДЕО 🎬 ---
          if (_isVideoUploading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[900] : Colors.blue.withOpacity(0.1),
                border: const Border(left: BorderSide(color: Colors.blue, width: 4))
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20, height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2.5)
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Загрузка видео в облако... ⏳', 
                      style: TextStyle(
                        color: isDarkMode ? Colors.white70 : Colors.black87, 
                        fontWeight: FontWeight.bold,
                        fontSize: 13
                      )
                    )
                  ),
                ],
              ),
            ),

          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[900] : Colors.grey[200], 
                border: const Border(left: BorderSide(color: Colors.blue, width: 4))
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply, color: Colors.blue), 
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, 
                      children: [
                        Text(
                          'В ответ ${_replyingTo!.senderId == widget.currentUser.id ? "Вам" : widget.otherUser.username}', 
                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)
                        ), 
                        Text(
                          _replyingTo!.messageText, 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis, 
                          style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black54, fontSize: 13)
                        )
                      ]
                    )
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20), 
                    onPressed: () => setState(() => _replyingTo = null)
                  ),
                ],
              ),
            ),
            // --- ПЛАШКА РЕДАКТИРОВАНИЯ ---
          if (_editingMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[900] : Colors.grey[200], 
                border: const Border(left: BorderSide(color: Colors.blue, width: 4))
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: Colors.blue), 
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, 
                      children: [
                        const Text('Редактирование', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)), 
                        Text(
                          _editingMessage!.messageText, 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis, 
                          style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black54, fontSize: 13)
                        )
                      ]
                    )
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20), 
                    onPressed: () {
                      setState(() {
                        _editingMessage = null; // Отменяем редактирование
                        _messageController.clear(); // Очищаем поле
                      });
                    }
                  ),
                ],
              ),
            ),
// --- БЛОК ВВОДА ИЛИ БЛОКИРОВКИ ---
          _isBlocked 
          ? Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Text(
                // Если заблокировал ТЫ, пишем одно. Если ОН - пишем другое!
                _iBlockedHim 
                    ? 'Вы заблокировали этого пользователя 🛑' 
                    : 'Пользователь ограничил доступ к чату 🛑',
                style: const TextStyle(
                  color: Colors.redAccent, 
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            )
          : Padding(
            padding: const EdgeInsets.all(8.0),
            child: _isRecording 
            ? Row( 
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red), 
                    onPressed: _cancelRecording
                  ),
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.mic, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(_recordDuration), 
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                          ),
                        ],
                      ),
                    )
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.blue), 
                    onPressed: _stopAndSendRecording
                  ),
                ],
              )
            : Row( 
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.attach_file, color: Colors.blue),
                        onPressed: _showAttachmentMenu,
                      ),
                      IconButton(
                        icon: Icon(
                          _showCustomEmojiPanel ? Icons.keyboard : Icons.sentiment_very_satisfied,
                          color: Colors.amber, 
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          // Переключаем панель
                          setState(() => _showCustomEmojiPanel = !_showCustomEmojiPanel);
                          // Убираем фокус с поля ввода (прячем клавиатуру)
                          if (_showCustomEmojiPanel) {
                            _messageInputFocusNode.unfocus();
                          } else {
                            // Если закрыли панель - возвращаем фокус (открываем клаву)
                            _messageInputFocusNode.requestFocus();
                          }
                        },
                      ),
                    ],
                  ),
                  Expanded(
                    child: TextField(
                controller: _messageController,
                focusNode: _messageInputFocusNode, // <--- ДОБАВЬ ЭТУ СТРОЧКУ
                decoration: InputDecoration(
                  hintText: isSavedMessages ? 'Написать заметку...' : 'Сообщение...',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                
                // --- ДОБАВЛЯЕМ СВОЕ МЕНЮ ВЫДЕЛЕНИЯ ТЕКСТА ---
                contextMenuBuilder: (context, editableTextState) {
                  final buttonItems = editableTextState.contextMenuButtonItems;

                  // Функция обертывания выделенного текста в теги
                  void applyTag(String tag) {
                    final textValue = editableTextState.textEditingValue;
                    final selection = textValue.selection;
                    if (!selection.isValid || selection.isCollapsed) return;
                    
                    final selectedText = selection.textInside(textValue.text);
                    final newText = textValue.text.replaceRange(selection.start, selection.end, '$tag$selectedText$tag');
                    
                    editableTextState.updateEditingValue(TextEditingValue(
                      text: newText,
                      selection: TextSelection.collapsed(offset: selection.end + (tag.length * 2)),
                    ));
                    editableTextState.hideToolbar(); // Закрываем меню после нажатия
                  }

                  // Вставляем наши новые кнопки в самое начало меню
                  buttonItems.insert(0, ContextMenuButtonItem(
                    label: 'Спойлер',
                    onPressed: () => applyTag('||'),
                  ));
                  buttonItems.insert(1, ContextMenuButtonItem(
                    label: 'Жирный',
                    onPressed: () => applyTag('**'),
                  ));
                  buttonItems.insert(2, ContextMenuButtonItem(
                    label: 'Подчеркнутый',
                    onPressed: () => applyTag('__'),
                  ));

                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: editableTextState.contextMenuAnchors,
                    buttonItems: buttonItems,
                  );
                },
                // --- КОНЕЦ МЕНЮ ---
                
              ), // TextField
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      // Если мы редактируем - показываем галочку, иначе обычная логика (микрофон/самолет)
                      _editingMessage != null ? Icons.check : (_isTextFieldEmpty ? Icons.mic : Icons.send), 
                      color: Colors.blue
                    ), 
                    onPressed: () {
                      if (_editingMessage != null) {
                        _sendMessage(); // Если редактируем - сохраняем
                      } else {
                        // Обычная логика: пустая строка - ГС, есть текст - отправка
                        _isTextFieldEmpty ? _startRecording() : _sendMessage(); 
                      }
                    }
                  ),
                ]
              ),
          ),
        // закрывает Column
            AnimatedSize(
          duration: const Duration(milliseconds: 200), // Плавное появление
          child: _showCustomEmojiPanel
              ? CustomEmojiSelector(
                  isDarkMode: isDarkMode,
                  onEmojiSelected: (assetPath) {
                    HapticFeedback.mediumImpact();
                    // 1. Закрываем панель стикеров
                    setState(() => _showCustomEmojiPanel = false);

                    // 2. Вписываем наш секретный код стикера в текстовое поле
                    _messageController.text = '[STICKER]$assetPath';
                    
                    // 3. Вызываем твою стандартную функцию отправки сообщения!
                    _sendMessage(); 
                  
                  },
                )
              : const SizedBox(),
            ), // AnimatedSize
          ], // <--- ВОТ СЮДА МЫ ПЕРЕНЕСЛИ ЭТУ СКОБКУ (закрываем список виджетов)
        ), // <--- И ЭТУ (закрываем колонку)
      ), // ЗАКРЫВАЕТ BackdropFilter 
    ),
         ), // ЗАКРЫВАЕТ самый первый Container (фон)
       ConfettiWidget(
      confettiController: _confettiController,
      blastDirection: 3.14 / 2, // Направление: ВНИЗ (Пи / 2)
      maxBlastForce: 6,         // Максимальная сила выстрела
      minBlastForce: 2,         // Минимальная сила
      emissionFrequency: 0.05,  // Как часто вылетают частицы
      numberOfParticles: 25,    // Количество за раз
      gravity: 0.2,             // Скорость падения (гравитация)
      colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
      ), // ЗАКРЫВАЕТ ConfettiWidget

    ], // ЗАКРЫВАЕТ список слоев (children)
  ), // ЗАКРЫВАЕТ Stack
); // ЗАКРЫВАЕТ Scaffold

} // ЗАКРЫВАЕТ метод build

} // ЗАКРЫВАЕТ класс _ChatScreenState

class VoiceMessagePlayer extends StatefulWidget {
  final String base64Audio;
  final String messageId;
  final bool isMe;
  final bool isDarkMode;

  const VoiceMessagePlayer({
    super.key, 
    required this.base64Audio, 
    required this.messageId, 
    required this.isMe, 
    required this.isDarkMode
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isReady = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override 
  void initState() {
    super.initState(); 
    _initAudio();
    _audioPlayer.onPlayerStateChanged.listen((state) { 
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing); 
    });
    _audioPlayer.onDurationChanged.listen((d) { 
      if (mounted) setState(() => _duration = d); 
    });
    _audioPlayer.onPositionChanged.listen((p) { 
      if (mounted) setState(() => _position = p); 
    });
    _audioPlayer.onPlayerComplete.listen((_) { 
      if (mounted) setState(() { 
        _isPlaying = false; 
        _position = Duration.zero; 
      }); 
    });
  }

  Future<void> _initAudio() async { 
    try { 
      final dir = await getTemporaryDirectory(); 
      final file = File('${dir.path}/${widget.messageId}.m4a'); 
      if (!await file.exists()) { 
        await file.writeAsBytes(base64Decode(widget.base64Audio.replaceAll(RegExp(r'\s+'), ''))); 
      } 
      await _audioPlayer.setSourceDeviceFile(file.path); 
      setState(() => _isReady = true); 
    } catch (e) {
      print("Ошибка: $e");
    } 
  }

  @override 
  void dispose() { 
    _audioPlayer.dispose(); 
    super.dispose(); 
  }

  @override 
  Widget build(BuildContext context) {
    return Container(
      width: 220, 
      padding: const EdgeInsets.symmetric(vertical: 4), 
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, 
              color: Colors.blue, 
              size: 36
            ), 
            onPressed: _isReady ? () { _isPlaying ? _audioPlayer.pause() : _audioPlayer.resume(); } : null,
          ), 
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), 
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14), 
                trackHeight: 3
              ), 
              child: Slider(
                min: 0, 
                max: _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1.0, 
                value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1.0), 
                activeColor: Colors.blue, 
                inactiveColor: Colors.blue.withOpacity(0.3), 
                onChanged: _isReady ? (v) => _audioPlayer.seek(Duration(seconds: v.toInt())) : null,
              )
            )
          ), 
          Text(
            '${(_position.inSeconds > 0 ? _position : _duration).inMinutes.toString().padLeft(2,'0')}:${(_position.inSeconds > 0 ? _position : _duration).inSeconds.remainder(60).toString().padLeft(2,'0')}', 
            style: TextStyle(
              fontSize: 12, 
              color: (widget.isDarkMode ? Colors.white : Colors.black87).withOpacity(0.7)
            )
          ),
        ]
      )
    );
  }
}

// --- ВИДЖЕТ ВИДЕОПЛЕЕРА В ЧАТЕ ---
class VideoMessagePlayer extends StatefulWidget {
  final String videoUrl;
  final String messageId; // <--- ДОБАВИЛИ ДЛЯ АНИМАЦИИ
  const VideoMessagePlayer({super.key, required this.videoUrl, required this.messageId});

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) setState(() => _isInitialized = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const SizedBox(
        width: 220, height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return GestureDetector(
      onTap: () {
        _controller.pause(); // Ставим на паузу мини-плеер перед открытием
        
        // Открываем на весь экран с красивой анимацией затемнения!
        Navigator.push(context, PageRouteBuilder(
          opaque: false,
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, a1, a2) => FullScreenVideoScreen(
            videoUrl: widget.videoUrl, 
            heroTag: 'video_${widget.messageId}' // Уникальный тег
          ),
          transitionsBuilder: (context, a1, a2, child) => FadeTransition(opacity: a1, child: child),
        ));
      },
      child: Container(
        width: 250,
        margin: const EdgeInsets.only(bottom: 4),
        constraints: const BoxConstraints(maxHeight: 350),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // АНИМАЦИЯ ПЕРЕХОДА HERO
            Hero(
              tag: 'video_${widget.messageId}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
            // Кнопка Play / Pause поверх видео (работает только для мини-плеера)
            IconButton(
              iconSize: 50,
              color: Colors.white.withOpacity(0.8),
              icon: Icon(
                _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              ),
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
// -----------------------------

class CustomSwipeToReply extends StatefulWidget { 
  final Widget child; 
  final VoidCallback onReply; 

  const CustomSwipeToReply({
    super.key, 
    required this.child, 
    required this.onReply
  }); 

  @override 
  State<CustomSwipeToReply> createState() => _CustomSwipeToReplyState(); 
}

class _CustomSwipeToReplyState extends State<CustomSwipeToReply> { 
  double _dragOffset = 0.0; 

  @override 
  Widget build(BuildContext context) { 
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild, 
      onHorizontalDragUpdate: (details) { 
        setState(() { 
          _dragOffset += details.primaryDelta ?? 0; 
          if (_dragOffset > 0) _dragOffset = 0; 
          if (_dragOffset < -70) _dragOffset = -70; 
        }); 
      }, 
      onHorizontalDragEnd: (details) { 
        if (_dragOffset <= -50) widget.onReply(); 
        setState(() { _dragOffset = 0.0; }); 
      }, 
      child: Stack(
        alignment: Alignment.centerRight, 
        clipBehavior: Clip.none, 
        children: [
          Positioned(
            right: -40, 
            child: Opacity(
              opacity: (_dragOffset.abs() / 70).clamp(0.0, 1.0), 
              child: const Icon(Icons.reply, color: Colors.blue, size: 24)
            )
          ), 
          AnimatedContainer(
            duration: _dragOffset == 0 ? const Duration(milliseconds: 200) : Duration.zero, 
            transform: Matrix4.translationValues(_dragOffset, 0, 0), 
            child: widget.child
          )
        ]
      )
    ); 
  } 
}

class TypingIndicator extends StatefulWidget { 
  const TypingIndicator({super.key}); 

  @override 
  State<TypingIndicator> createState() => _TypingIndicatorState(); 
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin { 
  late AnimationController _controller; 

  @override 
  void initState() { 
    super.initState(); 
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(); 
  } 

  @override 
  void dispose() { 
    _controller.dispose(); 
    super.dispose(); 
  } 

  @override 
  Widget build(BuildContext context) { 
    return Row(
      mainAxisSize: MainAxisSize.min, 
      children: List.generate(4, (index) { 
        return AnimatedBuilder(
          animation: _controller, 
          builder: (context, child) { 
            final isVisible = _controller.value >= index * 0.25; 
            return Opacity(
              opacity: isVisible ? 1.0 : 0.0, 
              child: Transform.translate(
                offset: Offset(0, index % 2 == 0 ? -2.0 : 2.0), 
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0), 
                  child: Transform.rotate(
                    angle: math.pi / 4, 
                    child: const Icon(Icons.pets, size: 14, color: Colors.blue)
                  )
                )
              )
            );
          }
        );
      })
    ); 
  } 
}

// ==========================================
// 📸 ПОЛНОЭКРАННАЯ ГАЛЕРЕЯ (ИДЕАЛЬНЫЕ ЖЕСТЫ)
// ==========================================
class FullScreenImageScreen extends StatefulWidget {
  final List<Map<String, dynamic>> mediaList;
  final int initialIndex;

  const FullScreenImageScreen({super.key, required this.mediaList, required this.initialIndex});

  @override
  State<FullScreenImageScreen> createState() => _FullScreenImageScreenState();
}

class _FullScreenImageScreenState extends State<FullScreenImageScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Фон (черный, теперь будет плавно исчезать при закрытии без багов)
          Container(color: Colors.black),
          
          PageView.builder(
            controller: _pageController,
            itemCount: widget.mediaList.length,
            // --- ФИКС 1: Ставим null, чтобы вернулась родная Android-анимация растяжения ---
            physics: _isZoomed ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (index) {
              setState(() { _currentIndex = index; });
            },
            itemBuilder: (context, index) {
              final media = widget.mediaList[index];
              
              final Widget myImageWidget = media.containsKey('url') 
                  ? Image.network(media['url']!, fit: BoxFit.contain, gaplessPlayback: true)
                  : Image.memory(base64Decode(media['base64']!.replaceAll(RegExp(r'\s+'), '')), fit: BoxFit.contain, gaplessPlayback: true);

              final String currentHeroTag = (index == _currentIndex) 
                  ? media['tag']! 
                  : 'hidden_hero_${media['tag']}';

              return ZoomableImagePage(
                imageWidget: myImageWidget,
                heroTag: currentHeroTag,
                onSwipeDown: () => Navigator.pop(context),
                onZoomChanged: (isZoomed) {
                  if (_isZoomed != isZoomed && mounted) {
                    setState(() => _isZoomed = isZoomed);
                  }
                },
              );
            }
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context)
                )
              )
            )
          ),
        ]
      ),
    );
  }
}

// ==========================================
// 🔍 ПЛЕЕР С КАРТИНКОЙ (ЗУМ)
// ==========================================
class ZoomableImagePage extends StatefulWidget {
  final Widget imageWidget;
  final String heroTag;
  final VoidCallback onSwipeDown;
  final ValueChanged<bool> onZoomChanged; 

  const ZoomableImagePage({
    super.key,
    required this.imageWidget,
    required this.heroTag,
    required this.onSwipeDown,
    required this.onZoomChanged,
  });

  @override
  State<ZoomableImagePage> createState() => _ZoomableImagePageState();
}

class _ZoomableImagePageState extends State<ZoomableImagePage> with SingleTickerProviderStateMixin {
  final TransformationController _transformationController = TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  bool _isZoomed = false;

  // Следим за пальцами для идеального свайпа
  int _pointers = 0;
  bool _isSwipingDown = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250)
    )..addListener(() {
        if (_animation != null) _transformationController.value = _animation!.value;
      });

    _transformationController.addListener(() {
      final isZoomed = _transformationController.value.getMaxScaleOnAxis() > 1.01;
      if (_isZoomed != isZoomed) {
        setState(() => _isZoomed = isZoomed);
        widget.onZoomChanged(isZoomed); 
      }
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final Matrix4 endMatrix;
    if (!_isZoomed) {
      final scale = 3.0;
      final size = MediaQuery.of(context).size;
      final dx = -size.width * (scale - 1) / 2;
      final dy = -size.height * (scale - 1) / 2;
      
      endMatrix = Matrix4.identity()
        ..translate(dx, dy)
        ..scale(scale);
    } else {
      endMatrix = Matrix4.identity();
    }

    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: endMatrix
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
    _animationController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    // --- ФИКС 2: Используем системный Listener вместо Dismissible ---
    return Listener(
      onPointerDown: (_) => _pointers++,
      onPointerUp: (_) {
        _pointers--;
        if (_pointers < 0) _pointers = 0;
        _isSwipingDown = false;
      },
      onPointerCancel: (_) {
        _pointers = 0;
        _isSwipingDown = false;
      },
      onPointerMove: (event) {
        // УСЛОВИЕ ИДЕАЛЬНОГО СВАЙПА:
        // 1. На экране ровно один палец.
        // 2. Фото НЕ приближено.
        // 3. Мы тянем ВНИЗ (y > 6).
        // 4. Движение вниз сильнее, чем движение влево/вправо (чтобы не путать с перелистыванием).
        if (_pointers == 1 && !_isZoomed && event.delta.dy > 6 && event.delta.dy > event.delta.dx.abs()) {
          if (!_isSwipingDown) {
            _isSwipingDown = true;
            widget.onSwipeDown(); // Мягко закрываем галерею!
          }
        }
      },
      child: GestureDetector(
        onDoubleTap: _handleDoubleTap,
        child: InteractiveViewer(
          transformationController: _transformationController,
          panEnabled: true,
          scaleEnabled: true,
          minScale: 1.0,
          maxScale: 5.0,
          clipBehavior: Clip.none,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Hero(
              tag: widget.heroTag,
              child: widget.imageWidget,
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 🍿 ПОЛНОЭКРАННЫЙ ВИДЕОПЛЕЕР (Кинотеатр)
// ==========================================
class FullScreenVideoScreen extends StatefulWidget {
  final String videoUrl;
  final String heroTag;

  const FullScreenVideoScreen({super.key, required this.videoUrl, required this.heroTag});

  @override
  State<FullScreenVideoScreen> createState() => _FullScreenVideoScreenState();
}

class _FullScreenVideoScreenState extends State<FullScreenVideoScreen> {
  late VideoPlayerController _controller;
  bool _showControls = true; // Показываем ли интерфейс

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.play(); // Сразу начинаем проигрывать при открытии
        }
      });

    // Обновляем экран, чтобы ползунок двигался
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Красивое форматирование времени (01:23)
  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Вокруг видео должно быть темно
      body: GestureDetector(
        // Тап по экрану скрывает/показывает кнопки
        onTap: () => setState(() => _showControls = !_showControls),
        // Свайп вниз закрывает видео
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta! > 7) {
            Navigator.pop(context);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // --- 1. САМО ВИДЕО (по центру) ---
            Center(
              child: Hero(
                tag: widget.heroTag,
                child: _controller.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      )
                    : const CircularProgressIndicator(color: Colors.blue), // Крутилка загрузки
              ),
            ),

            // --- 2. КНОПКА "НАЗАД" (слева сверху) ---
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Align(
                alignment: Alignment.topLeft,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ),

            // --- 3. БОЛЬШАЯ КНОПКА PLAY/PAUSE (по центру) ---
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Center(
                child: IconButton(
                  iconSize: 80,
                  color: Colors.white.withOpacity(0.9),
                  icon: Icon(_controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                  onPressed: () {
                    setState(() {
                      _controller.value.isPlaying ? _controller.pause() : _controller.play();
                    });
                  },
                ),
              ),
            ),

            // --- 4. ПАНЕЛЬ УПРАВЛЕНИЯ И ПОЛЗУНОК (жестко прижаты к низу) ---
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  padding: const EdgeInsets.only(bottom: 30, left: 20, right: 20, top: 40),
                  decoration: BoxDecoration(
                    // Плавное затемнение снизу вверх, чтобы текст всегда читался
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        // Текущее время
                        Text(_formatDuration(_controller.value.position), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 15),
                        
                        // Ползунок
                        Expanded(
                          child: VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            colors: const VideoProgressColors(
                              playedColor: Colors.blue,
                              bufferedColor: Colors.white54,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 15),
                        // Общее время
                        Text(_formatDuration(_controller.value.duration), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- АНИМАЦИЯ МЕРЦАЮЩЕГО СПОЙЛЕРА ---
class AnimatedSpoilerText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const AnimatedSpoilerText({super.key, required this.text, required this.style});

  @override
  State<AnimatedSpoilerText> createState() => _AnimatedSpoilerTextState();
}

class _AnimatedSpoilerTextState extends State<AnimatedSpoilerText> with SingleTickerProviderStateMixin {
  bool _isRevealed = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Запускаем бесконечное мерцание
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isRevealed) {
      return Text(widget.text, style: widget.style);
    }
    return GestureDetector(
      onTap: () => setState(() => _isRevealed = true), // Открываем по клику
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                colors: [Colors.grey[500]!, Colors.grey[300]!, Colors.grey[500]!],
                stops: [0.0, _controller.value, 1.0],
              ).createShader(bounds);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              // Прячем текст прозрачностью, чтобы блок принял нужный размер
              child: Opacity(opacity: 0, child: Text(widget.text, style: widget.style)),
            ),
          );
        },
      ),
    );
  }
}

// --- УМНЫЙ ТЕКСТ (Читает теги и стилизует) ---
class SmartMessageText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  const SmartMessageText({super.key, required this.text, required this.baseStyle});

  @override
  Widget build(BuildContext context) {
    final List<InlineSpan> spans = [];
    // Ищем ||спойлер|| или **жирный** или __подчеркнутый__
    final RegExp exp = RegExp(r'(\|\|.*?\|\||\*\*.*?\*\*|__.*?__)');
    int lastIndex = 0;

    for (final match in exp.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start), style: baseStyle));
      }
      String matchText = match[0]!;
      if (matchText.startsWith('||')) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: AnimatedSpoilerText(text: matchText.replaceAll('||', ''), style: baseStyle),
        ));
      } else if (matchText.startsWith('**')) {
        spans.add(TextSpan(text: matchText.replaceAll('**', ''), style: baseStyle.copyWith(fontWeight: FontWeight.bold)));
      } else if (matchText.startsWith('__')) {
        spans.add(TextSpan(text: matchText.replaceAll('__', ''), style: baseStyle.copyWith(decoration: TextDecoration.underline)));
      }
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex), style: baseStyle));
    }

    return RichText(text: TextSpan(children: spans));
  }
}
// --- НОВЫЙ ВИДЖЕТ ПАНЕЛИ custom ЭМОДЗИ (СТИКЕРОВ) ---
class CustomEmojiSelector extends StatelessWidget {
  final Function(String) onEmojiSelected; // Функция, которая сработает при выборе
  final bool isDarkMode;

  const CustomEmojiSelector({
    super.key,
    required this.onEmojiSelected,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    // Высота панели (примерно как клавиатура)
    final double panelHeight = MediaQuery.of(context).size.height * 0.35;

    // Симулируем списки картинок (по 15 в каждом паке). 
    // Когда найдешь реальные, просто замени пути!
    final packAlpha = List.generate(18, (index) => 'assets/emojis/pack_alpha/${index + 1}.png');
    final packBeta = List.generate(20, (index) => 'assets/emojis/pack_beta/${index + 1}.png');

    return DefaultTabController(
      length: 2, // Две вкладки (два пака)
      child: Container(
        height: panelHeight,
        color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
        child: Column(
          children: [
            // Переключатель вкладок
            TabBar(
              labelColor: isDarkMode ? Colors.white : Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              tabs: const [
                Tab(icon: Icon(Icons.star), text: 'Пак Котя'),
                Tab(icon: Icon(Icons.bolt), text: 'Пак Дракоша'),
              ],
            ),
            // Сами паки
            Expanded(
              child: TabBarView(
                children: [
                  _buildEmojiGrid(packAlpha, context), // Сетка для пака 1
                  _buildEmojiGrid(packBeta, context),  // Сетка для пака 2
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Строим сетку картинок
  Widget _buildEmojiGrid(List<String> emojiPaths, BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5, // 5 штук в ряд
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: emojiPaths.length,
      itemBuilder: (context, index) {
        final String path = emojiPaths[index];
        return GestureDetector(
          onTap: () => onEmojiSelected(path), // Передаем путь при клике
          child: MouseRegion( // Добавляем эффект наведения (если на ПК)
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              // --- САМА КАРТИНКА ЭМОДЗИ ---
              // Пока у тебя нет картинок, используем заглушку, чтобы не было ошибок
              child: Image.asset(
                path, 
                fit: BoxFit.contain,
                // Если картинки нет по пути — покажет иконку-заглушку
                errorBuilder: (context, error, stackTrace) => Icon(Icons.image, color: Colors.grey[400]),
              ),
            ),
          ),
        );
      },
    );
  }
}
// ----------------------------------------------------