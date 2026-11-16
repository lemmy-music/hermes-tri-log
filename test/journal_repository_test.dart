import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/services/history_service.dart';
import 'package:tri_log/state/app_repository.dart';
import 'package:tri_log/utils/formats.dart';

/// Repository-Operationen für Tagebucheinträge (Upsert, Löschen, Sortierung,
/// Persistenz) – ohne UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = DateTime(2026, 11, 23, 21, 30);

  AppRepository newRepository() => AppRepository(
    clock: () => today,
    saveDebounce: const Duration(milliseconds: 1),
  );

  /// Frischer Speicher + Repository (für jeden Test).
  AppRepository buildRepository() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return newRepository();
  }

  JournalEntry entry({
    required String id,
    required DateTime at,
    int? feeling,
    String? text,
  }) => JournalEntry(
    id: id,
    timestamp: isoWithOffset(at),
    overallFeeling: feeling,
    text: text,
  );

  test('legt einen Eintrag an (ID-Präfix jnl, Werte unverändert)', () async {
    final repository = buildRepository();
    await repository.load();

    final id = repository.nextJournalEntryId();
    expect(id, startsWith('jnl-'));

    repository.saveJournalEntry(
      JournalEntry(
        id: id,
        timestamp: isoWithOffset(today),
        overallFeeling: 60,
        text: 'Gut geschlafen, ruhiger Tag.',
      ),
    );

    expect(repository.state.journal, hasLength(1));
    final saved = repository.journalEntryById(id)!;
    expect(saved.overallFeeling, 60);
    expect(saved.text, 'Gut geschlafen, ruhiger Tag.');
    expect(DateTime.parse(saved.timestamp).isAtSameMomentAs(today), isTrue);

    repository.dispose();
  });

  test('saveJournalEntry ist ein Upsert per id (kein Duplikat)', () async {
    final repository = buildRepository();
    await repository.load();
    final timestamp = isoWithOffset(today);

    repository.saveJournalEntry(
      JournalEntry(
        id: 'j1',
        timestamp: timestamp,
        overallFeeling: 60,
        text: 'erste Fassung',
      ),
    );
    repository.saveJournalEntry(
      JournalEntry(
        id: 'j1',
        timestamp: timestamp,
        overallFeeling: 30,
        text: 'zweite Fassung',
      ),
    );

    expect(repository.state.journal, hasLength(1));
    expect(repository.state.journal.single.overallFeeling, 30);
    expect(repository.state.journal.single.text, 'zweite Fassung');

    repository.dispose();
  });

  test('mehrere Einträge pro Tag, aufsteigend nach Uhrzeit', () async {
    final repository = buildRepository();
    await repository.load();

    repository.saveJournalEntry(
      entry(
        id: 'j-late',
        at: DateTime(2026, 11, 23, 21, 15),
        feeling: 40,
        text: 'abends',
      ),
    );
    repository.saveJournalEntry(
      entry(
        id: 'j-early',
        at: DateTime(2026, 11, 23, 7, 5),
        feeling: 70,
        text: 'morgens',
      ),
    );

    expect(repository.state.journal, hasLength(2));
    final ofDay = repository.journalEntriesForDate(DateTime(2026, 11, 23));
    expect(ofDay.map((e) => e.id), <String>['j-early', 'j-late']);
    // Der letzte Eintrag des Tages bestimmt das Tagesbefinden.
    expect(repository.latestJournalFeelingForDate(DateTime(2026, 11, 23)), 40);
    // Einträge eines anderen Tages bleiben außen vor.
    expect(repository.journalEntriesForDate(DateTime(2026, 11, 22)), isEmpty);
    expect(
      repository.latestJournalFeelingForDate(DateTime(2026, 11, 22)),
      isNull,
    );

    repository.dispose();
  });

  test('journalEntriesNewestFirst sortiert absteigend', () async {
    final repository = buildRepository();
    await repository.load();

    repository.saveJournalEntry(
      entry(id: 'a', at: DateTime(2026, 11, 21, 9), feeling: 50),
    );
    repository.saveJournalEntry(
      entry(id: 'b', at: DateTime(2026, 11, 23, 9), feeling: 80),
    );
    repository.saveJournalEntry(
      entry(id: 'c', at: DateTime(2026, 11, 22, 20), feeling: 65),
    );

    expect(repository.journalEntriesNewestFirst.map((e) => e.id), <String>[
      'b',
      'c',
      'a',
    ]);

    repository.dispose();
  });

  test('deleteJournalEntry entfernt den Eintrag und benachrichtigt', () async {
    final repository = buildRepository();
    await repository.load();
    repository.saveJournalEntry(
      entry(id: 'j1', at: today, feeling: 60, text: 'Text'),
    );

    var notifications = 0;
    repository.addListener(() => notifications++);

    repository.deleteJournalEntry('j1');
    expect(repository.state.journal, isEmpty);
    expect(notifications, 1);

    // Unbekannte ID: kein Effekt, keine Benachrichtigung.
    repository.deleteJournalEntry('gibt-es-nicht');
    expect(notifications, 1);

    repository.dispose();
  });

  test('Persistenz-Roundtrip inkl. null-Befinden', () async {
    final repository = buildRepository();
    await repository.load();
    repository.saveJournalEntry(
      entry(
        id: 'j-null',
        at: DateTime(2026, 11, 23, 8, 0),
        text: 'Nur Text, kein Befinden.',
      ),
    );
    expect(repository.state.journal.single.overallFeeling, isNull);
    // null bleibt null – im JSON ausdrücklich null, nicht 0.
    expect(repository.state.journal.single.toJson()['overall_feeling'], isNull);

    await repository.flush();
    repository.dispose();

    // Gleicher (Mock-)Speicher, neue Instanz – kein Reset der Werte.
    final reloaded = newRepository();
    await reloaded.load();
    expect(reloaded.state.journal, hasLength(1));
    final restored = reloaded.state.journal.single;
    expect(restored.id, 'j-null');
    expect(restored.overallFeeling, isNull);
    expect(restored.text, 'Nur Text, kein Befinden.');
    reloaded.dispose();
  });

  group('groupJournalByDay', () {
    test('gruppiert nach Tag, Tage absteigend, Einträge aufsteigend', () {
      final entries = <JournalEntry>[
        entry(id: 'n1', at: DateTime(2026, 11, 23, 21), feeling: 40),
        entry(id: 'o1', at: DateTime(2026, 11, 21, 8), feeling: 70),
        entry(id: 'n2', at: DateTime(2026, 11, 23, 7), feeling: 80, text: 'x'),
        entry(id: 'o2', at: DateTime(2026, 11, 22, 12), feeling: null),
      ];

      final groups = groupJournalByDay(entries);
      expect(groups.map((g) => g.dateIso), <String>[
        '2026-11-23',
        '2026-11-22',
        '2026-11-21',
      ]);
      expect(groups.first.entries.map((e) => e.id), <String>['n2', 'n1']);
      expect(groups.first.lastFeeling, 40);
      expect(groups[1].lastFeeling, isNull);
      expect(groups.last.lastFeeling, 70);
    });

    test('unlesbare Zeitstempel werden nicht erfunden (ignoriert)', () {
      final groups = groupJournalByDay(<JournalEntry>[
        entry(id: 'ok', at: DateTime(2026, 11, 23, 9), feeling: 60),
        const JournalEntry(id: 'kaputt', timestamp: 'keine-zeit', text: 'x'),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.entries.single.id, 'ok');
    });
  });

  test('sortJournalNewestFirst: unlesbare Zeitstempel ans Ende', () {
    final sorted = sortJournalNewestFirst(<JournalEntry>[
      const JournalEntry(id: 'kaputt', timestamp: 'xyz'),
      entry(id: 'alt', at: DateTime(2026, 11, 20, 9), feeling: 10),
      entry(id: 'neu', at: DateTime(2026, 11, 23, 9), feeling: 90),
    ]);
    expect(sorted.map((e) => e.id), <String>['neu', 'alt', 'kaputt']);
  });
}
