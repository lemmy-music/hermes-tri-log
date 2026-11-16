import 'package:flutter_test/flutter_test.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/services/import_service.dart';
import 'package:tri_log/services/merge_service.dart';

import 'fixtures.dart';

void main() {
  const service = ImportService();
  final now = DateTime(2026, 11, 16, 12);

  MergeResult mergeWith(
    AppState current,
    List<Map<String, dynamic>> plans, {
    List<Map<String, dynamic>>? activities,
    List<Map<String, dynamic>>? journal,
  }) {
    final imported = service.parse(
      documentJson(plans: plans, activities: activities, journal: journal),
      now: now,
    );
    expect(imported.errors, isEmpty);
    return computeMerge(current: current, imported: imported);
  }

  test('Regel 2: identische Revision ist ein No-op', () {
    final current = sampleState();
    final merge = mergeWith(current, <Map<String, dynamic>>[
      current.plans.first.toJson(),
    ]);

    expect(merge.hasConflict, isFalse);
    expect(merge.plans.single.status, PlanImportStatus.unchanged);
    expect(merge.hasChanges, isFalse);
    expect(merge.affectedDayCount, 0);
    expect(merge.proposedState!.plans.length, 1);
    expect(merge.summaryDe, 'Keine Änderungen.');
  });

  test('Regel 3: gleiche Revision mit anderem Inhalt blockiert den Import', () {
    final current = sampleState();
    final changed = current.plans.first.toJson()
      ..['title'] = 'Ganz anderer Titel';
    final merge = mergeWith(current, <Map<String, dynamic>>[changed]);

    expect(merge.hasConflict, isTrue);
    expect(merge.plans.single.status, PlanImportStatus.conflict);
    expect(merge.proposedState, isNull);
    expect(
      merge.plans.single.conflictMessage,
      contains('bitte Revision erhöhen'),
    );
    expect(merge.plans.single.conflictMessage, contains('Revision 1'));
  });

  test('Regel 4: neuer Plan wird hinzugefügt, ältere Revisionen bleiben', () {
    final current = sampleState();
    final merge = mergeWith(current, <Map<String, dynamic>>[
      planJson(
        id: 'fruehjahr-2027',
        revision: 1,
        sessions: <Map<String, dynamic>>[
          sessionJson(id: 'f1', date: '2027-03-01', sport: 'bike'),
        ],
      ),
      planJson(
        id: 'fruehjahr-2027',
        revision: 2,
        sessions: <Map<String, dynamic>>[
          sessionJson(id: 'f1', date: '2027-03-01', sport: 'bike'),
          sessionJson(
            id: 'f2',
            date: '2027-03-02',
            sport: 'run',
            plannedDurationSeconds: 1800,
          ),
        ],
      ),
    ]);

    expect(merge.hasConflict, isFalse);
    expect(merge.plans.map((diff) => diff.status), <PlanImportStatus>[
      PlanImportStatus.newPlan,
      PlanImportStatus.newRevision,
    ]);
    // Rev 2 basiert auf Rev 1: nur f2 ist neu, f1 unverändert.
    expect(merge.plans[1].addedSessions, 1);
    expect(merge.plans[1].changedSessions, 0);
    expect(merge.plans[1].removedSessions, 0);
    expect(merge.proposedState!.plans.length, 3);
    expect(merge.proposedState!.latestPlanFor('fruehjahr-2027')!.revision, 2);
  });

  test('Regel 5: neue Revision zählt hinzugefügt/geändert/entfernt', () {
    final current = sampleState();
    final revision2 = <String, dynamic>{
      'id': 'winter-2026',
      'revision': 2,
      'title': 'Wintergrundlage',
      'sessions': <Map<String, dynamic>>[
        // s1 verändert (Dauer), s2 entfernt, s3 neu
        sessionJson(id: 's1', date: '2026-11-23', plannedDurationSeconds: 3000),
        sessionJson(id: 's3', date: '2026-11-25', sport: 'bike'),
      ],
    };
    final merge = mergeWith(current, <Map<String, dynamic>>[revision2]);

    final diff = merge.plans.single;
    expect(diff.status, PlanImportStatus.newRevision);
    expect(diff.addedSessions, 1);
    expect(diff.changedSessions, 1);
    expect(diff.removedSessions, 1);
    expect(diff.affectedDates, <String>{
      '2026-11-23',
      '2026-11-25',
      '2026-11-26',
    });
    expect(merge.affectedDayCount, 3);
    expect(merge.addedSessions, 1);
    expect(merge.changedSessions, 1);
    expect(merge.removedSessions, 1);
    expect(merge.proposedState!.plans.length, 2);
  });

  test(
    'Regel 6: Activities bleiben unverändert, Warnung bei entfernter Sitzung',
    () {
      final current = sampleState(
        activities: <Activity>[
          // verweist auf die Sitzung s2 (2026-11-26), die in Rev 2 wegfällt
          Activity(
            id: 'a2',
            planId: 'winter-2026',
            planRevision: 1,
            plannedSessionId: 's2',
            startedAt: '2026-11-26T17:00:00+01:00',
            status: ActivityStatus.completed,
            elapsedDurationSeconds: 2400,
          ),
        ],
      );
      final merge = mergeWith(current, <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'winter-2026',
          'revision': 2,
          'title': 'Wintergrundlage',
          'sessions': <Map<String, dynamic>>[
            sessionJson(id: 's1', date: '2026-11-23'),
          ],
        },
      ]);

      expect(merge.hasConflict, isFalse);
      expect(merge.plans.single.removedSessions, 1);
      expect(merge.plans.single.warnings.join(' '), contains('Aktivität'));
      expect(merge.plans.single.warnings.join(' '), contains('s2'));
      expect(merge.proposedState!.activities.length, 1);
      expect(merge.proposedState!.activities.single.id, 'a2');
      expect(merge.addedActivities, 0);
    },
  );

  test('Regel 7: Activities/Journal werden per id ergänzt, nie gelöscht', () {
    final current = sampleState();
    final merge = mergeWith(
      current,
      <Map<String, dynamic>>[current.plans.first.toJson()],
      activities: <Map<String, dynamic>>[
        current.activities.first.toJson(),
        activityJson(
          id: 'a2',
          plannedSessionId: 's2',
          startedAt: '2026-11-26T17:00:00+01:00',
          rpe: 4,
        ),
      ],
      journal: <Map<String, dynamic>>[
        current.journal.first.toJson(),
        journalJson(id: 'j2', timestamp: '2026-11-26T21:00:00+01:00'),
      ],
    );

    expect(merge.hasConflict, isFalse);
    expect(merge.plans.single.status, PlanImportStatus.unchanged);
    expect(merge.addedActivities, 1);
    expect(merge.addedJournalEntries, 1);
    expect(merge.proposedState!.activities.length, 2);
    expect(merge.proposedState!.journal.length, 2);
    expect(merge.hasChanges, isTrue);
  });

  test('Konflikt blockiert den gesamten Import (auch Activities)', () {
    final current = sampleState();
    final changed = current.plans.first.toJson()..['title'] = 'Umbenannt';
    final merge = mergeWith(
      current,
      <Map<String, dynamic>>[changed],
      activities: <Map<String, dynamic>>[activityJson(id: 'neu')],
    );

    expect(merge.hasConflict, isTrue);
    expect(merge.proposedState, isNull);
    expect(merge.addedActivities, 0);
  });

  test('betroffene Tage werden über mehrere Pläne vereinigt', () {
    final current = sampleState();
    final merge = mergeWith(current, <Map<String, dynamic>>[
      planJson(
        id: 'p-a',
        sessions: <Map<String, dynamic>>[
          sessionJson(id: 'a1', date: '2027-01-04', sport: 'swim'),
        ],
      ),
      planJson(
        id: 'p-b',
        sessions: <Map<String, dynamic>>[
          sessionJson(id: 'b1', date: '2027-01-04', sport: 'bike'),
          sessionJson(id: 'b2', date: '2027-01-06', sport: 'run'),
        ],
      ),
    ]);

    expect(
      merge.plans.every((diff) => diff.status == PlanImportStatus.newPlan),
      isTrue,
    );
    expect(merge.affectedDayCount, 2);
    expect(merge.summaryDe, contains('3 hinzugefügt'));
    expect(merge.summaryDe, contains('2 Tag(e) betroffen'));
  });

  test('ältere Revision einer bekannten plan.id erzeugt einen Hinweis', () {
    final current = sampleState(
      plans: <Plan>[
        Plan(
          id: 'winter-2026',
          revision: 3,
          title: 'Wintergrundlage',
          sessions: const <Session>[
            Session(
              id: 's1',
              date: '2026-11-23',
              sport: Sport.swim,
              type: 'Technik',
              plannedDurationSeconds: 2700,
            ),
            Session(
              id: 's2',
              date: '2026-11-26',
              sport: Sport.run,
              type: 'Lauf',
              plannedDurationSeconds: 2400,
            ),
          ],
        ),
      ],
    );
    final merge = mergeWith(current, <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'winter-2026',
        'revision': 2,
        'title': 'Wintergrundlage',
        'sessions': <Map<String, dynamic>>[sessionJson()],
      },
    ]);

    expect(merge.hasConflict, isFalse);
    expect(merge.plans.single.status, PlanImportStatus.newRevision);
    expect(merge.plans.single.warnings.join(' '), contains('älter als'));
    expect(merge.removedSessions, 1);
  });
}
