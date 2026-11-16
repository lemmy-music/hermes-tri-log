import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/state/app_repository.dart';
import 'package:tri_log/utils/formats.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = DateTime(2026, 11, 23, 9);

  AppRepository buildRepository() => AppRepository(
    clock: () => today,
    saveDebounce: const Duration(milliseconds: 1),
  );

  /// Repository mit einem importierten Plan (Sitzung `s1` am 23.11.).
  Future<AppRepository> buildWithPlan({
    List<Map<String, dynamic>>? activities,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = buildRepository();
    await repository.load();
    repository.importPlans(
      repository.parseImport(documentJson(activities: activities)),
    );
    await repository.flush();
    return repository;
  }

  group('saveActivityForSession', () {
    test('legt eine Aktivität mit vollständigem Sitzungsbezug an', () async {
      final repository = await buildWithPlan();
      final entry = repository.todaySessions.single;

      final activity = repository.saveActivityForSession(
        plan: entry.plan,
        session: entry.session,
        status: ActivityStatus.completed,
        elapsedDurationSeconds: 2700,
      );

      expect(repository.state.activities, hasLength(1));
      expect(activity.id, startsWith('act-'));
      expect(activity.planId, 'winter-2026');
      expect(activity.planRevision, 1);
      expect(activity.plannedSessionId, 's1');
      expect(activity.sport, 'swim');
      expect(activity.status, ActivityStatus.completed);
      expect(activity.elapsedDurationSeconds, 2700);
      expect(activity.movingDurationSeconds, isNull);
      expect(activity.rpe, isNull);
      expect(activity.notes, isNull);
      expect(
        DateTime.parse(activity.startedAt).isAtSameMomentAs(today),
        isTrue,
      );
      expect(repository.activityForSession('s1')?.id, activity.id);

      repository.dispose();
    });

    test(
      'zweiter Aufruf erzeugt kein Duplikat, sondern überschreibt',
      () async {
        final repository = await buildWithPlan();
        final entry = repository.todaySessions.single;

        final first = repository.saveActivityForSession(
          plan: entry.plan,
          session: entry.session,
          status: ActivityStatus.completed,
          elapsedDurationSeconds: 2700,
        );
        final updated = repository.saveActivityForSession(
          plan: entry.plan,
          session: entry.session,
          status: ActivityStatus.partial,
          elapsedDurationSeconds: 1800,
          rpe: 7,
          notes: 'Nur die Hälfte',
        );

        expect(repository.state.activities, hasLength(1));
        expect(updated.id, first.id);
        expect(updated.startedAt, first.startedAt);
        expect(updated.status, ActivityStatus.partial);
        expect(updated.elapsedDurationSeconds, 1800);
        expect(updated.rpe, 7);
        expect(updated.notes, 'Nur die Hälfte');
        expect(
          repository.activityForSession('s1')?.status,
          ActivityStatus.partial,
        );

        repository.dispose();
      },
    );

    test(
      'übernimmt eine bereits importierte Aktivität derselben Sitzung',
      () async {
        final repository = await buildWithPlan(
          activities: <Map<String, dynamic>>[activityJson()],
        );
        expect(repository.state.activities, hasLength(1));

        final entry = repository.todaySessions.single;
        final updated = repository.saveActivityForSession(
          plan: entry.plan,
          session: entry.session,
          status: ActivityStatus.partial,
          elapsedDurationSeconds: 1200,
        );

        expect(repository.state.activities, hasLength(1));
        expect(updated.id, 'a1');
        expect(updated.startedAt, '2026-11-23T18:05:00+01:00');
        expect(updated.status, ActivityStatus.partial);

        repository.dispose();
      },
    );
  });

  group('deleteActivity', () {
    test('entfernt eine Aktivität und benachrichtigt', () async {
      final repository = await buildWithPlan();
      final entry = repository.todaySessions.single;
      final activity = repository.saveActivityForSession(
        plan: entry.plan,
        session: entry.session,
        status: ActivityStatus.completed,
      );

      var notifications = 0;
      repository.addListener(() => notifications++);

      repository.deleteActivity(activity.id);
      expect(repository.state.activities, isEmpty);
      expect(repository.activityForSession('s1'), isNull);
      expect(notifications, 1);

      repository.dispose();
    });

    test('unbekannte ID ändert nichts', () async {
      final repository = await buildWithPlan(
        activities: <Map<String, dynamic>>[activityJson()],
      );
      var notifications = 0;
      repository.addListener(() => notifications++);

      repository.deleteActivity('gibt-es-nicht');
      expect(repository.state.activities, hasLength(1));
      expect(notifications, 0);

      repository.dispose();
    });
  });

  group('Ungeplante Einheiten', () {
    test('ohne Planbezug, nur am richtigen Tag gelistet', () async {
      final repository = await buildWithPlan();

      final todayActivity = Activity(
        id: repository.nextActivityId(),
        sport: Sport.run.wireName,
        startedAt: isoWithOffset(DateTime(2026, 11, 23, 18, 30)),
        status: ActivityStatus.completed,
        elapsedDurationSeconds: 1800,
      );
      final otherDay = Activity(
        id: repository.nextActivityId(),
        sport: Sport.bike.wireName,
        startedAt: isoWithOffset(DateTime(2026, 11, 24, 10)),
        status: ActivityStatus.completed,
        elapsedDurationSeconds: 3600,
      );

      repository.saveActivity(todayActivity);
      repository.saveActivity(otherDay);

      expect(repository.state.activities, hasLength(2));
      expect(todayActivity.planId, isNull);
      expect(todayActivity.plannedSessionId, isNull);
      expect(repository.todayUnplannedActivities, hasLength(1));
      expect(repository.todayUnplannedActivities.single.id, todayActivity.id);
      expect(
        repository.unplannedActivitiesForDate(DateTime(2026, 11, 24)),
        hasLength(1),
      );

      repository.dispose();
    });

    test('saveActivity ist ein Upsert per id', () async {
      final repository = await buildWithPlan();
      final id = repository.nextActivityId();
      repository.saveActivity(
        Activity(
          id: id,
          sport: 'other',
          startedAt: isoWithOffset(DateTime(2026, 11, 23, 7)),
          status: ActivityStatus.completed,
        ),
      );
      repository.saveActivity(
        Activity(
          id: id,
          sport: 'other',
          startedAt: isoWithOffset(DateTime(2026, 11, 23, 7)),
          status: ActivityStatus.skipped,
          notes: 'doch nicht',
        ),
      );

      expect(repository.state.activities, hasLength(1));
      expect(repository.state.activities.single.status, ActivityStatus.skipped);
      expect(repository.state.activities.single.notes, 'doch nicht');

      repository.dispose();
    });
  });

  test('Aktivitäten überleben Neustart (Persistenz-Roundtrip)', () async {
    final repository = await buildWithPlan();
    final entry = repository.todaySessions.single;
    repository.saveActivityForSession(
      plan: entry.plan,
      session: entry.session,
      status: ActivityStatus.completed,
      elapsedDurationSeconds: 2700,
      distanceMeters: 1500,
    );
    repository.saveActivity(
      Activity(
        id: 'frei-1',
        sport: Sport.strength.wireName,
        startedAt: isoWithOffset(DateTime(2026, 11, 23, 20)),
        status: ActivityStatus.completed,
        elapsedDurationSeconds: 1200,
      ),
    );
    await repository.flush();
    repository.dispose();

    final reloaded = buildRepository();
    await reloaded.load();
    expect(reloaded.state.activities, hasLength(2));
    expect(reloaded.activityForSession('s1')?.elapsedDurationSeconds, 2700);
    expect(reloaded.activityForSession('s1')?.distanceMeters, 1500);
    expect(reloaded.todayUnplannedActivities.single.sport, 'strength');
    reloaded.dispose();
  });
}
