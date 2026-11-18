import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_log/main.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/services/settings_service.dart';
import 'package:tri_log/screens/settings_screen.dart';
import 'package:tri_log/state/app_repository.dart';
import 'package:tri_log/state/settings_controller.dart';
import 'package:tri_log/utils/formats.dart';

import 'fixtures.dart';

/// Fester „heute“-Tag für alle Widget-Tests.
DateTime get _today => DateTime(2026, 11, 23, 9);

Future<AppRepository> _buildRepository({
  bool withSessions = true,
  bool withDraft = true,
  bool journalFinalized = false,
}) async {
  final repository = AppRepository(
    clock: () => _today,
    saveDebounce: const Duration(milliseconds: 1),
  );
  await repository.load();

  if (withSessions) {
    repository.importPlans(
      repository.parseImport(
        documentJson(
          plans: <Map<String, dynamic>>[
            planJson(
              sessions: <Map<String, dynamic>>[
                sessionJson(
                  id: 's1',
                  date: '2026-11-23',
                  sport: 'bike',
                  type: 'Schwellen-Intervalle',
                  plannedDurationSeconds: 3600,
                ),
                sessionJson(
                  id: 's2',
                  date: '2026-11-23',
                  sport: 'strength',
                  type: 'Kraft',
                  plannedDurationSeconds: 2400,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  if (withDraft) {
    repository.saveJournalEntry(
      JournalEntry(
        id: 'j1',
        timestamp: isoWithOffset(DateTime(2026, 11, 23, 12)),
        finalizedAt: journalFinalized
            ? isoWithOffset(DateTime(2026, 11, 23, 21))
            : null,
        overallFeeling: 70,
        text: 'Entwurf der Tagesnotiz',
      ),
    );
  }

  await repository.flush();
  return repository;
}

Future<void> _openSettings(
  WidgetTester tester,
  AppRepository repository,
) async {
  await tester.pumpWidget(TriLogApp(repository: repository));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settingsButton')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Zahnrad in der AppBar öffnet die Einstellungen', (tester) async {
    final repository = await _buildRepository();
    await _openSettings(tester, repository);

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Morgen-Übersicht'), findsOneWidget);
    expect(find.text('Tagesnotiz-Erinnerung'), findsOneWidget);
    expect(
      find.text(
        'Erinnerungen werden nur in der Android-App ausgelöst. '
        'In der PWA/Browser erscheinen sie nicht.',
      ),
      findsOneWidget,
    );
    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('Version'),
      find.byKey(const Key('settingsList')),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    expect(find.text('Version'), findsOneWidget);
    expect(find.textContaining('Daten bleiben lokal'), findsOneWidget);
  });

  testWidgets(
    'Schalter aus: Hinweis bleibt, Einstellung wird sofort gespeichert',
    (tester) async {
      final repository = await _buildRepository();
      await _openSettings(tester, repository);

      await tester.tap(find.byKey(const Key('morningSwitch')));
      await tester.pumpAndSettle();

      final controller = Provider.of<SettingsController>(
        tester.element(find.byType(SettingsScreen)),
        listen: false,
      );
      await controller.pendingSave;

      expect(controller.settings.morningEnabled, isFalse);
      // Beschreibung und Hinweis-Box bleiben sichtbar.
      expect(
        find.text('Zeigt morgens die geplanten Einheiten.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('nur in der Android-App ausgelöst'),
        findsOneWidget,
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(SettingsService.storageKey);
      expect(raw, isNotNull);
      expect(raw, contains('"morning_enabled":false'));
      expect(
        prefs.getString('tri_log_state_v1') ?? '',
        isNot(contains('morning')),
      );
    },
  );

  testWidgets('Vorschau zeigt morgens Einheiten und abends den Entwurf', (
    tester,
  ) async {
    final repository = await _buildRepository();
    await _openSettings(tester, repository);

    await tester.ensureVisible(find.byKey(const Key('previewReminders')));
    await tester.tap(find.byKey(const Key('previewReminders')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reminderPreviewDialog')), findsOneWidget);
    expect(find.text('05:00 · Tri-Log'), findsOneWidget);
    expect(find.text('20:00 · Tri-Log'), findsOneWidget);
    expect(
      find.text('Rad · Schwellen-Intervalle (60 min) · Kraft (40 min)'),
      findsOneWidget,
    );
    expect(find.text('Tagesnotiz ist noch Entwurf'), findsOneWidget);
    expect(find.text('Schließen'), findsOneWidget);
  });

  testWidgets('Vorschau ohne geplante Einheiten meldet „keine Erinnerungen“', (
    tester,
  ) async {
    // Nichts geplant und die Tagesnotiz ist abgeschlossen → wirklich nichts
    // zu erinnern.
    final repository = await _buildRepository(
      withSessions: false,
      journalFinalized: true,
    );
    await _openSettings(tester, repository);

    await tester.ensureVisible(find.byKey(const Key('previewReminders')));
    await tester.tap(find.byKey(const Key('previewReminders')));
    await tester.pumpAndSettle();

    expect(find.textContaining('keine Erinnerungen'), findsOneWidget);
    expect(find.textContaining('05:00 · Tri-Log'), findsNothing);
  });

  testWidgets('Zeitwahl-Dialog öffnet und schließt ohne Exception', (
    tester,
  ) async {
    final repository = await _buildRepository();
    await _openSettings(tester, repository);

    await tester.tap(find.byKey(const Key('morningTime')));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(TimePickerDialog))).pop();
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
