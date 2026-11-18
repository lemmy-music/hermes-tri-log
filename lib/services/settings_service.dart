import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Erinnerungs-Einstellungen (Morgen-Übersicht + Tagesnotiz-Erinnerung).
///
/// Bewusst ein eigener Datentyp außerhalb von `AppState`: Einstellungen sind
/// Geräte-/Nutzerpräferenzen und gehören NICHT in das Export-/Coach-Dokument.
///
/// Ungültige Werte werden beim Lesen geklemmt (Stunden 0..23, Minuten 0..59)
/// bzw. durch die Defaults ersetzt – ein kaputter Speicherinhalt darf die App
/// nie blockieren.
class ReminderSettings {
  const ReminderSettings({
    this.morningEnabled = true,
    this.morningHour = 5,
    this.morningMinute = 0,
    this.eveningEnabled = true,
    this.eveningHour = 20,
    this.eveningMinute = 0,
  });

  /// Standard: morgens 05:00 und abends 20:00, beide aktiv.
  static const ReminderSettings defaults = ReminderSettings();

  final bool morningEnabled;
  final int morningHour;
  final int morningMinute;
  final bool eveningEnabled;
  final int eveningHour;
  final int eveningMinute;

  ReminderSettings copyWith({
    bool? morningEnabled,
    int? morningHour,
    int? morningMinute,
    bool? eveningEnabled,
    int? eveningHour,
    int? eveningMinute,
  }) => ReminderSettings(
    morningEnabled: morningEnabled ?? this.morningEnabled,
    morningHour: morningHour ?? this.morningHour,
    morningMinute: morningMinute ?? this.morningMinute,
    eveningEnabled: eveningEnabled ?? this.eveningEnabled,
    eveningHour: eveningHour ?? this.eveningHour,
    eveningMinute: eveningMinute ?? this.eveningMinute,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'morning_enabled': morningEnabled,
    'morning_hour': morningHour,
    'morning_minute': morningMinute,
    'evening_enabled': eveningEnabled,
    'evening_hour': eveningHour,
    'evening_minute': eveningMinute,
  };

  /// Tolerantes Lesen: fehlende/falsch typisierte Felder → Default,
  /// Zahlen werden auf gültige Uhrzeiten geklemmt.
  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    const fallback = ReminderSettings.defaults;
    return ReminderSettings(
      morningEnabled:
          _readBool(json['morning_enabled']) ?? fallback.morningEnabled,
      morningHour: _clampInt(
        _readInt(json['morning_hour']) ?? fallback.morningHour,
        min: 0,
        max: 23,
      ),
      morningMinute: _clampInt(
        _readInt(json['morning_minute']) ?? fallback.morningMinute,
        min: 0,
        max: 59,
      ),
      eveningEnabled:
          _readBool(json['evening_enabled']) ?? fallback.eveningEnabled,
      eveningHour: _clampInt(
        _readInt(json['evening_hour']) ?? fallback.eveningHour,
        min: 0,
        max: 23,
      ),
      eveningMinute: _clampInt(
        _readInt(json['evening_minute']) ?? fallback.eveningMinute,
        min: 0,
        max: 59,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.morningEnabled == morningEnabled &&
      other.morningHour == morningHour &&
      other.morningMinute == morningMinute &&
      other.eveningEnabled == eveningEnabled &&
      other.eveningHour == eveningHour &&
      other.eveningMinute == eveningMinute;

  @override
  int get hashCode => Object.hash(
    morningEnabled,
    morningHour,
    morningMinute,
    eveningEnabled,
    eveningHour,
    eveningMinute,
  );

  @override
  String toString() =>
      'ReminderSettings(morning: $morningEnabled '
      '${_two(morningHour)}:${_two(morningMinute)}, '
      'evening: $eveningEnabled ${_two(eveningHour)}:${_two(eveningMinute)})';

  static String _two(int value) => value.toString().padLeft(2, '0');
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  return null;
}

bool? _readBool(Object? value) => value is bool ? value : null;

int _clampInt(int value, {required int min, required int max}) =>
    value < min ? min : (value > max ? max : value);

/// Persistiert [ReminderSettings] als EIN JSON-Objekt unter einem eigenen
/// Schlüssel – getrennt vom Zustandsdokument (`tri_log_state_v1`), damit
/// Einstellungen nicht im Coach-Export landen.
class SettingsService {
  const SettingsService();

  /// Eigener Key, bewusst NICHT `tri_log_state_v1`.
  static const String storageKey = 'tri_log_settings_v1';

  /// Lädt die Einstellungen; fehlt/kaputt → [ReminderSettings.defaults].
  Future<ReminderSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.trim().isEmpty) return ReminderSettings.defaults;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return ReminderSettings.defaults;
      return ReminderSettings.fromJson(decoded);
    } catch (_) {
      return ReminderSettings.defaults;
    }
  }

  /// Speichert sofort (kein Debounce) – Schalter/Zeiten wirken unmittelbar.
  Future<void> save(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(settings.toJson()));
  }
}
