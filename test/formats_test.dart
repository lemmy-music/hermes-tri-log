import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tri_log/utils/formats.dart';
import 'package:tri_log/utils/ids.dart';

void main() {
  group('Datum', () {
    test('formatiert deutsch mit Wochentag', () {
      expect(formatDateGerman(DateTime(2026, 11, 16)), 'Mo, 16.11.2026');
      expect(formatDateNumeric(DateTime(2026, 1, 5)), '05.01.2026');
      expect(formatDateIso(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('parst nur echte YYYY-MM-DD-Daten', () {
      expect(parseIsoDate('2026-11-16'), DateTime(2026, 11, 16));
      expect(parseIsoDate('2026-02-31'), isNull);
      expect(parseIsoDate('16.11.2026'), isNull);
      expect(parseIsoDate('2026-11-16T10:00:00Z'), isNull);
      expect(parseIsoDate(null), isNull);
    });

    test('berechnet ISO-Kalenderwoche und Wochenstart', () {
      expect(startOfWeek(DateTime(2026, 11, 19)), DateTime(2026, 11, 16));
      expect(isoWeekNumber(DateTime(2026, 11, 16)), 47);
      expect(isoWeekNumber(DateTime(2026, 11, 23)), 48);
      // Jahreswechsel: 2027-01-01 gehört zur KW 53 von 2026.
      expect(isoWeekNumber(DateTime(2027, 1, 1)), 53);
    });
  });

  group('Dauer und Distanz', () {
    test('Minuten ganzzahlig, sonst eine Dezimale', () {
      expect(formatMinutes(2700), '45');
      expect(formatMinutes(0), '0');
      expect(formatMinutes(5850), '97,5');
      expect(formatMinutes(90), '1,5');
      expect(formatMinutes(null), '–');
      expect(formatMinutesWithUnit(2820), '47 min');
      expect(formatMinutesWithUnit(null), '–');
    });

    test('Kilometer mit deutschem Komma', () {
      expect(formatDistanceKm(1800), '1,8 km');
      expect(formatDistanceKm(10000), '10 km');
      expect(formatDistanceKm(0), '0 km');
      expect(formatDistanceKm(null), '–');
    });

    test('Prozentwerte', () {
      expect(formatPercent(70), '70 %');
      expect(formatPercent(null), '–');
    });
  });

  group('ISO-Zeitstempel', () {
    test('enthält einen expliziten Offset und bleibt parsebar', () {
      final formatted = isoWithOffset(DateTime(2026, 11, 16, 20, 5, 6));
      expect(
        RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$',
        ).hasMatch(formatted),
        isTrue,
      );
      expect(
        DateTime.parse(formatted).toUtc(),
        DateTime(2026, 11, 16, 20, 5, 6).toUtc(),
      );
    });
  });

  group('Ids', () {
    test('Format <prefix>-<millis>-<4 Zeichen>', () {
      final generator = IdGenerator(
        clock: () => DateTime.fromMillisecondsSinceEpoch(1763323200000),
        random: _FixedRandom(),
      );
      final id = generator.nextActivity();
      expect(id, matches(RegExp(r'^act-1763323200000-[a-z0-9]{4}$')));
      expect(generator.nextJournalEntry(), startsWith('jnl-1763323200000-'));
    });
  });
}

class _FixedRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}
