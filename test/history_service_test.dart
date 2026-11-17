import 'package:flutter_test/flutter_test.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/services/history_service.dart';

/// Reine Helfer des Verlaufs: Tages-Ableitung, Zähler, Minuten, Sortierung,
/// „unbekannt“-Kennzeichnung.
void main() {
  final today = DateTime(2026, 11, 23, 9);

  Session session({
    required String id,
    required String date,
    Sport sport = Sport.swim,
    String type = 'Technik',
    int? planned = 2700,
    bool optional = false,
  }) => Session(
    id: id,
    date: date,
    sport: sport,
    type: type,
    optional: optional,
    plannedDurationSeconds: planned,
  );

  Activity activity({
    required String id,
    String? forSession,
    String startedAt = '2026-11-23T18:05:00+01:00',
    ActivityStatus status = ActivityStatus.completed,
    int? elapsed,
    int? moving,
  }) => Activity(
    id: id,
    plannedSessionId: forSession,
    startedAt: startedAt,
    status: status,
    elapsedDurationSeconds: elapsed,
    movingDurationSeconds: moving,
  );

  AppState state({
    List<Plan>? plans,
    List<Activity>? activities,
    List<JournalEntry>? journal,
  }) => AppState(
    plans: plans ?? const <Plan>[],
    activities: activities ?? const <Activity>[],
    journal: journal ?? const <JournalEntry>[],
  );

  List<HistoryDayRecord> daysFor(
    AppState appState, {
    HistoryRange range = HistoryRange.last30Days,
  }) => buildHistoryDays(state: appState, range: range, today: today);

  group('Zeitraum', () {
    test('Zeitscheibe um heute: ±7, ±30 und Standard 30', () {
      final week = HistoryRange.last7Days.window(today: today);
      expect(week.from, DateTime(2026, 11, 16));
      expect(week.to, DateTime(2026, 11, 30));
      // Beide Grenzen inklusiv → 15 Kalendertage.
      expect(week.dayCount, 15);
      expect(week.contains(DateTime(2026, 11, 16)), isTrue);
      expect(week.contains(DateTime(2026, 11, 30)), isTrue);
      expect(week.contains(DateTime(2026, 11, 15)), isFalse);
      expect(week.contains(DateTime(2026, 12, 1)), isFalse);

      final month = HistoryRange.last30Days.window(today: today);
      expect(month.from, DateTime(2026, 10, 24));
      expect(month.to, DateTime(2026, 12, 23));
      expect(month.dayCount, 61);

      // Standard im Verlauf bleibt „30 Tage“.
      expect(HistoryRange.last7Days.labelDe, '7 Tage');
      expect(HistoryRange.last30Days.labelDe, '30 Tage');
      expect(HistoryRange.all.labelDe, 'Alles');
    });

    test('„Alles“ reicht mindestens ±7 und sonst über den Inhalt', () {
      final empty = HistoryRange.all.window(today: today);
      expect(empty.from, DateTime(2026, 11, 16));
      expect(empty.to, DateTime(2026, 11, 30));

      final withContent = HistoryRange.all.window(
        today: today,
        contentDates: <DateTime>[
          DateTime(2026, 9, 1, 18, 30),
          DateTime(2027, 1, 15),
        ],
      );
      expect(withContent.from, DateTime(2026, 9, 1));
      expect(withContent.to, DateTime(2027, 1, 15));

      // Inhalt INNERHALB von ±7 verschiebt die Grenzen nicht.
      final inner = HistoryRange.all.window(
        today: today,
        contentDates: <DateTime>[DateTime(2026, 11, 20)],
      );
      expect(inner.from, DateTime(2026, 11, 16));
      expect(inner.to, DateTime(2026, 11, 30));
    });

    test('Tages-Filter: alte Sitzung nur bei „Alles“', () {
      final old = dateOffset(today, -60);
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 'alt', date: old),
              session(id: 'neu', date: '2026-11-22'),
            ],
          ),
        ],
      );

      expect(daysFor(appState).map((d) => d.dateIso), <String>[
        '2026-11-22',
        '2026-11-23',
      ]);
      expect(
        daysFor(appState, range: HistoryRange.all).map((d) => d.dateIso),
        <String>[old, '2026-11-22', '2026-11-23'],
      );
      expect(daysFor(appState, range: HistoryRange.last7Days).length, 2);
    });

    test('nur die neueste Plan-Revision zählt', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'alt',
            sessions: <Session>[session(id: 's1', date: '2026-11-22')],
          ),
          Plan(
            id: 'p1',
            revision: 2,
            title: 'neu',
            sessions: <Session>[
              session(id: 's1', date: '2026-11-22'),
              session(id: 's2', date: '2026-11-21', sport: Sport.run),
            ],
          ),
        ],
      );
      final days = daysFor(appState);
      expect(summarizeHistory(days).total, 2);
    });
  });

  group('RangeSummary', () {
    test('zählt erledigt, teilweise, ausgelassen und offen', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 'c', date: '2026-11-23'),
              session(id: 'p', date: '2026-11-22'),
              session(id: 's', date: '2026-11-21'),
              session(id: 'u', date: '2026-11-20'),
            ],
          ),
        ],
        activities: <Activity>[
          activity(id: 'a1', forSession: 'c', elapsed: 2700),
          activity(
            id: 'a2',
            forSession: 'p',
            status: ActivityStatus.partial,
            elapsed: 1800,
          ),
          activity(id: 'a3', forSession: 's', status: ActivityStatus.skipped),
        ],
      );

      final summary = summarizeHistory(daysFor(appState));
      expect(summary.completed, 1);
      expect(summary.partial, 1);
      expect(summary.skipped, 1);
      expect(summary.unknown, 1);
      expect(summary.total, 4);
      expect(
        summary.countsLabelDe,
        '1 erledigt · 1 teilweise · 1 ausgelassen · 1 offen',
      );
    });

    test('ohne Sitzungen sind alle Zähler 0 und Minuten unbekannt', () {
      final summary = summarizeHistory(daysFor(state()));
      expect(summary.total, 0);
      expect(summary.actualSeconds, isNull);
      expect(summary.plannedSeconds, isNull);
      expect(summary.minutesLabelDe, 'Ist: – / Plan: –');
    });

    test('nur ungeplante Einheiten erzeugen keinen Sitzungs-Zähler', () {
      final appState = state(
        activities: <Activity>[
          activity(id: 'frei', startedAt: '2026-11-22T07:30:00+01:00'),
        ],
      );
      final days = daysFor(appState);
      // 11-22 (ungeplant) + heutiger Anker-Tag ohne Inhalt.
      expect(days.map((d) => d.dateIso), <String>['2026-11-22', '2026-11-23']);
      expect(days.first.unplanned, hasLength(1));
      expect(days.last.isToday, isTrue);
      expect(days.last.hasContent, isFalse);
      expect(summarizeHistory(days).total, 0);
      // Geplante Minuten fehlen weiterhin (nicht 0).
      expect(summarizeHistory(days).plannedSeconds, isNull);
    });

    test('mehrere Sitzungen pro Tag werden einzeln gezählt', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 'bike', date: '2026-11-23', sport: Sport.bike),
              session(id: 'swim', date: '2026-11-23', sport: Sport.swim),
            ],
          ),
        ],
        activities: <Activity>[
          activity(id: 'a1', forSession: 'swim', elapsed: 2700),
        ],
      );
      final days = daysFor(appState);
      expect(days, hasLength(1));
      expect(days.single.sessions, hasLength(2));
      // Sport-Reihenfolge: Schwimmen vor Rad.
      expect(days.single.sessions.map((s) => s.session.id), <String>[
        'swim',
        'bike',
      ]);
      final summary = summarizeHistory(days);
      expect(summary.completed, 1);
      expect(summary.unknown, 1);
    });

    test('Minuten-Summen nur aus vorhandenen Werten', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 's1', date: '2026-11-23', planned: 2700),
              // Ohne Plan-Dauer: zählt nicht in die Plan-Summe.
              session(id: 's2', date: '2026-11-22', planned: null),
            ],
          ),
        ],
        activities: <Activity>[
          activity(id: 'a1', forSession: 's1', elapsed: 1800),
          // Aktivität ohne Dauer: zählt nicht in die Ist-Summe.
          activity(id: 'a2', forSession: 's2'),
        ],
      );

      final summary = summarizeHistory(daysFor(appState));
      expect(summary.plannedSeconds, 2700);
      expect(summary.actualSeconds, 1800);
      expect(summary.minutesLabelDe, 'Ist: 30 min / Plan: 45 min');
    });

    test('„ausgelassen“ zählt nicht in die Ist-Minuten', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 's1', date: '2026-11-23', planned: 2700),
            ],
          ),
        ],
        activities: <Activity>[
          activity(
            id: 'a1',
            forSession: 's1',
            status: ActivityStatus.skipped,
            elapsed: 600,
          ),
        ],
      );
      final summary = summarizeHistory(daysFor(appState));
      expect(summary.skipped, 1);
      expect(summary.actualSeconds, isNull);
      expect(summary.plannedSeconds, 2700);
    });
  });

  group('Tage mit Inhalt', () {
    test(
      'Sitzung mit Aktivität an einem anderen Tag bleibt am Sitzungstag',
      () {
        final appState = state(
          plans: <Plan>[
            Plan(
              id: 'p1',
              revision: 1,
              title: 'Plan',
              sessions: <Session>[session(id: 's1', date: '2026-11-20')],
            ),
          ],
          activities: <Activity>[
            activity(
              id: 'a1',
              forSession: 's1',
              startedAt: '2026-11-21T08:00:00+01:00',
              elapsed: 2400,
            ),
          ],
        );

        final days = daysFor(appState);
        expect(days.map((d) => d.dateIso), <String>[
          '2026-11-20',
          '2026-11-23',
        ]);
        expect(days.first.sessions.single.activity?.id, 'a1');
        // Die verknüpfte Aktivität taucht nicht zusätzlich als ungeplant auf.
        expect(days.first.unplanned, isEmpty);
        expect(summarizeHistory(days).completed, 1);
      },
    );

    test('Tag nur mit Tagebucheintrag erscheint, Tage aufsteigend', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[session(id: 's1', date: '2026-11-20')],
          ),
        ],
        journal: <JournalEntry>[
          const JournalEntry(
            id: 'j1',
            timestamp: '2026-11-22T21:00:00+01:00',
            overallFeeling: 70,
            text: 'Müde Beine',
          ),
          const JournalEntry(
            id: 'j2',
            timestamp: '2026-11-22T07:00:00+01:00',
            overallFeeling: 85,
          ),
        ],
      );

      final days = daysFor(appState);
      expect(days.map((d) => d.dateIso), <String>[
        '2026-11-20',
        '2026-11-22',
        '2026-11-23',
      ]);
      // Innerhalb des Tages aufsteigend, Tagesbefinden = letzter Eintrag.
      expect(days[1].journal.map((e) => e.id), <String>['j2', 'j1']);
      expect(days[1].lastFeeling, 70);
      expect(days[1].hasJournalText, isTrue);
      // Beim geplanten Tag ohne Eintrag ist das Befinden unbekannt.
      expect(days.first.lastFeeling, isNull);
      expect(days.first.hasJournalText, isFalse);
    });

    test('unbekannt ≠ ausgelassen', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[session(id: 's1', date: '2026-11-23')],
          ),
        ],
      );
      final record = daysFor(appState).single.sessions.single;
      expect(record.isUnknown, isTrue);
      expect(record.status, isNull);
      expect(record.statusLabelDe, kNoRecordingLabelDe);
      expect(record.statusLabelDe, 'keine Aufzeichnung');
      expect(record.statusLabelDe, isNot('Ausgelassen'));
    });

    test('Ist- und Plan-Abweichung je Sitzung', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 's1', date: '2026-11-23', planned: 3000),
            ],
          ),
        ],
        activities: <Activity>[
          activity(id: 'a1', forSession: 's1', elapsed: 2100),
        ],
      );
      final record = daysFor(appState).single.sessions.single;
      expect(record.plannedSeconds, 3000);
      expect(record.actualSeconds, 2100);
      expect(record.deltaLabelDe, '15 min kürzer');
      expect(record.statusLabelDe, 'Erledigt');
    });

    test('Bewegungszeit greift, wenn keine Gesamtzeit erfasst ist', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 's1', date: '2026-11-23', planned: 2700),
            ],
          ),
        ],
        activities: <Activity>[
          activity(id: 'a1', forSession: 's1', moving: 1800),
        ],
      );
      final summary = summarizeHistory(daysFor(appState));
      expect(summary.actualSeconds, 1800);
    });
  });

  group('Zeitscheibe — Anker heute & Zukunft', () {
    test('heutiger Tag ist auch ohne Inhalt enthalten und markiert', () {
      final days = daysFor(state(), range: HistoryRange.last7Days);
      expect(days, hasLength(1));
      final today0 = days.single;
      expect(today0.dateIso, '2026-11-23');
      expect(today0.isToday, isTrue);
      expect(today0.isFuture, isFalse);
      expect(today0.hasContent, isFalse);
      expect(today0.sessions, isEmpty);
    });

    test('Zukunft wird markiert, Vergangenheit nicht', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 'gestern', date: '2026-11-22'),
              session(id: 'morgen', date: '2026-11-24'),
            ],
          ),
        ],
      );
      final days = daysFor(appState);
      expect(days.map((d) => d.dateIso), <String>[
        '2026-11-22',
        '2026-11-23',
        '2026-11-24',
      ]);
      expect(days[0].isFuture, isFalse);
      expect(days[1].isToday, isTrue);
      expect(days[2].isFuture, isTrue);
      // Aufsteigend: Vergangenheit oben, Zukunft unten.
      for (var index = 1; index < days.length; index++) {
        expect(
          days[index].dateIso.compareTo(days[index - 1].dateIso),
          greaterThan(0),
        );
      }
    });

    test('Tage außerhalb der Zeitscheibe sind ausgeschlossen', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              // heute −8 / heute +8 liegen außerhalb von ±7.
              session(id: 'zu-alt', date: dateOffset(today, -8)),
              session(id: 'rand-vor', date: dateOffset(today, -7)),
              session(id: 'rand-nach', date: dateOffset(today, 7)),
              session(id: 'zu-neu', date: dateOffset(today, 8)),
            ],
          ),
        ],
      );
      final days = daysFor(appState, range: HistoryRange.last7Days);
      expect(days.map((d) => d.dateIso), <String>[
        dateOffset(today, -7),
        '2026-11-23',
        dateOffset(today, 7),
      ]);
    });

    test('Statuszähler und Plan-Minuten ignorieren die Zukunft', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 'heute', date: '2026-11-23', planned: 2700),
              session(
                id: 'gestern',
                date: '2026-11-22',
                sport: Sport.run,
                planned: 1800,
              ),
              session(id: 'zukunft', date: '2026-11-26', planned: 3600),
            ],
          ),
        ],
        activities: <Activity>[
          activity(id: 'a1', forSession: 'gestern', elapsed: 1800),
        ],
      );

      final summary = summarizeHistory(daysFor(appState));
      expect(summary.completed, 1);
      expect(summary.unknown, 1);
      // Zukunft ist weder „offen“ noch „ausgelassen“.
      expect(summary.skipped, 0);
      expect(summary.partial, 0);
      expect(summary.plannedInFuture, 1);
      expect(summary.total, 2);
      // Plan-Minuten nur aus Tagen ≤ heute (2700 + 1800, ohne 3600).
      expect(summary.plannedSeconds, 4500);
      expect(summary.actualSeconds, 1800);
      expect(
        summary.countsLabelDe,
        '1 erledigt · 0 teilweise · 0 ausgelassen · 1 offen · '
        '1 geplant (Zukunft)',
      );
      expect(summary.minutesLabelDe, 'Ist: 30 min / Plan: 75 min');
    });

    test('nur Zukunft: keine Statuszähler, keine Plan-Minuten', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 'z1', date: '2026-11-26', planned: 3600),
              session(id: 'z2', date: '2026-11-28', planned: 2400),
            ],
          ),
        ],
      );
      final summary = summarizeHistory(daysFor(appState));
      expect(summary.total, 0);
      expect(summary.plannedInFuture, 2);
      expect(summary.plannedSeconds, isNull);
      expect(summary.actualSeconds, isNull);
      expect(summary.minutesLabelDe, 'Ist: – / Plan: –');
      expect(
        summary.countsLabelDe,
        '0 erledigt · 0 teilweise · 0 ausgelassen · 0 offen · '
        '2 geplant (Zukunft)',
      );
    });
  });

  group('Kommende Tage (Heute-Screen)', () {
    test('nur die nächsten 7 Tage, nur Tage mit Sitzung', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 'heute', date: '2026-11-23'),
              session(id: 'morgen', date: '2026-11-24', sport: Sport.bike),
              session(id: 'plus3-swim', date: '2026-11-26', sport: Sport.swim),
              session(id: 'plus3-run', date: '2026-11-26', sport: Sport.run),
              session(id: 'plus7', date: '2026-11-30', sport: Sport.strength),
              session(id: 'plus8', date: '2026-12-01', sport: Sport.other),
            ],
          ),
        ],
      );

      final upcoming = buildUpcomingDays(state: appState, today: today);
      expect(upcoming.map((d) => d.dateIso), <String>[
        '2026-11-24',
        '2026-11-26',
        '2026-11-30',
      ]);
      // Tage ohne Sitzung (25., 27.–29.) fehlen komplett.
      expect(upcoming.map((d) => d.dateIso), isNot(contains('2026-11-25')));
      // Innerhalb eines Tages nach Sport sortiert.
      expect(upcoming[1].sessions.map((r) => r.session.id), <String>[
        'plus3-swim',
        'plus3-run',
      ]);
      expect(upcoming.every((d) => d.isFuture), isTrue);
    });

    test('ohne geplante Sitzungen ist die Liste leer', () {
      expect(buildUpcomingDays(state: state(), today: today), isEmpty);
      final onlyPast = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[session(id: 'alt', date: '2026-11-20')],
          ),
        ],
      );
      expect(buildUpcomingDays(state: onlyPast, today: today), isEmpty);
    });
  });

  group('Zeilen & Zentrierung', () {
    test('Index des heutigen Tageskopfs in der flachen Liste', () {
      final appState = state(
        plans: <Plan>[
          Plan(
            id: 'p1',
            revision: 1,
            title: 'Plan',
            sessions: <Session>[
              session(id: 'alt', date: '2026-11-20'),
              session(id: 'heute', date: '2026-11-23'),
              session(id: 'morgen', date: '2026-11-24'),
            ],
          ),
        ],
        activities: <Activity>[
          activity(id: 'frei', startedAt: '2026-11-22T07:30:00+01:00'),
        ],
      );
      final days = daysFor(appState);
      final rows = buildHistoryRows(days);
      // Zeilen: 20. Kopf, 20. Sitzung, 22. Kopf, 22. ungeplant, 23. Kopf, …
      expect(rows[0], isA<HistoryDayRow>());
      expect(rows[1], isA<HistorySessionRow>());
      expect(rows[2], isA<HistoryDayRow>());
      expect(rows[3], isA<HistoryUnplannedRow>());
      expect((rows[4] as HistoryDayRow).day.isToday, isTrue);
      expect(indexOfTodayRow(rows), 4);
      expect(indexOfTodayRow(const <HistoryRow>[]), -1);
    });

    test('ohne heutigen Tag liefert der Index -1', () {
      final rows = buildHistoryRows(<HistoryDayRecord>[
        HistoryDayRecord(dateIso: '2026-11-20', date: DateTime(2026, 11, 20)),
      ]);
      expect(indexOfTodayRow(rows), -1);
    });
  });
}

/// `YYYY-MM-DD` für einen Tag relativ zu [date] (ohne Zeitzonen-Fallen).
String dateOffset(DateTime date, int days) {
  final shifted = DateTime(date.year, date.month, date.day + days);
  final month = shifted.month.toString().padLeft(2, '0');
  final day = shifted.day.toString().padLeft(2, '0');
  return '${shifted.year}-$month-$day';
}
