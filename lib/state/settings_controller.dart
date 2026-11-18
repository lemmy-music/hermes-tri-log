import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/settings_service.dart';

/// Hält die [ReminderSettings] im Speicher und persistiert jede Änderung
/// sofort (kein „Speichern“-Knopf nötig).
///
/// Bewusst getrennt vom [AppRepository]: Einstellungen sind keine Trainings-
/// daten und landen deshalb weder im Zustandsdokument noch im Export.
class SettingsController extends ChangeNotifier {
  SettingsController({SettingsService? service})
    : _service = service ?? const SettingsService();

  final SettingsService _service;

  ReminderSettings _settings = ReminderSettings.defaults;
  bool _loaded = false;
  bool _disposed = false;
  Future<void> _pendingSave = Future<void>.value();

  ReminderSettings get settings => _settings;
  bool get isLoaded => _loaded;

  /// Schließt ab, sobald alle bisher angestoßenen Speichervorgänge fertig sind
  /// (für Tests und ein sauberes Beenden).
  Future<void> get pendingSave => _pendingSave;

  Future<void> load() async {
    _settings = await _service.load();
    _loaded = true;
    _notify();
  }

  void setMorningEnabled(bool enabled) =>
      _update(_settings.copyWith(morningEnabled: enabled));

  void setEveningEnabled(bool enabled) =>
      _update(_settings.copyWith(eveningEnabled: enabled));

  void setMorningTime(int hour, int minute) =>
      _update(_settings.copyWith(morningHour: hour, morningMinute: minute));

  void setEveningTime(int hour, int minute) =>
      _update(_settings.copyWith(eveningHour: hour, eveningMinute: minute));

  /// Ersetzt die Einstellungen komplett (z. B. nach einem Restore).
  void replace(ReminderSettings settings) => _update(settings);

  void _update(ReminderSettings next) {
    if (next == _settings) return;
    _settings = next;
    _notify();
    _pendingSave = _pendingSave.then((_) => _save(next));
  }

  Future<void> _save(ReminderSettings settings) async {
    try {
      await _service.save(settings);
    } catch (_) {
      // Speichern darf die UI nie zum Absturz bringen; der Wert bleibt
      // zumindest für die laufende Sitzung gesetzt.
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
