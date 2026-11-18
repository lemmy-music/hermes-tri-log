import 'package:flutter_test/flutter_test.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/services/journal_service.dart';
import 'package:tri_log/utils/formats.dart';

/// Reine Funktion [staleDraftFinalizations]: vergessene Entwürfe werden
/// rückwirkend um 23:59 des Eintragstags abgeschlossen – heute nie.
void main() {
  JournalEntry draft(
    String id,
    DateTime at, {
    int? feeling,
    String? text,
    String? updatedAt,
  }) => JournalEntry(
    id: id,
    timestamp: isoWithOffset(at),
    updatedAt: updatedAt,
    overallFeeling: feeling,
    text: text,
  );

  final today = DateTime(2026, 11, 23, 9, 45);

  test('Entwurf von gestern → 23:59 lokal, Flag true, updated_at bleibt', () {
    final yesterday = DateTime(2026, 11, 22, 20, 10);
    final updated = DateTime(2026, 11, 22, 22, 5);
    final entry = draft(
      'j1',
      yesterday,
      feeling: 60,
      text: 'Gestern notiert',
      updatedAt: isoWithOffset(updated),
    );

    final changes = staleDraftFinalizations(<JournalEntry>[entry], today);

    expect(changes, hasLength(1));
    final result = changes.single;
    expect(result.id, 'j1');
    expect(result.finalizedAutomatically, isTrue);
    expect(result.isFinalized, isTrue);
    expect(result.isAutomaticallyFinalized, isTrue);
    // Lokale Wanduhr 23:59 des Eintragstags, unabhängig von der Systemzone.
    expect(
      result.finalizedLocal!.isAtSameMomentAs(DateTime(2026, 11, 22, 23, 59)),
      isTrue,
    );
    expect(result.finalizedLocal!.hour, 23);
    expect(result.finalizedLocal!.minute, 59);
    // Offset wird explizit mitgeschrieben (hier: Offset der lokalen Zeit).
    expect(result.finalizedAt, isoWithOffset(DateTime(2026, 11, 22, 23, 59)));
    // Erstellung, Änderungszeit, Befinden und Text bleiben unangetastet.
    expect(result.timestamp, entry.timestamp);
    expect(result.updatedAt, entry.updatedAt);
    expect(result.overallFeeling, 60);
    expect(result.text, 'Gestern notiert');
  });

  test('Eintrag von heute bleibt unangetastet', () {
    final entry = draft('heute', DateTime(2026, 11, 23, 7, 12), feeling: 70);
    expect(staleDraftFinalizations(<JournalEntry>[entry], today), isEmpty);
  });

  test('Eintrag aus der Zukunft bleibt unangetastet', () {
    final entry = draft('morgen', DateTime(2026, 11, 25, 18), feeling: 70);
    expect(staleDraftFinalizations(<JournalEntry>[entry], today), isEmpty);
  });

  test('bereits abgeschlossene Einträge bleiben unverändert (Idempotenz)', () {
    final manual = JournalEntry(
      id: 'manuell',
      timestamp: isoWithOffset(DateTime(2026, 11, 21, 8)),
      finalizedAt: isoWithOffset(DateTime(2026, 11, 21, 21, 14)),
      overallFeeling: 55,
    );
    expect(staleDraftFinalizations(<JournalEntry>[manual], today), isEmpty);

    // Ergebnis eines Laufs ist beim zweiten Lauf ebenfalls unverändert.
    final changes = staleDraftFinalizations(<JournalEntry>[
      draft('j1', DateTime(2026, 11, 22, 20, 10)),
    ], today);
    expect(changes, hasLength(1));
    expect(staleDraftFinalizations(changes, today), isEmpty);
  });

  test('mehrere Entwürfe am selben Tag werden alle abgeschlossen', () {
    final day = DateTime(2026, 11, 21);
    final entries = <JournalEntry>[
      draft('a', DateTime(2026, 11, 21, 7)),
      draft('b', DateTime(2026, 11, 21, 12)),
      draft('c', DateTime(2026, 11, 21, 22)),
    ];

    final changes = staleDraftFinalizations(entries, today);

    expect(changes.map((entry) => entry.id), <String>['a', 'b', 'c']);
    for (final change in changes) {
      expect(change.finalizedAutomatically, isTrue);
      expect(
        change.finalizedLocal!.isAtSameMomentAs(
          DateTime(day.year, day.month, day.day, 23, 59),
        ),
        isTrue,
      );
    }
  });

  test('Einträge ohne auswertbaren Zeitstempel bleiben unverändert', () {
    const broken = JournalEntry(id: 'kaputt', timestamp: 'keine-zeit');
    expect(staleDraftFinalizations(<JournalEntry>[broken], today), isEmpty);
  });

  test('Monats-/Jahreswechsel: 31.12. → 01.01. schließt auf den 31.12.', () {
    final newYear = DateTime(2027, 1, 1, 0, 5);
    final entry = draft(
      'silvester',
      DateTime(2026, 12, 31, 22, 30),
      feeling: 40,
    );

    final changes = staleDraftFinalizations(<JournalEntry>[entry], newYear);

    expect(changes, hasLength(1));
    expect(
      changes.single.finalizedLocal!.isAtSameMomentAs(
        DateTime(2026, 12, 31, 23, 59),
      ),
      isTrue,
    );
    expect(changes.single.finalizedAutomatically, isTrue);
  });

  test('Sommerzeit: 23:59 lokale Wanduhr gilt in Sommer- wie Winterzeit', () {
    // Zwei Daten mit (in Europe/Berlin) unterschiedlichem UTC-Offset.
    for (final at in <DateTime>[
      DateTime(2026, 7, 15, 20, 30),
      DateTime(2026, 1, 15, 20, 30),
    ]) {
      final entry = draft('j-${at.month}', at);
      final day = DateTime(at.year, at.month, at.day);
      final changes = staleDraftFinalizations(<JournalEntry>[
        entry,
      ], day.add(const Duration(days: 1)));

      expect(changes, hasLength(1), reason: '$at');
      final finalized = changes.single.finalizedLocal!;
      expect(finalized.hour, 23, reason: '$at');
      expect(finalized.minute, 59, reason: '$at');
      expect(finalized.day, at.day, reason: '$at');
      // Der geschriebene Offset gehört zum lokalen 23:59-Zeitpunkt des Tages.
      expect(
        changes.single.finalizedAt,
        isoWithOffset(DateTime(at.year, at.month, at.day, 23, 59)),
        reason: '$at',
      );
    }
  });

  test('nextLocalMidnight liefert 00:00 des Folgetags (auch über DST)', () {
    for (final from in <DateTime>[
      DateTime(2026, 11, 23, 9, 45),
      DateTime(2026, 3, 28, 23, 30), // Zeitumstellung am 29.03.
      DateTime(2026, 10, 24, 23, 30), // Zeitumstellung am 25.10.
      DateTime(2026, 12, 31, 23, 59),
    ]) {
      final next = nextLocalMidnight(from);
      expect(next.hour, 0, reason: '$from');
      expect(next.minute, 0, reason: '$from');
      expect(next.day, from.day + 1 == 32 ? 1 : from.day + 1, reason: '$from');
      // 00:00 lokal – als Wanduhr, nicht als 24-Stunden-Differenz.
      expect(
        next.isAtSameMomentAs(DateTime(next.year, next.month, next.day)),
        isTrue,
        reason: '$from',
      );
    }
  });

  test('heutige Entwürfe bleiben auch bei mehreren Einträgen Entwurf', () {
    final entries = <JournalEntry>[
      draft('h1', DateTime(2026, 11, 23, 0, 1)),
      draft('h2', DateTime(2026, 11, 23, 23, 58)),
    ];
    expect(staleDraftFinalizations(entries, today), isEmpty);
  });
}
