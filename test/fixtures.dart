import 'dart:convert';

import 'package:tri_log/models/models.dart';

/// Baut ein Sitzungs-JSON. Nicht gesetzte optionale Felder werden als `null`
/// ausgegeben (das Format schreibt explizite Nullen vor, nicht Weglassen).
Map<String, dynamic> sessionJson({
  String id = 's1',
  String date = '2026-11-23',
  String sport = 'swim',
  String type = 'Technik',
  bool? optional,
  int? plannedDurationSeconds = 2700,
  String? instructions,
  Map<String, dynamic>? structure,
}) => <String, dynamic>{
  'id': id,
  'date': date,
  'sport': sport,
  'type': type,
  'optional': optional,
  'planned_duration_seconds': plannedDurationSeconds,
  'instructions': instructions,
  'structure': structure,
};

Map<String, dynamic> planJson({
  String id = 'winter-2026',
  int revision = 1,
  String title = 'Wintergrundlage',
  List<Map<String, dynamic>>? sessions,
}) => <String, dynamic>{
  'id': id,
  'revision': revision,
  'title': title,
  'sessions': sessions ?? <Map<String, dynamic>>[sessionJson()],
};

Map<String, dynamic> activityJson({
  String id = 'a1',
  String? planId = 'winter-2026',
  int? planRevision = 1,
  String? plannedSessionId = 's1',
  String? sport,
  String startedAt = '2026-11-23T18:05:00+01:00',
  String status = 'completed',
  int? elapsed = 2820,
  int? moving,
  double? distance,
  int? heartRate,
  int? power,
  int? rpe = 6,
  String? notes,
}) => <String, dynamic>{
  'id': id,
  'plan_id': planId,
  'plan_revision': planRevision,
  'planned_session_id': plannedSessionId,
  'sport': sport,
  'started_at': startedAt,
  'status': status,
  'elapsed_duration_seconds': elapsed,
  'moving_duration_seconds': moving,
  'distance_meters': distance,
  'average_heart_rate_bpm': heartRate,
  'average_power_watts': power,
  'rpe': rpe,
  'notes': notes,
};

Map<String, dynamic> journalJson({
  String id = 'j1',
  String timestamp = '2026-11-23T21:30:00+01:00',
  Map<String, int?>? metrics,
  String? text,
}) => <String, dynamic>{
  'id': id,
  'timestamp': timestamp,
  'metrics':
      metrics ?? <String, int?>{'energy': 70, 'mood': 80, 'happiness': null},
  'text': text,
};

/// Komplettes Dokument als JSON-Text (Plan-only oder vollständig).
String documentJson({
  List<Map<String, dynamic>>? plans,
  List<Map<String, dynamic>>? activities,
  List<Map<String, dynamic>>? journal,
  bool includePlans = true,
}) => jsonEncode(<String, dynamic>{
  'schema_version': '1.0',
  'timezone': 'Europe/Berlin',
  if (includePlans) 'plans': plans ?? <Map<String, dynamic>>[planJson()],
  'activities': ?activities,
  'journal': ?journal,
});

/// Beispielzustand für Export- und Merge-Tests.
AppState sampleState({
  List<Plan>? plans,
  List<Activity>? activities,
  List<JournalEntry>? journal,
}) => AppState(
  plans:
      plans ??
      <Plan>[
        Plan(
          id: 'winter-2026',
          revision: 1,
          title: 'Wintergrundlage',
          sessions: const <Session>[
            Session(
              id: 's1',
              date: '2026-11-23',
              sport: Sport.swim,
              type: 'Technik',
              plannedDurationSeconds: 2700,
              instructions: 'Locker einschwimmen.',
              structure: SessionStructure(
                warmupSeconds: 600,
                repetitions: 3,
                workSeconds: 300,
                recoverySeconds: 180,
                cooldownSeconds: 1140,
              ),
            ),
            Session(
              id: 's2',
              date: '2026-11-26',
              sport: Sport.run,
              type: 'Lockerer Dauerlauf',
              plannedDurationSeconds: 2400,
            ),
          ],
        ),
      ],
  activities:
      activities ??
      <Activity>[
        Activity(
          id: 'a1',
          planId: 'winter-2026',
          planRevision: 1,
          plannedSessionId: 's1',
          startedAt: '2026-11-23T18:05:00+01:00',
          status: ActivityStatus.completed,
          elapsedDurationSeconds: 2820,
          distanceMeters: 1800,
          rpe: 6,
          notes: 'Lief gut',
        ),
      ],
  journal:
      journal ??
      <JournalEntry>[
        JournalEntry(
          id: 'j1',
          timestamp: '2026-11-23T21:30:00+01:00',
          metrics: <String, int?>{'energy': 70, 'mood': 80, 'happiness': null},
          text: 'Guter Schlaf',
        ),
      ],
);
