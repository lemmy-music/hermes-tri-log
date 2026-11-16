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
    test('7 Tage beginnt 6 Tage vor heute, 30 Tage 29 Tage davor', () {
      expect(HistoryRange.last7Days.startDate(today), DateTime(2026, 11, 17));
      expect(HistoryRange.last30Days.startDate(today), DateTime(2026, 10, 25));
      expect(HistoryRange.all.startDate(today), isNull);
      expect(HistoryRange.all.endDate(today), isNull);
      expect(HistoryRange.last7Days.labelDe, '7 Tage');
      expect(HistoryRange.last30Days.labelDe, '30 Tage');
      expect(HistoryRange.all.labelDe, 'Alles');
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

      expect(daysFor(appState).map((d) => d.dateIso), <String>['2026-11-22']);
      expect(
        daysFor(appState, range: HistoryRange.all).map((d) => d.dateIso),
        <String>['2026-11-22', old],
      );
      expect(daysFor(appState, range: HistoryRange.last7Days).length, 1);
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
      expect(days, hasLength(1));
      expect(days.single.unplanned, hasLength(1));
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
        expect(days.map((d) => d.dateIso), <String>['2026-11-20']);
        expect(days.single.sessions.single.activity?.id, 'a1');
        // Die verknüpfte Aktivität taucht nicht zusätzlich als ungeplant auf.
        expect(days.single.unplanned, isEmpty);
        expect(summarizeHistory(days).completed, 1);
      },
    );

    test('Tag nur mit Tagebucheintrag erscheint, neueste Tage zuerst', () {
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
      expect(days.map((d) => d.dateIso), <String>['2026-11-22', '2026-11-20']);
      // Innerhalb des Tages aufsteigend, Tagesbefinden = letzter Eintrag.
      expect(days.first.journal.map((e) => e.id), <String>['j2', 'j1']);
      expect(days.first.lastFeeling, 70);
      expect(days.first.hasJournalText, isTrue);
      // Beim geplanten Tag ohne Eintrag ist das Befinden unbekannt.
      expect(days.last.lastFeeling, isNull);
      expect(days.last.hasJournalText, isFalse);
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
}

/// `YYYY-MM-DD` für einen Tag relativ zu [date] (ohne Zeitzonen-Fallen).
String dateOffset(DateTime date, int days) {
  final shifted = DateTime(date.year, date.month, date.day + days);
  final month = shifted.month.toString().padLeft(2, '0');
  final day = shifted.day.toString().padLeft(2, '0');
  return '${shifted.year}-$month-$day';
}
