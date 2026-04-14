import 'package:flutter/material.dart';

class GlobalMessageSearch extends SearchDelegate {
  
  // Текст-подсказка в поле ввода
  @override
  String get searchFieldLabel => 'Поиск по всем чатам...';

  // Настройка цветов (чтобы подходило под твою тему)
  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: theme.appBarTheme.backgroundColor ?? Colors.blue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: Colors.white70),
      ),
      textTheme: theme.textTheme.copyWith(
        titleLarge: const TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  // Кнопка очистки текста (крестик справа)
  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '', // Очищаем строку
        )
    ];
  }

  // Кнопка "Назад" (стрелочка слева)
  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null), // Закрываем поиск
    );
  }

  // Результаты поиска (когда нажали Enter)
  @override
  Widget buildResults(BuildContext context) {
    if (query.isEmpty) return const SizedBox();

    // 🌟 В БУДУЩЕМ ЗДЕСЬ БУДЕТ ЗАПРОС К ТВОЕМУ C# API
    // Пока что мы просто показываем красивую заглушку

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.manage_search, size: 80, color: Colors.blue),
          const SizedBox(height: 16),
          Text('Ищем: "$query"', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Интерфейс готов! Осталось добавить метод поиска в C# API.', 
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // Подсказки при вводе (пока ты печатаешь)
  @override
  Widget buildSuggestions(BuildContext context) {
    return const Center(
      child: Text('Введите текст для поиска сообщений', style: TextStyle(color: Colors.grey)),
    );
  }
}