import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'state/app_repository.dart';
import 'state/settings_controller.dart';

void main() {
  runApp(const TriLogApp());
}

const Color _seedColor = Color(0xFF0F172A);

class TriLogApp extends StatelessWidget {
  const TriLogApp({super.key, this.repository, this.settingsController});

  /// Optional injizierbar (Tests).
  final AppRepository? repository;

  /// Optional injizierbar (Tests); sonst wird ein eigener Controller geladen.
  final SettingsController? settingsController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppRepository>(
          create: (_) {
            final repo = repository ?? AppRepository();
            if (!repo.isLoaded) unawaited(repo.load());
            return repo;
          },
        ),
        ChangeNotifierProvider<SettingsController>(
          create: (_) {
            final controller = settingsController ?? SettingsController();
            if (!controller.isLoaded) unawaited(controller.load());
            return controller;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Tri-Log',
        debugShowCheckedModeBanner: false,
        // Deutsche Material-Texte (Zeitwahl, Dialoge, Tooltips) – ohne diese
        // Delegates zeigt der TimePicker AM/PM und kann unter `locale: de`
        // werfen.
        locale: const Locale('de'),
        supportedLocales: const <Locale>[Locale('de'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
