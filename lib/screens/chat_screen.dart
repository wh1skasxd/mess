import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final UserModel currentUser; // <-- ИЗМЕНИЛИ User на UserModel
  final UserModel otherUser;   // <-- ИЗМЕНИЛИ User на UserModel

  const ChatScreen({
    super.key,
    required this.currentUser,
    required this.otherUser,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    // Автообновление каждые 8 секунд (для демонстрации)
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _loadMessages();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final api = ApiService();
    final messages = await api.getMessages(
      widget.currentUser.id,
      widget.otherUser.id,
    );

    if (mounted) {
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final api = ApiService();
    final success = await api.sendMessage(
      widget.currentUser.id,
      widget.otherUser.id,
      text,
    );

    if (success) {
      _messageController.clear();
      _loadMessages();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отправить сообщение')),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherUser.username),
      ),
      body: Column(
        children: [
          // Сообщения
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('Сообщений пока нет'))
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          // Тут может быть проблема, если msg.senderId остался типа int
                          final isMe = msg.senderId == widget.currentUser.id;

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                              decoration: BoxDecoration(
                                color: isMe ? Colors.blue[100] : Colors.grey[300],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.messageText,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    msg.time,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Поле ввода
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Напишите сообщение...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}