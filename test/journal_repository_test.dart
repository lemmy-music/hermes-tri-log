import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/services/history_service.dart';
import 'package:tri_log/services/storage.dart';
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

  group('Tagesnotiz (updated_at/finalized_at)', () {
    /// Repository mit steuerbarer Uhr (für Änderungs-/Abschlusszeiten).
    ({AppRepository repository, void Function(DateTime) setNow}) buildClocked(
      DateTime start,
    ) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      var current = start;
      final repository = AppRepository(
        clock: () => current,
        saveDebounce: const Duration(milliseconds: 1),
      );
      return (
        repository: repository,
        setNow: (DateTime next) => current = next,
      );
    }

    test(
      'saveJournalEntry setzt updated_at, timestamp bleibt erhalten',
      () async {
        final clocked = buildClocked(DateTime(2026, 11, 23, 7, 12, 30));
        final repository = clocked.repository;
        await repository.load();

        final created = repository.saveJournalEntry(
          JournalEntry(
            id: 'j1',
            timestamp: isoWithOffset(DateTime(2026, 11, 23, 7, 12, 30)),
            overallFeeling: 60,
            text: 'morgens',
          ),
        );
        expect(
          DateTime.parse(
            created.updatedAt!,
          ).isAtSameMomentAs(DateTime(2026, 11, 23, 7, 12, 30)),
          isTrue,
        );
        expect(created.finalizedAt, isNull);

        clocked.setNow(DateTime(2026, 11, 23, 18, 40));
        final edited = repository.saveJournalEntry(
          JournalEntry(
            id: 'j1',
            timestamp: created.timestamp,
            overallFeeling: 55,
            text: 'morgens, abends ergänzt',
          ),
        );

        expect(edited.timestamp, created.timestamp);
        expect(
          DateTime.parse(
            edited.updatedAt!,
          ).isAtSameMomentAs(DateTime(2026, 11, 23, 18, 40)),
          isTrue,
        );
        expect(repository.state.journal, hasLength(1));
        expect(
          repository.journalEntryById('j1')!.text,
          'morgens, abends ergänzt',
        );

        repository.dispose();
      },
    );

    test(
      'abschließen setzt finalized_at; späteres Speichern lässt es stehen',
      () async {
        final clocked = buildClocked(DateTime(2026, 11, 23, 7, 12));
        final repository = clocked.repository;
        await repository.load();

        final created = repository.saveJournalEntry(
          JournalEntry(
            id: 'j1',
            timestamp: isoWithOffset(DateTime(2026, 11, 23, 7, 12)),
            overallFeeling: 60,
            text: 'tagsüber',
          ),
        );

        clocked.setNow(DateTime(2026, 11, 23, 21, 30));
        final finalized = repository.finalizeJournalEntry(created);
        expect(finalized.finalizedAt, isNotNull);
        expect(
          DateTime.parse(
            finalized.finalizedAt!,
          ).isAtSameMomentAs(DateTime(2026, 11, 23, 21, 30)),
          isTrue,
        );
        expect(finalized.timestamp, created.timestamp);
        expect(finalized.isFinalized, isTrue);

        // Abgeschlossen + erneut speichern: updated_at neu, finalized_at bleibt.
        clocked.setNow(DateTime(2026, 11, 23, 22, 5));
        final reopenedEdit = repository.saveJournalEntry(
          JournalEntry(
            id: 'j1',
            timestamp: finalized.timestamp,
            finalizedAt: finalized.finalizedAt,
            overallFeeling: 65,
            text: 'nachgetragen',
          ),
        );
        expect(reopenedEdit.finalizedAt, finalized.finalizedAt);
        expect(
          DateTime.parse(
            reopenedEdit.updatedAt!,
          ).isAtSameMomentAs(DateTime(2026, 11, 23, 22, 5)),
          isTrue,
        );
        expect(repository.journalEntryById('j1')!.overallFeeling, 65);

        repository.dispose();
      },
    );

    test('wieder öffnen setzt finalized_at auf null, Eintrag bleibt', () async {
      final clocked = buildClocked(DateTime(2026, 11, 23, 21, 30));
      final repository = clocked.repository;
      await repository.load();

      repository.saveJournalEntry(
        entry(id: 'j1', at: DateTime(2026, 11, 23, 7, 12), feeling: 60),
      );
      final finalized = repository.finalizeJournalEntry(
        repository.journalEntryById('j1')!,
      );
      expect(finalized.isFinalized, isTrue);

      clocked.setNow(DateTime(2026, 11, 23, 23, 15));
      final reopened = repository.reopenJournalEntry(finalized);
      expect(reopened.finalizedAt, isNull);
      expect(reopened.isFinalized, isFalse);
      expect(reopened.timestamp, finalized.timestamp);
      expect(repository.state.journal, hasLength(1));
      expect(repository.journalEntryById('j1')!.text, finalized.text);

      repository.dispose();
    });

    test(
      'Tagesnotiz nutzt den neuesten Eintrag und legt keinen weiteren an',
      () async {
        final repository = buildRepository();
        await repository.load();

        repository.saveJournalEntry(
          entry(id: 'j-early', at: DateTime(2026, 11, 23, 8), feeling: 70),
        );
        repository.saveJournalEntry(
          entry(id: 'j-late', at: DateTime(2026, 11, 23, 12), feeling: 55),
        );
        repository.saveJournalEntry(
          entry(id: 'j-gestern', at: DateTime(2026, 11, 22, 20), feeling: 40),
        );

        expect(repository.todayJournalEntry?.id, 'j-late');
        expect(
          repository.latestJournalEntryForDate(DateTime(2026, 11, 22))?.id,
          'j-gestern',
        );

        // Bearbeiten des neuesten Eintrags ist ein Upsert – kein dritter Eintrag,
        // nichts wird gelöscht.
        repository.saveJournalEntry(
          JournalEntry(
            id: 'j-late',
            timestamp: repository.journalEntryById('j-late')!.timestamp,
            overallFeeling: 60,
            text: 'weiter geschrieben',
          ),
        );
        expect(repository.state.journal, hasLength(3));
        expect(
          repository.journalEntriesForDate(DateTime(2026, 11, 23)),
          hasLength(2),
        );
        expect(repository.todayJournalEntry?.text, 'weiter geschrieben');

        repository.dispose();
      },
    );
  });

  group('automatischer Abschluss vergangener Entwürfe', () {
    final yesterday = DateTime(2026, 11, 22, 20, 10);

    /// Eintrag von gestern als Entwurf (nach dem Laden gespeichert, damit er
    /// nicht schon beim Laden abgeschlossen wird).
    JournalEntry saveYesterdayDraft(
      AppRepository repository, {
      String id = 'j1',
    }) => repository.saveJournalEntry(
      entry(id: id, at: yesterday, feeling: 60, text: 'offen geblieben'),
    );

    test(
      'schließt gestern um 23:59 ab, zählt, lässt updated_at stehen',
      () async {
        final repository = buildRepository();
        await repository.load();
        final created = saveYesterdayDraft(repository);

        var notifications = 0;
        repository.addListener(() => notifications++);

        final count = repository.finalizeStaleJournalDrafts();

        expect(count, 1);
        expect(notifications, 1);
        final finalized = repository.journalEntryById('j1')!;
        expect(finalized.isFinalized, isTrue);
        expect(finalized.finalizedAutomatically, isTrue);
        expect(
          finalized.finalizedLocal!.isAtSameMomentAs(
            DateTime(2026, 11, 22, 23, 59),
          ),
          isTrue,
        );
        // Änderungszeitpunkt bleibt der letzte Speichervorgang.
        expect(finalized.updatedAt, created.updatedAt);
        expect(
          DateTime.parse(finalized.updatedAt!).isAtSameMomentAs(today),
          isTrue,
        );
        expect(finalized.text, 'offen geblieben');

        repository.dispose();
      },
    );

    test(
      'zweiter Aufruf ändert nichts (idempotent, keine Benachrichtigung)',
      () async {
        final repository = buildRepository();
        await repository.load();
        saveYesterdayDraft(repository);
        expect(repository.finalizeStaleJournalDrafts(), 1);
        final before = repository.journalEntryById('j1')!;

        var notifications = 0;
        repository.addListener(() => notifications++);
        expect(repository.finalizeStaleJournalDrafts(), 0);
        expect(notifications, 0);
        expect(
          repository.journalEntryById('j1')!.finalizedAt,
          before.finalizedAt,
        );

        repository.dispose();
      },
    );

    test('heutiger Entwurf wird nicht abgeschlossen', () async {
      final repository = buildRepository();
      await repository.load();
      repository.saveJournalEntry(
        entry(id: 'heute', at: DateTime(2026, 11, 23, 7, 12), feeling: 60),
      );

      expect(repository.finalizeStaleJournalDrafts(), 0);
      expect(repository.journalEntryById('heute')!.isFinalized, isFalse);

      repository.dispose();
    });

    test(
      'Persistenz-Roundtrip: Flag und 23:59 überleben das Neuladen',
      () async {
        final repository = buildRepository();
        await repository.load();
        saveYesterdayDraft(repository);
        expect(repository.finalizeStaleJournalDrafts(), 1);
        await repository.flush();
        repository.dispose();

        final reloaded = newRepository();
        await reloaded.load();
        final restored = reloaded.journalEntryById('j1')!;
        expect(restored.finalizedAutomatically, isTrue);
        expect(
          restored.finalizedLocal!.isAtSameMomentAs(
            DateTime(2026, 11, 22, 23, 59),
          ),
          isTrue,
        );
        // Bereits abgeschlossen → beim Laden nichts mehr zu tun.
        expect(reloaded.finalizeStaleJournalDrafts(), 0);
        reloaded.dispose();
      },
    );

    test('load() schließt vergangene Entwürfe beim App-Start ab', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        StorageService.storageKey: jsonEncode(<String, dynamic>{
          'schema_version': '1.1',
          'timezone': 'Europe/Berlin',
          'plans': <dynamic>[],
          'journal': <dynamic>[
            <String, dynamic>{
              'id': 'j-gestern',
              'timestamp': isoWithOffset(yesterday),
              'updated_at': isoWithOffset(DateTime(2026, 11, 22, 21, 0)),
              'finalized_at': null,
              'finalized_automatically': false,
              'overall_feeling': 60,
              'text': 'gestern offen',
            },
            <String, dynamic>{
              'id': 'j-heute',
              'timestamp': isoWithOffset(DateTime(2026, 11, 23, 8, 0)),
              'updated_at': null,
              'finalized_at': null,
              'overall_feeling': 70,
              'text': 'heute',
            },
          ],
        }),
      });

      final repository = newRepository();
      await repository.load();

      final gestern = repository.journalEntryById('j-gestern')!;
      expect(gestern.isFinalized, isTrue);
      expect(gestern.finalizedAutomatically, isTrue);
      expect(gestern.finalizedLocal!.hour, 23);
      expect(gestern.finalizedLocal!.minute, 59);
      expect(
        gestern.finalizedLocal!.isAtSameMomentAs(
          DateTime(2026, 11, 22, 23, 59),
        ),
        isTrue,
      );
      // Heute bleibt Entwurf.
      expect(repository.journalEntryById('j-heute')!.isFinalized, isFalse);

      repository.dispose();
    });

    test('App-Resume schließt über Mitternacht offene Entwürfe ab', () async {
      final clocked = <DateTime>[DateTime(2026, 11, 23, 23, 55)];
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repository = AppRepository(
        clock: () => clocked.single,
        saveDebounce: const Duration(milliseconds: 1),
      );
      await repository.load();
      repository.saveJournalEntry(
        entry(id: 'j1', at: DateTime(2026, 11, 23, 21, 0), feeling: 60),
      );
      expect(repository.journalEntryById('j1')!.isFinalized, isFalse);

      // Über Mitternacht: die App kommt aus dem Hintergrund zurück.
      clocked[0] = DateTime(2026, 11, 24, 0, 2);
      repository.didChangeAppLifecycleState(AppLifecycleState.resumed);

      final finalized = repository.journalEntryById('j1')!;
      expect(finalized.finalizedAutomatically, isTrue);
      expect(
        finalized.finalizedLocal!.isAtSameMomentAs(
          DateTime(2026, 11, 23, 23, 59),
        ),
        isTrue,
      );

      repository.dispose();
    });

    test(
      'manueller Abschluss setzt das Flag false, Wiederöffnen ebenso',
      () async {
        final repository = buildRepository();
        await repository.load();
        final created = repository.saveJournalEntry(
          entry(id: 'j1', at: today, feeling: 60, text: 'manuell'),
        );

        final manual = repository.finalizeJournalEntry(created);
        expect(manual.isFinalized, isTrue);
        expect(manual.finalizedAutomatically, isFalse);

        final reopened = repository.reopenJournalEntry(manual);
        expect(reopened.isFinalized, isFalse);
        expect(reopened.finalizedAutomatically, isFalse);

        repository.dispose();
      },
    );

    test(
      'Wiederöffnen eines automatisch abgeschlossenen Eintrags löscht das Flag',
      () async {
        final repository = buildRepository();
        await repository.load();
        saveYesterdayDraft(repository);
        expect(repository.finalizeStaleJournalDrafts(), 1);
        final auto = repository.journalEntryById('j1')!;
        expect(auto.finalizedAutomatically, isTrue);

        final reopened = repository.reopenJournalEntry(auto);
        expect(reopened.finalizedAt, isNull);
        expect(reopened.finalizedAutomatically, isFalse);
        expect(
          repository.journalEntryById('j1')!.isAutomaticallyFinalized,
          isFalse,
        );

        repository.dispose();
      },
    );
  });
}
