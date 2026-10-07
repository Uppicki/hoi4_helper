import 'package:flutter/material.dart';

import 'ui/saves_screen.dart';

void main() => runApp(const HoiAssistantApp());

class HoiAssistantApp extends StatelessWidget {
  const HoiAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD7B979);
    return MaterialApp(
      title: 'HOI IV · Помощник',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF111715),
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          primary: accent,
          surface: const Color(0xFF1B2420),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Color(0xFF111715),
        ),
      ),
      home: const SavesScreen(),
    );
  }
}
