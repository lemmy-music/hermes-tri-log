import 'package:flutter/material.dart';

void main() {
  runApp(const TriLogApp());
}

const Color _seedColor = Color(0xFF0F172A);

class TriLogApp extends StatelessWidget {
  const TriLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tri-Log',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const StartScreen(),
    );
  }
}

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tri-Log')),
      body: const Center(child: Text('Gerüst steht. Features folgen.')),
    );
  }
}
