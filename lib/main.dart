import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'state/app_repository.dart';

void main() {
  runApp(const TriLogApp());
}

const Color _seedColor = Color(0xFF0F172A);

class TriLogApp extends StatelessWidget {
  const TriLogApp({super.key, this.repository});

  /// Optional injizierbar (Tests).
  final AppRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppRepository>(
      create: (_) {
        final repo = repository ?? AppRepository();
        if (!repo.isLoaded) unawaited(repo.load());
        return repo;
      },
      child: MaterialApp(
        title: 'Tri-Log',
        debugShowCheckedModeBanner: false,
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
        home: const HomeShell(),
      ),
    );
  }
}
