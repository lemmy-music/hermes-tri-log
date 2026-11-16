import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_log/main.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/state/app_repository.dart';

/// Widget-Flows des Tagebuchs: FAB → Sheet, Speichern, Bearbeiten, Zurücksetzen.
void main() {
  final today = DateTime(2026, 11, 23, 9, 45);

  Future<AppRepository> pumpApp(
    WidgetTester tester, {
    List<JournalEntry> journal = const <JournalEntry>[],
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = AppRepository(
      clock: () => today,
      saveDebounce: const Duration(milliseconds: 1),
    );
    await repository.load();
    for (final entry in journal) {
      repository.saveJournalEntry(entry);
    }
    await repository.flush();

    await tester.pumpWidget(TriLogApp(repository: repository));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> openJournalTab(WidgetTester tester) async {
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
  }

  /// Simuliert das Verschieben des Sliders (deterministisch, ohne Pixeljagd).
  Future<void> setFeeling(WidgetTester tester, int value) async {
    final slider = tester.widget<Slider>(
      find.byKey(const Key('journalFeelingSlider')),
    );
    slider.onChanged!(value.toDouble());
    await tester.pumpAndSettle();
  }

  testWidgets('Tagebuch-FAB öffnet das Sheet, Speichern zeigt „60 %“ + Text', (
    tester,
  ) async {
    final repository = await pumpApp(tester);
    await openJournalTab(tester);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byKey(const Key('journalFab')));
    await tester.pumpAndSettle();

    expect(find.text('Tagebucheintrag'), findsOneWidget);
    // Neuer Eintrag: Befinden ist NICHT gesetzt.
    expect(find.text('nicht angegeben'), findsOneWidget);

    await setFeeling(tester, 60);
    expect(find.text('60 %'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('journalTextField')),
      'Guter Tag, Beine frisch.',
    );
    await tester.tap(find.byKey(const Key('journalSaveButton')));
    await tester.pumpAndSettle();

    // Rückmeldung IM Sheet, Sheet bleibt offen.
    expect(find.byKey(const Key('journalFeedback')), findsOneWidget);
    expect(find.textContaining('Gespeichert'), findsOneWidget);
    expect(find.text('Tagebucheintrag'), findsOneWidget);
    expect(repository.state.journal, hasLength(1));
    expect(repository.state.journal.single.overallFeeling, 60);
    expect(repository.state.journal.single.text, 'Guter Tag, Beine frisch.');
    // Neuer Eintrag bekommt den aktuellen Zeitpunkt (lokaler Offset).
    expect(
      DateTime.parse(
        repository.state.journal.single.timestamp,
      ).isAtSameMomentAs(today),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('journalDoneButton')));
    await tester.pumpAndSettle();

    expect(find.text('60 %'), findsOneWidget);
    expect(find.text('Guter Tag, Beine frisch.'), findsOneWidget);
    expect(find.text('09:45'), findsOneWidget);
    expect(find.text('Mo, 23.11.2026'), findsOneWidget);
  });

  testWidgets('Eintrag bearbeiten ändert den Wert, Zeitstempel bleibt', (
    tester,
  ) async {
    final repository = await pumpApp(
      tester,
      journal: <JournalEntry>[
        const JournalEntry(
          id: 'j1',
          timestamp: '2026-11-22T20:10:00+01:00',
          overallFeeling: 60,
          text: 'Erste Fassung',
        ),
      ],
    );
    await openJournalTab(tester);

    expect(find.text('60 %'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('journal-entry-j1')));
    await tester.pumpAndSettle();

    expect(find.text('60 %'), findsWidgets);
    await setFeeling(tester, 80);
    await tester.tap(find.byKey(const Key('journalSaveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('journalDoneButton')));
    await tester.pumpAndSettle();

    expect(find.text('80 %'), findsOneWidget);
    expect(find.text('60 %'), findsNothing);
    final saved = repository.journalEntryById('j1')!;
    expect(saved.overallFeeling, 80);
    expect(saved.timestamp, '2026-11-22T20:10:00+01:00');
    expect(repository.state.journal, hasLength(1));
  });

  testWidgets('Zurücksetzen setzt das Befinden auf null → Anzeige „–“', (
    tester,
  ) async {
    final repository = await pumpApp(
      tester,
      journal: <JournalEntry>[
        const JournalEntry(
          id: 'j1',
          timestamp: '2026-11-22T20:10:00+01:00',
          overallFeeling: 60,
          text: 'Text bleibt',
        ),
      ],
    );
    await openJournalTab(tester);

    await tester.tap(find.byKey(const ValueKey<String>('journal-entry-j1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('journalResetFeeling')));
    await tester.pumpAndSettle();
    expect(find.text('nicht angegeben'), findsOneWidget);

    await tester.tap(find.byKey(const Key('journalSaveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('journalDoneButton')));
    await tester.pumpAndSettle();

    expect(repository.journalEntryById('j1')!.overallFeeling, isNull);
    expect(repository.journalEntryById('j1')!.text, 'Text bleibt');
    final chip = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('journalFeelingChip')),
        matching: find.byType(Text),
      ),
    );
    expect(chip.data, '–');
    expect(find.text('60 %'), findsNothing);
  });

  testWidgets('Löschen fragt nach und entfernt den Eintrag', (tester) async {
    final repository = await pumpApp(
      tester,
      journal: <JournalEntry>[
        const JournalEntry(
          id: 'j1',
          timestamp: '2026-11-22T20:10:00+01:00',
          overallFeeling: 55,
          text: 'weg damit',
        ),
      ],
    );
    await openJournalTab(tester);

    await tester.tap(find.byKey(const ValueKey<String>('journal-entry-j1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('journalDeleteButton')));
    await tester.pumpAndSettle();

    expect(find.text('Tagebucheintrag löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(repository.state.journal, hasLength(1));

    await tester.tap(find.byKey(const Key('journalDeleteButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await tester.pumpAndSettle();

    expect(repository.state.journal, isEmpty);
    expect(find.textContaining('Gelöscht'), findsOneWidget);

    await tester.tap(find.byKey(const Key('journalDoneButton')));
    await tester.pumpAndSettle();
    expect(find.text('Noch keine Einträge'), findsOneWidget);
  });
}
