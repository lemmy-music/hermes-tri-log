import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_log/main.dart';
import 'package:tri_log/services/history_service.dart';
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
    bool tall = false,
  }) async {
    if (tall) {
      // Genug Platz, damit auch tiefere Zeilen ohne Scrollen gebaut werden.
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
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

  testWidgets('Sheet aus dem Verlauf zeigt den Plan-Block', (tester) async {
    const instructions =
        'Ruhiger Dauerlauf im Grundlagenbereich.\n'
        'Puls unter 145 halten, die letzten 10 Minuten locker auslaufen.';
    await pumpApp(
      tester,
      sessions: <Map<String, dynamic>>[
        sessionJson(
          id: 's1',
          date: '2026-11-20',
          instructions: instructions,
          structure: <String, dynamic>{
            'warmup_seconds': 600,
            'repetitions': 3,
            'work_seconds': 300,
            'cooldown_seconds': 600,
          },
        ),
      ],
    );
    await openHistoryTab(tester);

    await tester.tap(find.byKey(const ValueKey<String>('history-session-s1')));
    await tester.pumpAndSettle();

    final block = find.byKey(const Key('plannedSummary'));
    expect(block, findsOneWidget);
    expect(
      find.descendant(of: block, matching: find.text(instructions)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: block, matching: find.text('Plan: 45 min')),
      findsOneWidget,
    );
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

  testWidgets('Zeitraum-Auswahl filtert die Tagesliste (Standard 30)', (
    tester,
  ) async {
    await pumpApp(
      tester,
      sessions: <Map<String, dynamic>>[
        sessionJson(id: 's-neu', date: '2026-11-22'),
        sessionJson(id: 's-alt', date: '2026-10-30'),
      ],
    );
    await openHistoryTab(tester);

    // Standard: „30 Tage“ (−30/+30) → beide Tage im Zeitraum.
    final segments = tester.widget<SegmentedButton<HistoryRange>>(
      find.byKey(const Key('historyRangeSegments')),
    );
    expect(segments.selected.single, HistoryRange.last30Days);
    expect(find.text('So, 22.11.2026'), findsOneWidget);
    expect(
      find.text('0 erledigt · 0 teilweise · 0 ausgelassen · 2 offen'),
      findsOneWidget,
    );

    await tester.tap(find.text('7 Tage'));
    await tester.pumpAndSettle();
    expect(find.text('So, 22.11.2026'), findsOneWidget);
    // 30.10. liegt außerhalb von heute ±7 → nur noch eine Sitzung im Zeitraum.
    expect(
      find.text('0 erledigt · 0 teilweise · 0 ausgelassen · 1 offen'),
      findsOneWidget,
    );

    await tester.tap(find.text('Alles'));
    await tester.pumpAndSettle();
    // „Alles“ reicht bis zum frühesten Inhalt zurück.
    expect(
      find.text('0 erledigt · 0 teilweise · 0 ausgelassen · 2 offen'),
      findsOneWidget,
    );
  });

  testWidgets('heutiger Tag ist mit „Heute“ gekennzeichnet und zentriert', (
    tester,
  ) async {
    await pumpApp(
      tester,
      sessions: <Map<String, dynamic>>[
        sessionJson(id: 's1', date: '2026-11-20'),
        sessionJson(id: 's2', date: '2026-11-22'),
        sessionJson(id: 's3', date: '2026-11-23'),
      ],
    );
    await openHistoryTab(tester);

    final chip = find.byKey(const Key('history-today-chip'));
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('Heute')),
      findsOneWidget,
    );

    // Zentrierung: die Liste startet exakt auf dem heutigen Tageskopf.
    // Zeilen: 20. Kopf, 20. Sitzung, 22. Kopf, 22. Sitzung, 23. Kopf …
    final list = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    expect(list.initialScrollIndex, 4);
    expect(list.initialAlignment, 0.45);
  });

  testWidgets('Zukunftszeile zeigt „geplant“, nicht „keine Aufzeichnung“', (
    tester,
  ) async {
    await pumpApp(
      tester,
      sessions: <Map<String, dynamic>>[
        sessionJson(id: 'zukunft', date: '2026-11-26'),
      ],
    );
    await openHistoryTab(tester);

    const counts =
        '0 erledigt · 0 teilweise · 0 ausgelassen · 0 offen · '
        '1 geplant (Zukunft)';
    expect(find.text(counts), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('history-planned-zukunft')),
      findsOneWidget,
    );
    expect(find.text('keine Aufzeichnung'), findsNothing);
    expect(find.textContaining('geplant'), findsWidgets);
  });

  testWidgets('Tap auf eine Zukunfts-Sitzung öffnet das Lese-Sheet', (
    tester,
  ) async {
    const instructions =
        'Ruhiger Dauerlauf im Grundlagenbereich.\n'
        'Puls unter 145 halten, die letzten 10 Minuten locker auslaufen.';
    await pumpApp(
      tester,
      tall: true,
      sessions: <Map<String, dynamic>>[
        sessionJson(
          id: 'zukunft',
          date: '2026-11-26',
          sport: 'run',
          type: 'Dauerlauf',
          instructions: instructions,
          structure: <String, dynamic>{
            'warmup_seconds': 600,
            'repetitions': 3,
            'work_seconds': 300,
            'cooldown_seconds': 600,
          },
        ),
      ],
    );
    await openHistoryTab(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('history-session-zukunft')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Planung ansehen'), findsOneWidget);
    expect(find.text('Do, 26.11.2026'), findsWidgets);
    expect(find.text(instructions), findsOneWidget);
    expect(find.text('Plan: 45 min'), findsOneWidget);
    expect(find.textContaining('3× 5 min'), findsOneWidget);
    // Rein lesend: kein Speichern, kein Status, keine Eingabefelder.
    expect(find.byKey(const Key('saveButton')), findsNothing);
    expect(find.byKey(const Key('statusSegments')), findsNothing);
    expect(find.text('Einheit erfassen'), findsNothing);
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
