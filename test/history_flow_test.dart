import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_log/main.dart';
import 'package:tri_log/state/app_repository.dart';

import 'fixtures.dart';

/// Widget-Flows des Verlaufs: geplant vs. tatsächlich, Unbekannt-Kennzeichnung,
/// Erfassen aus der Vergangenheit, Zeitraum-Auswahl.
void main() {
  final today = DateTime(2026, 11, 23, 9, 15);

  Future<AppRepository> pumpApp(
    WidgetTester tester, {
    List<Map<String, dynamic>>? sessions,
    List<Map<String, dynamic>>? activities,
    List<Map<String, dynamic>>? journal,
  }) async {
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
            planJson(
              sessions: sessions ?? <Map<String, dynamic>>[sessionJson()],
            ),
          ],
          activities: activities,
          journal: journal,
        ),
      ),
    );
    await repository.flush();

    await tester.pumpWidget(TriLogApp(repository: repository));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> openHistoryTab(WidgetTester tester) async {
    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pumpAndSettle();
  }

  testWidgets('geplante Einheit ohne Aufzeichnung: „keine Aufzeichnung“, '
      'nicht „Ausgelassen“', (tester) async {
    await pumpApp(tester);
    await openHistoryTab(tester);

    // Navigationslabel + Überschrift des Tabs.
    expect(find.text('Verlauf'), findsNWidgets(2));
    expect(find.text('keine Aufzeichnung'), findsOneWidget);
    expect(find.text('Ausgelassen'), findsNothing);
    expect(
      find.text('0 erledigt · 0 teilweise · 0 ausgelassen · 1 offen'),
      findsOneWidget,
    );
    expect(find.text('Ist: – / Plan: 45 min'), findsOneWidget);
    expect(find.text('Mo, 23.11.2026'), findsOneWidget);
    // Kein FAB im Verlauf.
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('erledigte Einheit zeigt Ist-Dauer mit Abweichung', (
    tester,
  ) async {
    await pumpApp(
      tester,
      activities: <Map<String, dynamic>>[activityJson(elapsed: 1800)],
    );
    await openHistoryTab(tester);

    expect(find.textContaining('Ist 30 min (15 min kürzer)'), findsOneWidget);
    expect(find.textContaining('Plan 45 min'), findsOneWidget);
    expect(find.text('Erledigt'), findsOneWidget);
    expect(find.text('keine Aufzeichnung'), findsNothing);
    expect(
      find.text('1 erledigt · 0 teilweise · 0 ausgelassen · 0 offen'),
      findsOneWidget,
    );
    expect(find.text('Ist: 30 min / Plan: 45 min'), findsOneWidget);
  });

  testWidgets('Antippen öffnet das Sheet, started_at = Sitzungsdatum', (
    tester,
  ) async {
    final repository = await pumpApp(
      tester,
      sessions: <Map<String, dynamic>>[
        sessionJson(id: 's1', date: '2026-11-20'),
      ],
    );
    await openHistoryTab(tester);

    expect(find.text('Fr, 20.11.2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('history-session-s1')));
    await tester.pumpAndSettle();

    expect(find.text('Einheit erfassen'), findsOneWidget);
    // Tageskopf (Liste) + Untertitel im Sheet.
    expect(find.textContaining('Fr, 20.11.2026'), findsNWidgets(2));
    await tester.enterText(find.byKey(const Key('durationField')), '30');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('doneButton')));
    await tester.pumpAndSettle();

    // Liste aktualisiert sich sofort.
    expect(find.textContaining('Ist 30 min (15 min kürzer)'), findsOneWidget);
    final activity = repository.activityForSession('s1')!;
    final startedAt = DateTime.parse(activity.startedAt).toLocal();
    expect(startedAt.year, 2026);
    expect(startedAt.month, 11);
    expect(startedAt.day, 20);
    // Aktuelle Uhrzeit, nicht 00:00.
    expect(startedAt.hour, today.hour);
    expect(startedAt.minute, today.minute);
    expect(activity.startedAt, contains('2026-11-20T'));
  });

  testWidgets('ungeplante Einheit erscheint mit Kennzeichnung „ungeplant“', (
    tester,
  ) async {
    await pumpApp(
      tester,
      sessions: <Map<String, dynamic>>[],
      activities: <Map<String, dynamic>>[
        activityJson(
          id: 'frei-1',
          planId: null,
          planRevision: null,
          plannedSessionId: null,
          sport: 'run',
          startedAt: '2026-11-22T07:30:00+01:00',
          elapsed: 2400,
        ),
      ],
    );
    await openHistoryTab(tester);

    expect(find.text('ungeplant'), findsOneWidget);
    expect(find.text('Laufen'), findsOneWidget);
    expect(find.text('40 min'), findsOneWidget);
    expect(find.text('So, 22.11.2026'), findsOneWidget);
  });

  testWidgets('Zeitraum-Auswahl filtert die Tagesliste', (tester) async {
    await pumpApp(
      tester,
      sessions: <Map<String, dynamic>>[
        sessionJson(id: 's-neu', date: '2026-11-22'),
        sessionJson(id: 's-alt', date: '2026-10-30'),
      ],
    );
    await openHistoryTab(tester);

    // Standard: 30 Tage → beide Tage sichtbar.
    expect(find.text('So, 22.11.2026'), findsOneWidget);
    expect(find.text('Fr, 30.10.2026'), findsOneWidget);

    await tester.tap(find.text('7 Tage'));
    await tester.pumpAndSettle();
    expect(find.text('So, 22.11.2026'), findsOneWidget);
    expect(find.text('Fr, 30.10.2026'), findsNothing);

    await tester.tap(find.text('Alles'));
    await tester.pumpAndSettle();
    expect(find.text('Fr, 30.10.2026'), findsOneWidget);
  });

  testWidgets('Tagebucheintrag erscheint nur als Indikator im Verlauf', (
    tester,
  ) async {
    await pumpApp(
      tester,
      journal: <Map<String, dynamic>>[
        journalJson(
          overallFeeling: 70,
          text: 'Geheimer ausführlicher Text',
          timestamp: '2026-11-23T21:30:00+01:00',
        ),
      ],
    );
    await openHistoryTab(tester);

    expect(
      find.byKey(const ValueKey<String>('history-feeling-2026-11-23')),
      findsOneWidget,
    );
    expect(find.text('70 %'), findsOneWidget);
    // Der vollständige Text bleibt im Tagebuch-Tab.
    expect(find.text('Geheimer ausführlicher Text'), findsNothing);
  });
}
