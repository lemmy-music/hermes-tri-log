import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/services/import_service.dart';

import 'fixtures.dart';

void main() {
  const service = ImportService();
  final now = DateTime(2026, 11, 16, 12);

  test('docs/example-plan.json parst fehlerfrei', () {
    final text = File('docs/example-plan.json').readAsStringSync();
    final result = service.parse(text, now: now);

    expect(result.errors, isEmpty);
    expect(result.warnings, isEmpty);
    expect(result.plans.single.id, 'winter-2026');
    expect(result.plans.single.sessions.length, 6);
    expect(
      result.plans.single.sessions.map((session) => session.sport.wireName),
      containsAll(<String>['swim', 'bike', 'run', 'strength']),
    );
    expect(
      result.plans.single.sessions.where((session) => session.optional).length,
      1,
    );
  });

  test('Plan-only-Datei ohne activities/journal ist gültig', () {
    final result = service.parse(documentJson(), now: now);
    expect(result.errors, isEmpty);
    expect(result.activities, isEmpty);
    expect(result.journal, isEmpty);
    expect(result.plans.length, 1);
  });

  test('kaputtes JSON ist ein harter Fehler', () {
    final result = service.parse('{"plans": [', now: now);
    expect(result.hasErrors, isTrue);
    expect(result.errors.single, contains('Ungültiges JSON'));
    expect(result.plans, isEmpty);
  });

  test('fehlende plan.id ist ein harter Fehler', () {
    final result = service.parse(
      documentJson(plans: <Map<String, dynamic>>[planJson(id: '')]),
      now: now,
    );
    expect(result.hasErrors, isTrue);
    expect(result.errors.join(' '), contains('id fehlt oder ist leer'));
  });

  test('revision < 1 ist ein harter Fehler', () {
    final result = service.parse(
      documentJson(plans: <Map<String, dynamic>>[planJson(revision: 0)]),
      now: now,
    );
    expect(result.hasErrors, isTrue);
    expect(result.errors.join(' '), contains('revision muss ≥ 1 sein'));
  });

  test('unbekannter sport-Wert in einer Sitzung ist ein harter Fehler', () {
    final result = service.parse(
      documentJson(
        plans: <Map<String, dynamic>>[
          planJson(
            sessions: <Map<String, dynamic>>[sessionJson(sport: 'rowing')],
          ),
        ],
      ),
      now: now,
    );
    expect(result.hasErrors, isTrue);
    expect(result.errors.join(' '), contains('sport "rowing" ist unbekannt'));
  });

  test('ungültiges Datum ist ein harter Fehler', () {
    final result = service.parse(
      documentJson(
        plans: <Map<String, dynamic>>[
          planJson(
            sessions: <Map<String, dynamic>>[sessionJson(date: '26.11.2026')],
          ),
        ],
      ),
      now: now,
    );
    expect(result.hasErrors, isTrue);
    expect(result.errors.join(' '), contains('YYYY-MM-DD'));
  });

  test(
    'doppelte session.id innerhalb einer Revision ist ein harter Fehler',
    () {
      final result = service.parse(
        documentJson(
          plans: <Map<String, dynamic>>[
            planJson(
              sessions: <Map<String, dynamic>>[
                sessionJson(id: 'doppelt'),
                sessionJson(id: 'doppelt', date: '2026-11-24'),
              ],
            ),
          ],
        ),
        now: now,
      );
      expect(result.hasErrors, isTrue);
      expect(result.errors.join(' '), contains('doppelte session.id'));
    },
  );

  test('doppelte (plan.id, revision) in der Datei ist ein harter Fehler', () {
    final result = service.parse(
      documentJson(plans: <Map<String, dynamic>>[planJson(), planJson()]),
      now: now,
    );
    expect(result.hasErrors, isTrue);
    expect(result.errors.join(' '), contains('Doppelte Plan-Revision'));
  });

  test('rpe außerhalb 1..10 ist ein harter Fehler', () {
    final result = service.parse(
      documentJson(
        plans: <Map<String, dynamic>>[planJson()],
        activities: <Map<String, dynamic>>[activityJson(rpe: 11)],
      ),
      now: now,
    );
    expect(result.hasErrors, isTrue);
    expect(result.errors.join(' '), contains('rpe muss zwischen 1 und 10'));
  });

  test('negativer Status und unbekannter Status sind harte Fehler', () {
    final result = service.parse(
      documentJson(
        plans: <Map<String, dynamic>>[planJson()],
        activities: <Map<String, dynamic>>[activityJson(status: 'finished')],
      ),
      now: now,
    );
    expect(result.hasErrors, isTrue);
    expect(
      result.errors.join(' '),
      contains('status "finished" ist unbekannt'),
    );
  });

  test('negative Dauern sind harte Fehler', () {
    final result = service.parse(
      documentJson(
        plans: <Map<String, dynamic>>[
          planJson(
            sessions: <Map<String, dynamic>>[
              sessionJson(plannedDurationSeconds: -60),
            ],
          ),
        ],
      ),
      now: now,
    );
    expect(result.hasErrors, isTrue);
    expect(result.errors.join(' '), contains('darf nicht negativ sein'));
  });

  test('overall_feeling außerhalb 0..100 ist ein harter Fehler', () {
    for (final value in <int>[-1, 101]) {
      final result = service.parse(
        documentJson(
          plans: <Map<String, dynamic>>[planJson()],
          journal: <Map<String, dynamic>>[journalJson(overallFeeling: value)],
        ),
        now: now,
      );
      expect(result.hasErrors, isTrue, reason: 'Wert $value');
      expect(result.errors.join(' '), contains('zwischen 0 und 100'));
      expect(result.journal, isEmpty);
    }
  });

  test('overall_feeling als Text ist ein harter Fehler', () {
    final result = service.parse(
      documentJson(
        plans: <Map<String, dynamic>>[planJson()],
        journal: <Map<String, dynamic>>[
          <String, dynamic>{...journalJson(), 'overall_feeling': '60'},
        ],
      ),
      now: now,
    );
    expect(result.hasErrors, isTrue);
    expect(result.errors.join(' '), contains('overall_feeling'));
    expect(result.journal, isEmpty);
  });

  test('overall_feeling 0/100/null ist gültig', () {
    final result = service.parse(
      documentJson(
        plans: <Map<String, dynamic>>[planJson()],
        journal: <Map<String, dynamic>>[
          journalJson(id: 'j0', overallFeeling: 0),
          journalJson(id: 'j100', overallFeeling: 100),
          journalJson(id: 'jnull', overallFeeling: null),
        ],
      ),
      now: now,
    );
    expect(result.errors, isEmpty);
    expect(result.journal.map((entry) => entry.overallFeeling), <int?>[
      0,
      100,
      null,
    ]);
  });

  test('altes metrics-Objekt erzeugt nur eine Warnung, keinen Fehler', () {
    final result = service.parse(
      documentJson(
        plans: <Map<String, dynamic>>[planJson()],
        journal: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'j-alt',
            'timestamp': '2026-11-23T21:30:00+01:00',
            'metrics': <String, dynamic>{'mood': 80},
            'text': 'alt',
          },
        ],
      ),
      now: now,
    );
    expect(result.errors, isEmpty);
    expect(result.warnings.join(' '), contains('unbekanntes Feld "metrics"'));
    expect(result.ignoredUnknownFields, 1);
    expect(result.journal.single.overallFeeling, isNull);
    expect(result.journal.single.text, 'alt');
  });

  test('docs/schema.json beschreibt overall_feeling und kein metrics', () {
    final schema =
        jsonDecode(File('docs/schema.json').readAsStringSync())
            as Map<String, dynamic>;
    final defs = schema[r'$defs'] as Map<String, dynamic>;
    final journalEntry = defs['journalEntry'] as Map<String, dynamic>;
    final properties = journalEntry['properties'] as Map<String, dynamic>;

    expect(properties.containsKey('overall_feeling'), isTrue);
    expect(properties.containsKey('metrics'), isFalse);
    final feeling = properties['overall_feeling'] as Map<String, dynamic>;
    expect(feeling['type'], <String>['integer', 'null']);
    expect(feeling['minimum'], 0);
    expect(feeling['maximum'], 100);
    expect(jsonEncode(schema), isNot(contains('"metrics"')));

    // Schema 1.1: getrennte Zeitpunkte für erstellt/geändert/abgeschlossen.
    for (final key in <String>['timestamp', 'updated_at', 'finalized_at']) {
      expect(properties.containsKey(key), isTrue, reason: key);
    }
    expect((properties['updated_at'] as Map<String, dynamic>)['type'], <String>[
      'string',
      'null',
    ]);
    expect(
      (properties['finalized_at'] as Map<String, dynamic>)['type'],
      <String>['string', 'null'],
    );
    final schemaVersion =
        (schema['properties'] as Map<String, dynamic>)['schema_version']
            as Map<String, dynamic>;
    expect(schemaVersion['enum'], <String>['1.0', '1.1']);
  });

  test('unbekannte Felder werden gezählt und als Hinweis gemeldet', () {
    final plans = <Map<String, dynamic>>[
      <String, dynamic>{...planJson(), 'coach_note': 'x'},
    ];
    final result = service.parse(documentJson(plans: plans), now: now);
    expect(result.errors, isEmpty);
    expect(result.ignoredUnknownFields, 1);
    expect(
      result.warnings.join(' '),
      contains('unbekanntes Feld "coach_note"'),
    );
  });

  test('unbekannter activity-sport ist nur ein Hinweis', () {
    final result = service.parse(
      documentJson(
        plans: <Map<String, dynamic>>[planJson()],
        activities: <Map<String, dynamic>>[
          activityJson(sport: 'rowing', plannedSessionId: null),
        ],
      ),
      now: now,
    );
    expect(result.errors, isEmpty);
    expect(result.warnings.join(' '), contains('unbekannter sport-Wert'));
    expect(result.activities.single.sport, 'rowing');
  });

  test('leere plans-Liste ist ein Hinweis, kein Fehler', () {
    final result = service.parse(
      documentJson(plans: <Map<String, dynamic>>[]),
      now: now,
    );
    expect(result.errors, isEmpty);
    expect(result.warnings.join(' '), contains('keine Pläne'));
  });

  test('Daten mehr als 2 Jahre entfernt erzeugen einen Hinweis', () {
    final result = service.parse(
      documentJson(
        plans: <Map<String, dynamic>>[
          planJson(
            sessions: <Map<String, dynamic>>[sessionJson(date: '2032-01-01')],
          ),
        ],
      ),
      now: now,
    );
    expect(result.errors, isEmpty);
    expect(result.warnings.join(' '), contains('mehr als 2 Jahre'));
  });

  test('unbekannte Struktur-Felder bleiben erhalten', () {
    final result = service.parse(
      documentJson(
        plans: <Map<String, dynamic>>[
          planJson(
            sessions: <Map<String, dynamic>>[
              sessionJson(
                structure: <String, dynamic>{
                  'warmup_seconds': 600,
                  'repetitions': 3,
                  'work_seconds': 300,
                  'target_power_watts': 250,
                },
              ),
            ],
          ),
        ],
      ),
      now: now,
    );
    expect(result.errors, isEmpty);
    final structure = result.plans.single.sessions.single.structure!;
    expect(structure.extra, <String, dynamic>{'target_power_watts': 250});
    expect(
      jsonEncode(structure.toJson()),
      contains('"target_power_watts":250'),
    );
  });

  group('Tagesnotiz-Felder (updated_at/finalized_at)', () {
    String documentWithJournal(
      Map<String, dynamic> journalEntry, {
      String schemaVersion = '1.1',
    }) => jsonEncode(<String, dynamic>{
      'schema_version': schemaVersion,
      'timezone': 'Europe/Berlin',
      'plans': <Map<String, dynamic>>[planJson()],
      'journal': <Map<String, dynamic>>[journalEntry],
    });

    test('1.0-Datei ohne neue Felder bleibt gültig (Altbestand)', () {
      final result = service.parse(
        documentWithJournal(journalJson(), schemaVersion: '1.0'),
        now: now,
      );
      expect(result.errors, isEmpty);
      // 1.0 wird weiterhin akzeptiert – kein Hinweis zur Version.
      expect(result.warnings.join(' '), isNot(contains('schema_version')));
      final entry = result.journal.single;
      expect(entry.updatedAt, isNull);
      expect(entry.finalizedAt, isNull);
      expect(entry.lastChangedAt, entry.timestamp);
    });

    test('1.1-Datei mit updated_at/finalized_at wird übernommen', () {
      final result = service.parse(
        documentWithJournal(<String, dynamic>{
          ...journalJson(),
          'updated_at': '2026-11-23T22:05:00+01:00',
          'finalized_at': '2026-11-23T21:30:00+01:00',
        }),
        now: now,
      );
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
      final entry = result.journal.single;
      expect(entry.updatedAt, '2026-11-23T22:05:00+01:00');
      expect(entry.finalizedAt, '2026-11-23T21:30:00+01:00');
      expect(entry.isFinalized, isTrue);
      expect(result.ignoredUnknownFields, 0);
    });

    test('finalized_at vor timestamp ist ein harter Fehler', () {
      final result = service.parse(
        documentWithJournal(<String, dynamic>{
          ...journalJson(timestamp: '2026-11-23T21:30:00+01:00'),
          'finalized_at': '2026-11-23T07:00:00+01:00',
        }),
        now: now,
      );
      expect(result.hasErrors, isTrue);
      expect(result.errors.join(' '), contains('finalized_at'));
      expect(result.errors.join(' '), contains('vor timestamp'));
      expect(result.journal, isEmpty);
    });

    test('updated_at vor timestamp ist ein harter Fehler', () {
      final result = service.parse(
        documentWithJournal(<String, dynamic>{
          ...journalJson(timestamp: '2026-11-23T21:30:00+01:00'),
          'updated_at': '2026-11-23T06:00:00+01:00',
        }),
        now: now,
      );
      expect(result.hasErrors, isTrue);
      expect(result.errors.join(' '), contains('updated_at'));
      expect(result.errors.join(' '), contains('vor timestamp'));
      expect(result.journal, isEmpty);
    });

    test('kaputter ISO-Zeitstempel in updated_at ist ein harter Fehler', () {
      final result = service.parse(
        documentWithJournal(<String, dynamic>{
          ...journalJson(),
          'updated_at': 'gestern abend',
        }),
        now: now,
      );
      expect(result.hasErrors, isTrue);
      expect(result.errors.join(' '), contains('ist kein ISO-Zeitstempel'));
      expect(result.journal, isEmpty);
    });

    test('unbekannte schema_version erzeugt weiterhin nur einen Hinweis', () {
      final result = service.parse(
        documentWithJournal(journalJson(), schemaVersion: '2.0'),
        now: now,
      );
      expect(result.errors, isEmpty);
      expect(result.warnings.join(' '), contains('schema_version "2.0"'));
      expect(result.warnings.join(' '), contains('1.1'));
      expect(result.journal, hasLength(1));
    });
  });
}
