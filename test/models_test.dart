import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tri_log/models/models.dart';

import 'fixtures.dart';

void main() {
  group('SessionStructure', () {
    test(
      'structureSummary fasst Einfahren, Intervalle und Ausfahren zusammen',
      () {
        const structure = SessionStructure(
          warmupSeconds: 600,
          repetitions: 3,
          workSeconds: 300,
          recoverySeconds: 180,
          cooldownSeconds: 1140,
        );
        expect(
          structure.structureSummary(),
          '10 min Einfahren · 3× 5 min / 3 min Pause · 19 min Ausfahren',
        );
      },
    );

    test('structureSummary ist leer ohne Angaben', () {
      expect(const SessionStructure().structureSummary(), '');
      expect(
        const SessionStructure(repetitions: 4).structureSummary(),
        '4× Intervall',
      );
    });

    test('behält unbekannte Schlüssel in extra (verlustfrei)', () {
      final structure = SessionStructure.fromJson(<String, dynamic>{
        'warmup_seconds': 600,
        'repetitions': 3,
        'target_power_watts': 240,
        'zone': 'Z3',
      });
      expect(structure.warmupSeconds, 600);
      expect(structure.extra, <String, dynamic>{
        'target_power_watts': 240,
        'zone': 'Z3',
      });

      final json = structure.toJson();
      expect(json['target_power_watts'], 240);
      expect(json['zone'], 'Z3');
      // Bekannte, fehlende Felder werden als null serialisiert.
      expect(json.containsKey('cooldown_seconds'), isTrue);
      expect(json['cooldown_seconds'], isNull);
    });
  });

  group('JSON-Roundtrip', () {
    test('Plan/Session bleiben inkl. null-Werten erhalten', () {
      final session = Session.fromJson(sessionJson());
      final plan = Plan.fromJson(
        planJson(sessions: <Map<String, dynamic>>[session.toJson()]),
      );

      final roundtripped = Plan.fromJson(
        jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>,
      );
      expect(roundtripped.id, 'winter-2026');
      expect(roundtripped.revision, 1);
      expect(roundtripped.sessions.single.sport, Sport.swim);
      expect(roundtripped.sessions.single.optional, isFalse);
      expect(roundtripped.sessions.single.instructions, isNull);

      final raw = roundtripped.sessions.single.toJson();
      expect(raw.containsKey('instructions'), isTrue);
      expect(raw['instructions'], isNull);
      expect(raw['planned_duration_seconds'], 2700);
      expect(raw.containsKey('structure'), isTrue);
      expect(raw['structure'], isNull);
    });

    test('Activity: null bleibt null, 0 bleibt 0', () {
      final activity = Activity.fromJson(
        activityJson(elapsed: 0, distance: null, rpe: null),
      );
      expect(activity.elapsedDurationSeconds, 0);
      expect(activity.distanceMeters, isNull);
      expect(activity.rpe, isNull);

      final json =
          jsonDecode(jsonEncode(activity.toJson())) as Map<String, dynamic>;
      expect(json['elapsed_duration_seconds'], 0);
      expect(json['distance_meters'], isNull);
      expect(json['rpe'], isNull);
      expect(json['status'], 'completed');
      expect(json['started_at'], '2026-11-23T18:05:00+01:00');
    });

    test('JournalEntry: overall_feeling bleibt erhalten, null bleibt null', () {
      final entry = JournalEntry.fromJson(
        journalJson(overallFeeling: 60, text: null),
      );
      expect(entry.overallFeeling, 60);
      expect(entry.text, isNull);

      final json =
          jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>;
      expect(json['overall_feeling'], 60);
      expect(json['text'], isNull);
      // Das alte metrics-Objekt wird nicht mehr geschrieben.
      expect(json.containsKey('metrics'), isFalse);
    });

    test('JournalEntry: Grenzen 0 und 100 sowie fehlender Wert', () {
      expect(
        JournalEntry.fromJson(journalJson(overallFeeling: 0)).overallFeeling,
        0,
      );
      expect(
        JournalEntry.fromJson(journalJson(overallFeeling: 100)).overallFeeling,
        100,
      );
      final missing = JournalEntry.fromJson(
        jsonDecode(jsonEncode(journalJson(overallFeeling: null)))
            as Map<String, dynamic>,
      );
      expect(missing.overallFeeling, isNull);

      final roundtrip = JournalEntry.fromJson(
        jsonDecode(jsonEncode(missing.toJson())) as Map<String, dynamic>,
      );
      expect(roundtrip.overallFeeling, isNull);
    });

    test('AppState enthält alle fünf Top-Level-Felder', () {
      final json = sampleState().toJson();
      expect(
        json.keys,
        containsAll(<String>[
          'schema_version',
          'exported_at',
          'timezone',
          'plans',
          'activities',
          'journal',
        ]),
      );
      expect(json['schema_version'], '1.0');
      expect(json['timezone'], 'Europe/Berlin');
      expect(json['exported_at'], isNull);
    });

    test('AppState.fromJson liest fehlende Felder als leer/null', () {
      final state = AppState.fromJson(<String, dynamic>{'plans': <dynamic>[]});
      expect(state.plans, isEmpty);
      expect(state.activities, isEmpty);
      expect(state.journal, isEmpty);
      expect(state.exportedAt, isNull);
      expect(state.timezone, 'Europe/Berlin');
    });

    test('AppState.fromJson überspringt kaputte Einträge ohne Absturz', () {
      final state = AppState.fromJson(<String, dynamic>{
        'plans': <dynamic>[
          <String, dynamic>{'id': '', 'revision': 1},
          <String, dynamic>{'id': 'ok', 'revision': 0},
          planJson(),
        ],
        'activities': <dynamic>['nope'],
      });
      expect(state.plans.length, 1);
      expect(state.plans.single.id, 'winter-2026');
      expect(state.activities, isEmpty);
    });
  });

  group('AppState-Helfer', () {
    test('latestPlans nimmt die höchste Revision je plan.id', () {
      final state = AppState(
        plans: <Plan>[
          Plan(id: 'p', revision: 1, title: 'alt'),
          Plan(id: 'p', revision: 3, title: 'neu'),
          Plan(id: 'q', revision: 1, title: 'andere'),
        ],
      );
      final latest = state.latestPlans;
      expect(latest.length, 2);
      expect(state.latestPlanFor('p')?.title, 'neu');
      expect(state.latestRevisionFor('p'), 3);
      expect(state.latestRevisionFor('unbekannt'), 0);
    });

    test('sessionsOnDate sortiert swim → bike → run → strength → other', () {
      final state = AppState(
        plans: <Plan>[
          Plan(
            id: 'p',
            revision: 1,
            title: 'Mix',
            sessions: const <Session>[
              Session(
                id: 'a',
                date: '2026-11-23',
                sport: Sport.run,
                type: 'Lauf',
              ),
              Session(
                id: 'b',
                date: '2026-11-23',
                sport: Sport.strength,
                type: 'Kraft',
              ),
              Session(
                id: 'c',
                date: '2026-11-23',
                sport: Sport.swim,
                type: 'Swim',
              ),
              Session(
                id: 'd',
                date: '2026-11-23',
                sport: Sport.bike,
                type: 'Rad',
              ),
              Session(
                id: 'e',
                date: '2026-11-24',
                sport: Sport.swim,
                type: 'Anders',
              ),
            ],
          ),
        ],
      );
      final sessions = state.sessionsOnDate(DateTime(2026, 11, 23));
      expect(sessions.map((session) => session.id), <String>[
        'c',
        'd',
        'a',
        'b',
      ]);
    });
  });
}
