import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_log/main.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/state/app_repository.dart';

import 'fixtures.dart';

/// Interaktion auf dem Heute-Screen: Abhaken, Sheet, ungeplante Einheit.
void main() {
  final today = DateTime(2026, 11, 23, 9);

  Future<AppRepository> buildRepository() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = AppRepository(
      clock: () => today,
      saveDebounce: const Duration(milliseconds: 1),
    );
    await repository.load();
    repository.importPlans(
      repository.parseImport(
        documentJson(
          plans: <Map<String, dynamic>>[
            planJson(sessions: <Map<String, dynamic>>[sessionJson()]),
          ],
        ),
      ),
    );
    await repository.flush();
    return repository;
  }

  Future<AppRepository> pumpApp(WidgetTester tester) async {
    final repository = await buildRepository();
    await tester.pumpWidget(TriLogApp(repository: repository));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('Schnell-Abhaken setzt Badge „Erledigt“ und bietet Rückgängig', (
    tester,
  ) async {
    final repository = await pumpApp(tester);

    expect(find.text('0 von 1 erledigt'), findsOneWidget);
    expect(find.text('Erledigt'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('check-s1')));
    await tester.pumpAndSettle();

    expect(find.text('Erledigt'), findsOneWidget);
    expect(find.text('1 von 1 erledigt'), findsOneWidget);
    expect(find.text('Abgehakt: Technik · 45 min'), findsOneWidget);
    expect(find.text('Rückgängig'), findsOneWidget);
    expect(repository.state.activities, hasLength(1));
    expect(repository.activityForSession('s1')?.status.name, 'completed');
    expect(repository.activityForSession('s1')?.elapsedDurationSeconds, 2700);

    // Der Button wird zum Bearbeiten-Button (kein Duplikat).
    expect(find.byKey(const ValueKey<String>('check-s1')), findsNothing);
    expect(find.byKey(const ValueKey<String>('edit-s1')), findsOneWidget);

    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();

    expect(repository.state.activities, isEmpty);
    expect(find.text('Erledigt'), findsNothing);
    expect(find.text('0 von 1 erledigt'), findsOneWidget);
  });

  testWidgets('Sheet zeigt die vorbelegte Ist-Dauer der Aktivität', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey<String>('check-s1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Technik'));
    await tester.pumpAndSettle();

    expect(find.text('Einheit erfassen'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('durationField')),
    );
    expect(field.controller?.text, '45');
    // Vorhandene Aktivität → Status „Erledigt“ ist vorausgewählt.
    final segmented = tester.widget<SegmentedButton<ActivityStatus>>(
      find.byKey(const Key('statusSegments')),
    );
    expect(segmented.selected.single, ActivityStatus.completed);
    // Löschen ist nur bei vorhandener Aktivität sichtbar.
    expect(find.byKey(const Key('deleteButton')), findsOneWidget);
  });

  testWidgets(
    'Sheet speichert „Teilweise“ und die Karte zeigt die Abweichung',
    (tester) async {
      final repository = await pumpApp(tester);

      await tester.tap(find.text('Technik'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Teilweise'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('durationField')), '30');
      await tester.tap(find.byKey(const Key('saveButton')));
      await tester.pumpAndSettle();

      // Rückmeldung erscheint IM Sheet (nicht als SnackBar dahinter).
      expect(find.byKey(const Key('sheetFeedback')), findsOneWidget);
      expect(find.textContaining('Gespeichert · Teilweise'), findsOneWidget);
      // Das Sheet bleibt offen.
      expect(find.text('Einheit erfassen'), findsOneWidget);

      await tester.tap(find.byKey(const Key('doneButton')));
      await tester.pumpAndSettle();

      expect(find.text('Teilweise'), findsOneWidget);
      expect(
        find.textContaining('Ist: 30 min (15 min kürzer)'),
        findsOneWidget,
      );
      expect(find.text('0 von 1 erledigt · 1 teilweise'), findsOneWidget);
      expect(repository.activityForSession('s1')?.elapsedDurationSeconds, 1800);
    },
  );

  testWidgets('FAB erfasst eine ungeplante Einheit unter „Zusätzlich“', (
    tester,
  ) async {
    final repository = await pumpApp(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Einheit erfassen'), findsOneWidget);
    expect(find.textContaining('Ungeplante Einheit'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sportDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rad').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('durationField')), '40');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('doneButton')));
    await tester.pumpAndSettle();

    expect(find.text('Zusätzlich'), findsOneWidget);
    expect(find.text('Rad'), findsOneWidget);
    expect(find.textContaining('40 min'), findsWidgets);
    expect(repository.state.activities, hasLength(1));
    final activity = repository.state.activities.single;
    expect(activity.planId, isNull);
    expect(activity.plannedSessionId, isNull);
    expect(activity.sport, 'bike');
    expect(activity.elapsedDurationSeconds, 2400);
    expect(activity.status.name, 'completed');
  });
}
