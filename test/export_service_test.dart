import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/services/export_service.dart';
import 'package:tri_log/utils/formats.dart';

import 'fixtures.dart';

void main() {
  const exporter = ExportService();
  final now = DateTime(2026, 11, 16, 20, 5, 6);

  group('JSON-Export', () {
    test(
      'enthält schema_version, exported_at, timezone, plans, activities, journal',
      () {
        final json =
            jsonDecode(exporter.buildJson(sampleState(), now: now))
                as Map<String, dynamic>;

        expect(json['schema_version'], '1.1');
        expect(json['timezone'], 'Europe/Berlin');
        expect(
          RegExp(
            r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$',
          ).hasMatch(json['exported_at'] as String),
          isTrue,
        );
        expect(json['plans'], hasLength(1));
        expect(json['activities'], hasLength(1));
        expect(json['journal'], hasLength(1));

        final activity =
            (json['activities'] as List<dynamic>).single
                as Map<String, dynamic>;
        expect(activity['id'], 'a1');
        expect(activity['started_at'], '2026-11-23T18:05:00+01:00');
      },
    );

    test('ohne Zeitraum sind alle Activities/Journal-Einträge enthalten', () {
      final state = sampleState(
        activities: <Activity>[
          ...sampleState().activities,
          Activity(
            id: 'a-alt',
            startedAt: '2025-01-01T10:00:00+01:00',
            status: ActivityStatus.skipped,
          ),
        ],
      );
      final json =
          jsonDecode(exporter.buildJson(state, now: now))
              as Map<String, dynamic>;
      expect(json['activities'], hasLength(2));
    });

    test('Zeitraum filtert Activities/Journal, Pläne bleiben vollständig', () {
      final state = sampleState(
        plans: <Plan>[
          sampleState().plans.first,
          Plan(
            id: 'winter-2026',
            revision: 2,
            title: 'Wintergrundlage',
            sessions: sampleState().plans.first.sessions,
          ),
        ],
        activities: <Activity>[
          ...sampleState().activities,
          Activity(
            id: 'a-dez',
            startedAt: '2026-12-05T10:00:00+01:00',
            status: ActivityStatus.completed,
          ),
        ],
      );

      final json =
          jsonDecode(
                exporter.buildJson(
                  state,
                  from: DateTime(2026, 12, 1),
                  to: DateTime(2026, 12, 31),
                  now: now,
                ),
              )
              as Map<String, dynamic>;

      expect(json['plans'], hasLength(2));
      final activities = json['activities'] as List<dynamic>;
      expect(activities, hasLength(1));
      expect((activities.single as Map<String, dynamic>)['id'], 'a-dez');
      expect(json['journal'], isEmpty);
    });

    test('Zeitraum ist inklusiv (Randtage zählen mit)', () {
      final json =
          jsonDecode(
                exporter.buildJson(
                  sampleState(),
                  from: DateTime(2026, 11, 23),
                  to: DateTime(2026, 11, 23),
                  now: now,
                ),
              )
              as Map<String, dynamic>;
      expect(json['activities'], hasLength(1));
      expect(json['journal'], hasLength(1));
    });

    test('Dateinamen', () {
      expect(exporter.fileNameJson(now), 'tri-log-export-2026-11-16.json');
      expect(exporter.fileNameMarkdown(now), 'tri-log-export-2026-11-16.md');
    });
  });

  group('Markdown-Export', () {
    test('enthält Kopfzeile, Woche, geplant vs. ist und Abweichung', () {
      final markdown = exporter.buildMarkdown(sampleState(), now: now);

      expect(markdown, startsWith('# Tri-Log Export'));
      expect(markdown, contains('Zeitraum: alle Daten'));
      expect(markdown, contains('Exportiert: 16.11.2026'));
      expect(markdown, contains('(Europe/Berlin)'));
      expect(markdown, contains('## Woche 23.11.2026 – 29.11.2026 (KW 48)'));
      expect(markdown, contains('### Mo, 23.11.2026'));

      expect(markdown, contains('**Geplant**'));
      expect(
        markdown,
        contains(
          'Schwimmen · Technik · 45 min · Struktur: 10 min Einfahren · '
          '3× 5 min / 3 min Pause · 19 min Ausfahren',
        ),
      );

      expect(markdown, contains('**Ist**'));
      expect(
        markdown,
        contains('Schwimmen · Technik · abgeschlossen · 47 min'),
      );
      expect(markdown, contains('1,8 km'));
      expect(markdown, contains('RPE 6'));
      expect(markdown, contains('Abweichung +2 min'));
      expect(markdown, contains('Notiz: „Lief gut“'));
    });

    test(
      'Tagebuch-Einträge zeigen das Gesamtbefinden und – bei fehlendem Wert',
      () {
        final markdown = exporter.buildMarkdown(sampleState(), now: now);
        expect(markdown, contains('**Tagebuch**'));
        expect(markdown, contains('Gesamtbefinden: 80 %'));
        expect(markdown, contains('Guter Schlaf'));
        expect(markdown, isNot(contains('metrics')));
        expect(markdown, isNot(contains('Energie')));

        final withoutFeeling = exporter.buildMarkdown(
          sampleState(
            journal: <JournalEntry>[
              const JournalEntry(
                id: 'j2',
                timestamp: '2026-11-23T22:00:00+01:00',
                text: 'Müde',
              ),
            ],
          ),
          now: now,
        );
        expect(withoutFeeling, contains('Gesamtbefinden: –'));
        expect(withoutFeeling, contains('Müde'));
      },
    );

    test(
      'Tagebuchzeilen kennzeichnen Entwurf bzw. Abschluss samt Zeitstempeln',
      () {
        final draft = JournalEntry(
          id: 'j-draft',
          timestamp: isoWithOffset(DateTime(2026, 11, 23, 7, 12)),
          updatedAt: isoWithOffset(DateTime(2026, 11, 23, 18, 40)),
          overallFeeling: 60,
          text: 'Tagsüber gesammelt',
        );
        final done = JournalEntry(
          id: 'j-done',
          timestamp: isoWithOffset(DateTime(2026, 11, 24, 7, 0)),
          updatedAt: isoWithOffset(DateTime(2026, 11, 24, 21, 14)),
          finalizedAt: isoWithOffset(DateTime(2026, 11, 24, 21, 14)),
          overallFeeling: 70,
          text: 'Abendnotiz',
        );

        final markdown = exporter.buildMarkdown(
          sampleState(journal: <JournalEntry>[draft, done]),
          now: now,
        );

        expect(markdown, contains('07:12 · Gesamtbefinden: 60 % · Entwurf'));
        expect(markdown, contains('(erstellt 07:12, zuletzt geändert 18:40)'));
        expect(
          markdown,
          contains('07:00 · Gesamtbefinden: 70 % · abgeschlossen 21:14'),
        );
        expect(markdown, contains('Abendnotiz'));
      },
    );

    test(
      'JSON-Export enthält updated_at/finalized_at und schema_version 1.1',
      () {
        final state = sampleState(
          journal: <JournalEntry>[
            JournalEntry(
              id: 'j-done',
              timestamp: isoWithOffset(DateTime(2026, 11, 23, 7, 12)),
              updatedAt: isoWithOffset(DateTime(2026, 11, 23, 21, 14)),
              finalizedAt: isoWithOffset(DateTime(2026, 11, 23, 21, 14)),
              overallFeeling: 70,
              text: 'Abendnotiz',
            ),
          ],
        );
        final json =
            jsonDecode(exporter.buildJson(state, now: now))
                as Map<String, dynamic>;
        expect(json['schema_version'], '1.1');
        final entry =
            (json['journal'] as List<dynamic>).single as Map<String, dynamic>;
        expect(entry['timestamp'], isNotNull);
        expect(entry['updated_at'], isNotNull);
        expect(entry['finalized_at'], isNotNull);
        expect(
          DateTime.parse(
            entry['finalized_at'] as String,
          ).isAtSameMomentAs(DateTime.parse(entry['timestamp'] as String)),
          isFalse,
        );
      },
    );

    test('Tage ohne Ist-Daten zeigen – und keine erfundenen Werte', () {
      final markdown = exporter.buildMarkdown(sampleState(), now: now);
      expect(markdown, contains('### Do, 26.11.2026'));
      expect(markdown, contains('Laufen · Lockerer Dauerlauf · 40 min'));
      // 26.11. hat weder Aktivität noch Tagebucheintrag.
      final dayBlock = markdown.split('### Do, 26.11.2026').last;
      expect(dayBlock, contains('- –'));
      expect(dayBlock, isNot(contains('abgeschlossen')));
    });

    test('leerer Zeitraum liefert einen sinnvollen Text', () {
      final markdown = exporter.buildMarkdown(
        sampleState(),
        from: DateTime(2027, 1, 1),
        to: DateTime(2027, 1, 31),
        now: now,
      );
      expect(markdown, contains('Zeitraum: 01.01.2027 – 31.01.2027'));
      expect(markdown, contains('Keine Einheiten im Zeitraum.'));
    });

    test('leeres Dokument funktioniert ohne Absturz', () {
      final markdown = exporter.buildMarkdown(AppState.empty(), now: now);
      expect(markdown, contains('# Tri-Log Export'));
      expect(markdown, contains('Keine Einheiten im Zeitraum.'));
    });

    test('ungeplante Aktivität wird als solche gekennzeichnet', () {
      final markdown = exporter.buildMarkdown(
        AppState(
          activities: <Activity>[
            Activity(
              id: 'frei',
              sport: 'rowing',
              startedAt: '2026-11-24T09:00:00+01:00',
              status: ActivityStatus.completed,
              elapsedDurationSeconds: 3600,
            ),
          ],
        ),
        now: now,
      );
      expect(markdown, contains('rowing · abgeschlossen · 60 min'));
      expect(markdown, contains('**Geplant**'));
    });
  });
}
