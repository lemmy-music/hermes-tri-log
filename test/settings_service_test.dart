import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_log/services/settings_service.dart';
import 'package:tri_log/state/settings_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Defaults: morgens 05:00 und abends 20:00, beide an', () {
    const settings = ReminderSettings.defaults;

    expect(settings.morningEnabled, isTrue);
    expect(settings.morningHour, 5);
    expect(settings.morningMinute, 0);
    expect(settings.eveningEnabled, isTrue);
    expect(settings.eveningHour, 20);
    expect(settings.eveningMinute, 0);
  });

  test('Roundtrip: speichern und wieder laden', () async {
    const service = SettingsService();
    const settings = ReminderSettings(
      morningEnabled: false,
      morningHour: 6,
      morningMinute: 45,
      eveningEnabled: true,
      eveningHour: 21,
      eveningMinute: 5,
    );

    await service.save(settings);
    final loaded = await service.load();

    expect(loaded, settings);
  });

  test('kaputtes JSON → Defaults (kein Crash)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.storageKey: '{nicht json',
    });

    expect(await const SettingsService().load(), ReminderSettings.defaults);
  });

  test('JSON, aber kein Objekt → Defaults', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.storageKey: '[1,2,3]',
    });

    expect(await const SettingsService().load(), ReminderSettings.defaults);
  });

  test('Stunden/Minuten werden geklemmt, falsche Typen → Defaults', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.storageKey: jsonEncode(<String, dynamic>{
        'morning_enabled': 'ja',
        'morning_hour': 99,
        'morning_minute': -5,
        'evening_enabled': true,
        'evening_hour': -1,
        'evening_minute': 61,
      }),
    });

    final loaded = await const SettingsService().load();

    expect(loaded.morningEnabled, isTrue, reason: 'String ist kein bool');
    expect(loaded.morningHour, 23);
    expect(loaded.morningMinute, 0);
    expect(loaded.eveningHour, 0);
    expect(loaded.eveningMinute, 59);
  });

  test('fehlende Felder behalten die Defaults', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.storageKey: jsonEncode(<String, dynamic>{
        'morning_hour': 7,
      }),
    });

    final loaded = await const SettingsService().load();

    expect(loaded.morningHour, 7);
    expect(loaded.morningMinute, 0);
    expect(loaded.eveningHour, 20);
    expect(loaded.eveningEnabled, isTrue);
  });

  test('eigener Key – das Zustandsdokument bleibt unberührt', () async {
    const stateKey = 'tri_log_state_v1';
    const stateDocument = '{"schema_version":"1.1","plans":[]}';
    SharedPreferences.setMockInitialValues(<String, Object>{
      stateKey: stateDocument,
    });

    const service = SettingsService();
    await service.save(const ReminderSettings(morningHour: 4));

    final prefs = await SharedPreferences.getInstance();
    expect(SettingsService.storageKey, 'tri_log_settings_v1');
    expect(prefs.getString(stateKey), stateDocument);
    final raw = prefs.getString(SettingsService.storageKey);
    expect(raw, isNotNull);
    expect(raw, contains('"morning_hour":4'));
    expect(raw, isNot(contains('schema_version')));
  });

  test(
    'SettingsController: lädt Defaults und persistiert jede Änderung',
    () async {
      final controller = SettingsController();
      await controller.load();

      expect(controller.isLoaded, isTrue);
      expect(controller.settings, ReminderSettings.defaults);

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setMorningEnabled(false);
      controller.setEveningTime(22, 30);
      await controller.pendingSave;

      expect(notifications, 2);
      expect(controller.settings.morningEnabled, isFalse);

      final loaded = await const SettingsService().load();
      expect(loaded.morningEnabled, isFalse);
      expect(loaded.eveningHour, 22);
      expect(loaded.eveningMinute, 30);

      controller.dispose();
    },
  );

  test(
    'SettingsController: identische Werte lösen kein Speichern aus',
    () async {
      final controller = SettingsController();
      await controller.load();

      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.setMorningTime(5, 0);

      expect(notifications, 0);
      controller.dispose();
    },
  );
}
