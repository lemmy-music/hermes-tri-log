import 'package:flutter_test/flutter_test.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/services/reminder_service.dart';
import 'package:tri_log/services/settings_service.dart';

/// Ein Kalendertag, der in allen Tests als „heute“ dient.
final DateTime _now = DateTime(2026, 11, 23, 4, 30);

AppState _state({
  List<Session> sessions = const <Session>[],
  List<Activity> activities = const <Activity>[],
  List<JournalEntry> journal = const <JournalEntry>[],
}) => AppState(
  plans: <Plan>[
    Plan(id: 'p1', revision: 1, title: 'Winter', sessions: sessions),
  ],
  activities: activities,
  journal: journal,
);

Session _session({
  String id = 's1',
  String date = '2026-11-23',
  Sport sport = Sport.bike,
  String type = 'Schwellen-Intervalle',
  int? seconds = 3600,
}) => Session(
  id: id,
  date: date,
  sport: sport,
  type: type,
  plannedDurationSeconds: seconds,
);

Activity _activity(
  String sessionId, {
  ActivityStatus status = ActivityStatus.completed,
}) => Activity(
  id: 'a-$sessionId',
  plannedSessionId: sessionId,
  startedAt: '2026-11-23T18:00:00+00:00',
  status: status,
);

JournalEntry _journal({
  String id = 'j1',
  String timestamp = '2026-11-23T12:00:00+00:00',
  String? finalizedAt,
}) => JournalEntry(id: id, timestamp: timestamp, finalizedAt: finalizedAt);

void main() {
  group('Morgen-Übersicht', () {
    test('plant 05:00 mit Titel und Einheiten-Zeile', () {
      final reminders = planReminders(
        state: _state(sessions: <Session>[_session()]),
        now: _now,
        settings: ReminderSettings.defaults,
      );

      final morning = reminders.singleWhere((r) => r.isMorning);
      expect(morning.kind, kReminderKindMorning);
      expect(morning.title, 'Tri-Log');
      expect(morning.dueAt, DateTime(2026, 11, 23, 5));
      expect(morning.body, 'Rad · Schwellen-Intervalle (60 min)');
    });

    test('zwei Einheiten werden mit „ · “ verbunden', () {
      final reminders = planReminders(
        state: _state(
          sessions: <Session>[
            _session(),
            _session(
              id: 's2',
              sport: Sport.strength,
              type: 'Kraft',
              seconds: 2400,
            ),
          ],
        ),
        now: _now,
        settings: ReminderSettings.defaults,
      );

      expect(
        reminders.singleWhere((r) => r.isMorning).body,
        'Rad · Schwellen-Intervalle (60 min) · Kraft (40 min)',
      );
    });

    test('vier Einheiten: drei Zeilen plus „… und 1 weitere“', () {
      final reminders = planReminders(
        state: _state(
          sessions: <Session>[
            _session(
              id: 's1',
              sport: Sport.swim,
              type: 'Technik',
              seconds: 2700,
            ),
            _session(id: 's2', sport: Sport.bike, type: 'GA1', seconds: 5400),
            _session(
              id: 's3',
              sport: Sport.run,
              type: 'Intervalle',
              seconds: 2400,
            ),
            _session(
              id: 's4',
              sport: Sport.strength,
              type: 'Kraft',
              seconds: 1800,
            ),
          ],
        ),
        now: _now,
        settings: ReminderSettings.defaults,
      );

      final body = reminders.singleWhere((r) => r.isMorning).body;
      expect(body, startsWith('Schwimmen · Technik (45 min) · '));
      expect(body, contains('… und 1 weitere'));
      expect(body, isNot(contains('Kraft')));
    });

    test('kein Reminder, wenn heute nichts geplant ist', () {
      final reminders = planReminders(
        state: _state(sessions: <Session>[_session(date: '2026-11-24')]),
        now: _now,
        settings: ReminderSettings.defaults,
      );

      expect(reminders.where((r) => r.isMorning), isEmpty);
    });

    test('alle Einheiten erledigt → knapper „Alles erfasst“-Body', () {
      final reminders = planReminders(
        state: _state(
          sessions: <Session>[
            _session(),
            _session(id: 's2'),
          ],
          activities: <Activity>[_activity('s1'), _activity('s2')],
        ),
        now: _now,
        settings: ReminderSettings.defaults,
      );

      expect(
        reminders.singleWhere((r) => r.isMorning).body,
        kMorningAllDoneBody,
      );
    });

    test('teilweise erfasst zählt ebenfalls als erfasst', () {
      final reminders = planReminders(
        state: _state(
          sessions: <Session>[_session()],
          activities: <Activity>[
            _activity('s1', status: ActivityStatus.partial),
          ],
        ),
        now: _now,
        settings: ReminderSettings.defaults,
      );

      expect(
        reminders.singleWhere((r) => r.isMorning).body,
        kMorningAllDoneBody,
      );
    });

    test('ausgelassen zählt nicht als erfasst – Einheit bleibt sichtbar', () {
      final reminders = planReminders(
        state: _state(
          sessions: <Session>[_session()],
          activities: <Activity>[
            _activity('s1', status: ActivityStatus.skipped),
          ],
        ),
        now: _now,
        settings: ReminderSettings.defaults,
      );

      expect(
        reminders.singleWhere((r) => r.isMorning).body,
        contains('Rad · Schwellen-Intervalle'),
      );
    });

    test('abgeschaltete Morgen-Übersicht erzeugt keinen Reminder', () {
      final reminders = planReminders(
        state: _state(sessions: <Session>[_session()]),
        now: _now,
        settings: ReminderSettings.defaults.copyWith(morningEnabled: false),
      );

      expect(reminders.where((r) => r.isMorning), isEmpty);
    });

    test('ungültige Uhrzeit erzeugt keinen Morgen-Reminder', () {
      final reminders = planReminders(
        state: _state(sessions: <Session>[_session()]),
        now: _now,
        settings: const ReminderSettings(morningHour: 25, morningMinute: 5),
      );

      expect(reminders.where((r) => r.isMorning), isEmpty);
    });
  });

  group('Abend-Erinnerung', () {
    test(
      'fehlende Tagesnotiz → „Tagesnotiz füllen und abschließen“ um 20:00',
      () {
        final reminders = planReminders(
          state: _state(),
          now: _now,
          settings: ReminderSettings.defaults,
        );

        final evening = reminders.single;
        expect(evening.kind, kReminderKindEvening);
        expect(evening.dueAt, DateTime(2026, 11, 23, 20));
        expect(evening.body, kEveningMissingBody);
        expect(evening.title, 'Tri-Log');
      },
    );

    test('Entwurf → „Tagesnotiz ist noch Entwurf“', () {
      final reminders = planReminders(
        state: _state(journal: <JournalEntry>[_journal()]),
        now: _now,
        settings: ReminderSettings.defaults,
      );

      expect(reminders.single.body, kEveningDraftBody);
    });

    test('abgeschlossene Tagesnotiz erzeugt keinen Abend-Reminder', () {
      final reminders = planReminders(
        state: _state(
          journal: <JournalEntry>[
            _journal(finalizedAt: '2026-11-23T21:00:00+00:00'),
          ],
        ),
        now: _now,
        settings: ReminderSettings.defaults,
      );

      expect(reminders.where((r) => r.isEvening), isEmpty);
    });

    test('abgeschaltete Tagesnotiz-Erinnerung erzeugt keinen Reminder', () {
      final reminders = planReminders(
        state: _state(),
        now: _now,
        settings: ReminderSettings.defaults.copyWith(eveningEnabled: false),
      );

      expect(reminders.where((r) => r.isEvening), isEmpty);
    });

    test('Tagesnotiz von gestern zählt nicht für heute', () {
      final reminders = planReminders(
        state: _state(
          journal: <JournalEntry>[
            _journal(timestamp: '2026-11-22T21:00:00+00:00'),
          ],
        ),
        now: _now,
        settings: ReminderSettings.defaults,
      );

      expect(reminders.single.body, kEveningMissingBody);
    });
  });

  group('Gesamtplanung', () {
    test('beide Erinnerungen, aufsteigend nach dueAt, Datum von now', () {
      final now = DateTime(2026, 11, 23, 4, 30);
      final reminders = planReminders(
        state: _state(sessions: <Session>[_session()]),
        now: now,
        settings: ReminderSettings.defaults.copyWith(
          morningHour: 6,
          morningMinute: 30,
          eveningHour: 21,
          eveningMinute: 15,
        ),
      );

      expect(reminders, hasLength(2));
      expect(reminders.first.kind, kReminderKindMorning);
      expect(reminders.first.dueAt, DateTime(2026, 11, 23, 6, 30));
      expect(reminders.last.kind, kReminderKindEvening);
      expect(reminders.last.dueAt, DateTime(2026, 11, 23, 21, 15));
      for (final reminder in reminders) {
        expect(reminder.dueAt.year, now.year);
        expect(reminder.dueAt.month, now.month);
        expect(reminder.dueAt.day, now.day);
      }
    });

    test('beide abgeschaltet → leere Liste', () {
      final reminders = planReminders(
        state: _state(sessions: <Session>[_session()]),
        now: _now,
        settings: ReminderSettings.defaults.copyWith(
          morningEnabled: false,
          eveningEnabled: false,
        ),
      );

      expect(reminders, isEmpty);
    });

    test('Uhrzeit 00:00 ist gültig (nicht „leer“)', () {
      final reminders = planReminders(
        state: _state(),
        now: _now,
        settings: const ReminderSettings(eveningHour: 0, eveningMinute: 0),
      );

      expect(reminders.single.dueAt, DateTime(2026, 11, 23));
    });
  });

  group('describeSessionLine / describeMorningBody', () {
    test('ohne Dauer und ohne Typ bleibt nur das Sport-Label', () {
      expect(describeSessionLine(_session(type: '  ', seconds: null)), 'Rad');
    });

    test('leere Sitzungsliste → leerer Body', () {
      expect(describeMorningBody(const <Session>[]), '');
    });

    test('mehr als drei Einheiten ohne Erfassung: „… und 2 weitere“', () {
      final sessions = <Session>[
        for (var i = 0; i < 5; i++) _session(id: 's$i', seconds: 1800),
      ];

      expect(describeMorningBody(sessions), endsWith('… und 2 weitere'));
    });

    test('latestJournalEntryOn nimmt den neuesten Eintrag des Tages', () {
      final state = _state(
        journal: <JournalEntry>[
          _journal(id: 'alt', timestamp: '2026-11-23T08:00:00+00:00'),
          _journal(id: 'neu', timestamp: '2026-11-23T19:00:00+00:00'),
        ],
      );

      expect(latestJournalEntryOn(state, _now)?.id, 'neu');
      expect(latestJournalEntryOn(state, DateTime(2026, 11, 24)), isNull);
    });
  });
}
