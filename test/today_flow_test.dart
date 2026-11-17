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

  Future<AppRepository> buildRepository({
    bool withPlan = true,
    String? instructions,
    Map<String, dynamic>? structure,
    List<Map<String, dynamic>>? extraSessions,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = AppRepository(
      clock: () => today,
      saveDebounce: const Duration(milliseconds: 1),
    );
    await repository.load();
    if (withPlan) {
      repository.importPlans(
        repository.parseImport(
          documentJson(
            plans: <Map<String, dynamic>>[
              planJson(
                sessions: <Map<String, dynamic>>[
                  sessionJson(instructions: instructions, structure: structure),
                  ...?extraSessions,
                ],
              ),
            ],
          ),
        ),
      );
      await repository.flush();
    }
    return repository;
  }

  Future<AppRepository> pumpApp(
    WidgetTester tester, {
    bool withPlan = true,
    String? instructions,
    Map<String, dynamic>? structure,
    List<Map<String, dynamic>>? extraSessions,
    bool tall = false,
  }) async {
    if (tall) {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final repository = await buildRepository(
      withPlan: withPlan,
      instructions: instructions,
      structure: structure,
      extraSessions: extraSessions,
    );
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

  // ─── Volle Plan-Beschreibung (Karte + Sheet) ──────────────────────────────

  const longInstructions =
      'Einschwimmen: 400 m locker, danach 8× 50 m Technik mit ruhiger Atmung.\n'
      'Hauptteil: 6× 100 m im Zug um die 1:45, dazwischen 30 s Pause – Fokus '
      'auf lange Wasserlage und gleichmäßigen Rhythmus.\n'
      'Abschluss: 200 m ausschwimmen, 5 Minuten Schulter mobilisieren. '
      'Bei Müdigkeit den Umfang kürzen – Qualität vor Menge.';

  const structureJson = <String, dynamic>{
    'warmup_seconds': 600,
    'repetitions': 3,
    'work_seconds': 300,
    'recovery_seconds': 180,
    'cooldown_seconds': 1140,
  };

  testWidgets('Karte zeigt eine lange Beschreibung vollständig', (
    tester,
  ) async {
    expect(longInstructions.length, greaterThan(300));
    await pumpApp(tester, instructions: longInstructions);

    final finder = find.text(longInstructions);
    expect(finder, findsOneWidget);

    final text = tester.widget<Text>(finder);
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    // Zeilenumbrüche bleiben erhalten.
    expect(text.data, contains('\n'));
  });

  testWidgets('Karte zeigt eine lange Ist-Notiz vollständig', (tester) async {
    const longNotes =
        'Beine schwer, aber Technik lief.\n'
        'Nach 30 Minuten kurz locker gemacht, danach noch 10 Minuten '
        'ausgeschwommen. Schulter rechts etwas zwicken – beobachten.';

    final repository = await buildRepository();
    final plan = repository.state.plans.single;
    final session = plan.sessions.single;
    repository.saveActivityForSession(
      plan: plan,
      session: session,
      status: ActivityStatus.completed,
      elapsedDurationSeconds: 2700,
      notes: longNotes,
    );
    await repository.flush();

    await tester.pumpWidget(TriLogApp(repository: repository));
    await tester.pumpAndSettle();

    final finder = find.text(longNotes);
    expect(finder, findsOneWidget);
    final text = tester.widget<Text>(finder);
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets(
    'Sheet zeigt Plan-Block mit vollständiger Beschreibung, Dauer und Struktur',
    (tester) async {
      await pumpApp(
        tester,
        instructions: longInstructions,
        structure: structureJson,
      );

      await tester.tap(find.text('Technik'));
      await tester.pumpAndSettle();

      expect(find.text('Einheit erfassen'), findsOneWidget);
      final block = find.byKey(const Key('plannedSummary'));
      expect(block, findsOneWidget);

      final instructionsInSheet = find.descendant(
        of: block,
        matching: find.text(longInstructions),
      );
      expect(instructionsInSheet, findsOneWidget);
      expect(tester.widget<Text>(instructionsInSheet).maxLines, isNull);
      expect(
        tester.widget<Text>(instructionsInSheet).overflow,
        isNot(TextOverflow.ellipsis),
      );
      expect(
        find.descendant(of: block, matching: find.text('Plan: 45 min')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: block, matching: find.textContaining('3× 5 min')),
        findsOneWidget,
      );

      // Speichern bleibt erreichbar und der Plan-Block bleibt sichtbar.
      await tester.tap(find.byKey(const Key('saveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sheetFeedback')), findsOneWidget);
      expect(find.byKey(const Key('plannedSummary')), findsOneWidget);
      expect(
        find.descendant(of: block, matching: find.text(longInstructions)),
        findsOneWidget,
      );
    },
  );

  testWidgets('Ungeplante Einheit zeigt keinen Plan-Block im Sheet', (
    tester,
  ) async {
    await pumpApp(tester, withPlan: false);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Einheit erfassen'), findsOneWidget);
    expect(find.byKey(const Key('plannedSummary')), findsNothing);
    expect(find.textContaining('Plan:'), findsNothing);
    expect(find.textContaining('Planung'), findsNothing);
  });

  // ─── Kommende Tage (Vorschau der nächsten 7 Kalendertage) ─────────────────

  const futureInstructions =
      'Lockerer Dauerlauf, Puls unter 145.\n'
      'Zum Schluss 4× 20 Sekunden Steigerung, dazwischen traben.';

  List<Map<String, dynamic>> futureSessions() => <Map<String, dynamic>>[
    sessionJson(
      id: 's3',
      date: '2026-11-26',
      sport: 'run',
      type: 'Dauerlauf',
      optional: true,
      plannedDurationSeconds: 2400,
      instructions: futureInstructions,
      structure: <String, dynamic>{
        'warmup_seconds': 600,
        'repetitions': 3,
        'work_seconds': 300,
        'cooldown_seconds': 600,
      },
    ),
  ];

  testWidgets('Kommende Tage zeigt nur Tage mit Sitzung', (tester) async {
    await pumpApp(tester, tall: true, extraSessions: futureSessions());

    expect(find.text('Kommende Tage'), findsOneWidget);
    // Sitzung in 3 Tagen ist da …
    expect(
      find.byKey(const ValueKey<String>('upcoming-day-2026-11-26')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('upcoming-session-s3')),
      findsOneWidget,
    );
    // … Tage ohne Sitzung (morgen, übermorgen) fehlen komplett.
    expect(
      find.byKey(const ValueKey<String>('upcoming-day-2026-11-24')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('upcoming-day-2026-11-25')),
      findsNothing,
    );
    // Kompakt: Dauer + optional-Kennzeichnung.
    expect(find.text('40 min'), findsOneWidget);
    expect(find.text('optional'), findsWidgets);
  });

  testWidgets('Ohne geplante Zukunft fehlt der Abschnitt komplett', (
    tester,
  ) async {
    await pumpApp(tester, tall: true);

    expect(find.text('Kommende Tage'), findsNothing);
  });

  testWidgets('Tap auf kommende Sitzung öffnet das Lese-Sheet', (tester) async {
    await pumpApp(tester, tall: true, extraSessions: futureSessions());

    await tester.tap(find.byKey(const ValueKey<String>('upcoming-session-s3')));
    await tester.pumpAndSettle();

    expect(find.text('Planung ansehen'), findsOneWidget);
    // Datum steht im Sheet-Kopf und (hinter dem Sheet) im Tageskopf der Liste.
    expect(find.text('Do, 26.11.2026'), findsWidgets);
    expect(find.text('Laufen · Wintergrundlage'), findsOneWidget);
    expect(find.text('Plan: 40 min'), findsWidgets);
    expect(find.text(futureInstructions), findsOneWidget);
    expect(find.textContaining('3× 5 min'), findsOneWidget);
    // Rein lesend: kein Speichern, keine Statusauswahl, keine Eingabefelder.
    expect(find.byKey(const Key('saveButton')), findsNothing);
    expect(find.byKey(const Key('statusSegments')), findsNothing);
    expect(find.byKey(const Key('durationField')), findsNothing);
    await tester.tap(find.byKey(const Key('planDetailCloseButton')));
    await tester.pumpAndSettle();
    expect(find.text('Planung ansehen'), findsNothing);
  });
}
