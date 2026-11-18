import '../utils/formats.dart';

/// Version des Dokumentformats (Import/Export/Storage).
const String kSchemaVersion = '1.1';

/// Versionen, die beim Import weiterhin akzeptiert werden.
///
/// `1.0` kennt weder `updated_at` noch `finalized_at` – solche Einträge gelten
/// als Altbestand (fehlende Felder = `null`).
const Set<String> kAcceptedSchemaVersions = <String>{'1.0', '1.1'};

/// Feste Zeitzone des Datenmodells – alle Datumswerte sind lokale Kalendertage
/// bzw. ISO-Zeitstempel mit Offset.
const String kTimezone = 'Europe/Berlin';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

/// Sportarten inkl. Anzeige-Reihenfolge (Reihenfolge der Enum-Werte ist die
/// Sortierung der Heute-Liste: swim → bike → run → strength → other).
enum Sport { swim, bike, run, strength, other }

const Map<String, Sport> _sportByWireName = <String, Sport>{
  'swim': Sport.swim,
  'bike': Sport.bike,
  'run': Sport.run,
  'strength': Sport.strength,
  'other': Sport.other,
};

/// Liefert `null` für unbekannte Werte (nichts wird stillschweigend ersetzt).
Sport? sportFromWireName(String? name) =>
    name == null ? null : _sportByWireName[name];

/// Anzeigename für einen Wire-Wert (z. B. an ungeplanten Aktivitäten).
/// Unbekannte Werte werden unverändert zurückgegeben, `null` → `''`.
String sportLabelFromWireName(String? name) =>
    sportFromWireName(name)?.labelDe ?? (name ?? '');

extension SportX on Sport {
  String get wireName => switch (this) {
    Sport.swim => 'swim',
    Sport.bike => 'bike',
    Sport.run => 'run',
    Sport.strength => 'strength',
    Sport.other => 'other',
  };

  String get labelDe => switch (this) {
    Sport.swim => 'Schwimmen',
    Sport.bike => 'Rad',
    Sport.run => 'Laufen',
    Sport.strength => 'Kraft',
    Sport.other => 'Sonstiges',
  };

  /// Sortierindex für die Anzeige (swim zuerst).
  int get sortIndex => index;
}

/// Status einer tatsächlich absolvierten Einheit.
enum ActivityStatus { completed, partial, skipped }

const Map<String, ActivityStatus> _statusByWireName = <String, ActivityStatus>{
  'completed': ActivityStatus.completed,
  'partial': ActivityStatus.partial,
  'skipped': ActivityStatus.skipped,
};

ActivityStatus? activityStatusFromWireName(String? name) =>
    name == null ? null : _statusByWireName[name];

extension ActivityStatusX on ActivityStatus {
  String get wireName => switch (this) {
    ActivityStatus.completed => 'completed',
    ActivityStatus.partial => 'partial',
    ActivityStatus.skipped => 'skipped',
  };

  String get labelDe => switch (this) {
    ActivityStatus.completed => 'abgeschlossen',
    ActivityStatus.partial => 'teilweise',
    ActivityStatus.skipped => 'ausgelassen',
  };

  /// Kurze Anzeige für Karte, Badge und Sheet („Erledigt“/„Teilweise“/
  /// „Ausgelassen“). [labelDe] bleibt die ausführliche Form für den Export.
  String get shortLabelDe => switch (this) {
    ActivityStatus.completed => 'Erledigt',
    ActivityStatus.partial => 'Teilweise',
    ActivityStatus.skipped => 'Ausgelassen',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Tolerante Lese-Helfer (fehlende/falsch typisierte Werte → null)
// ─────────────────────────────────────────────────────────────────────────────

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  return null;
}

double? _readDouble(Object? value) => value is num ? value.toDouble() : null;

bool? _readBool(Object? value) => value is bool ? value : null;

String? _readString(Object? value) => value is String ? value : null;

/// ISO-Zeitstempel: nur Strings, die sich parsen lassen (sonst `null`).
String? _readIsoTimestamp(Object? value) {
  final text = _readString(value);
  if (text == null || DateTime.tryParse(text) == null) return null;
  return text;
}

List<Object?> _readList(Object? value) => value is List ? value : const [];

// ─────────────────────────────────────────────────────────────────────────────
// SessionStructure
// ─────────────────────────────────────────────────────────────────────────────

/// Struktur einer Intervall-Einheit. Alle Felder sind optional; unbekannte
/// Schlüssel bleiben in [extra] erhalten, damit Import/Export verlustfrei ist.
class SessionStructure {
  const SessionStructure({
    this.warmupSeconds,
    this.repetitions,
    this.workSeconds,
    this.recoverySeconds,
    this.recoveryAfterLast,
    this.cooldownSeconds,
    this.extra = const <String, dynamic>{},
  });

  static const Set<String> knownKeys = <String>{
    'warmup_seconds',
    'repetitions',
    'work_seconds',
    'recovery_seconds',
    'recovery_after_last',
    'cooldown_seconds',
  };

  final int? warmupSeconds;
  final int? repetitions;
  final int? workSeconds;
  final int? recoverySeconds;
  final bool? recoveryAfterLast;
  final int? cooldownSeconds;

  /// Unbekannte Schlüssel aus der Importdatei (unverändert übernommen).
  final Map<String, dynamic> extra;

  factory SessionStructure.fromJson(Map<String, dynamic> json) {
    final unknown = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!knownKeys.contains(entry.key)) unknown[entry.key] = entry.value;
    }
    return SessionStructure(
      warmupSeconds: _readInt(json['warmup_seconds']),
      repetitions: _readInt(json['repetitions']),
      workSeconds: _readInt(json['work_seconds']),
      recoverySeconds: _readInt(json['recovery_seconds']),
      recoveryAfterLast: _readBool(json['recovery_after_last']),
      cooldownSeconds: _readInt(json['cooldown_seconds']),
      extra: unknown,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'warmup_seconds': warmupSeconds,
    'repetitions': repetitions,
    'work_seconds': workSeconds,
    'recovery_seconds': recoverySeconds,
    'recovery_after_last': recoveryAfterLast,
    'cooldown_seconds': cooldownSeconds,
    ...extra,
  };

  /// Deutsche Kurzfassung, z. B.
  /// `10 min Einfahren · 3× 5 min / 3 min Pause · 19 min Ausfahren`.
  ///
  /// Reine Funktion ohne Seiteneffekte; liefert einen leeren String, wenn
  /// keine Struktur-Angaben vorhanden sind.
  String structureSummary() {
    final parts = <String>[];

    final warmup = warmupSeconds;
    if (warmup != null && warmup > 0) {
      parts.add('${formatMinutes(warmup)} min Einfahren');
    }

    String? main;
    final work = workSeconds;
    final reps = repetitions;
    if (work != null && work > 0) {
      final workLabel = '${formatMinutes(work)} min';
      main = (reps != null && reps > 0)
          ? '$reps× $workLabel'
          : '$workLabel Belastung';
    } else if (reps != null && reps > 0) {
      main = '$reps× Intervall';
    }
    if (main != null) {
      final recovery = recoverySeconds;
      if (recovery != null && recovery > 0) {
        main = '$main / ${formatMinutes(recovery)} min Pause';
      }
      parts.add(main);
    }

    final cooldown = cooldownSeconds;
    if (cooldown != null && cooldown > 0) {
      parts.add('${formatMinutes(cooldown)} min Ausfahren');
    }

    return parts.join(' · ');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session
// ─────────────────────────────────────────────────────────────────────────────

/// Geplante Einheit eines Plans. [date] ist ein reiner Kalendertag
/// (`YYYY-MM-DD`), alle Dauern sind Sekunden.
class Session {
  const Session({
    required this.id,
    required this.date,
    required this.sport,
    required this.type,
    this.optional = false,
    this.plannedDurationSeconds,
    this.instructions,
    this.structure,
  });

  final String id;
  final String date;
  final Sport sport;
  final String type;
  final bool optional;
  final int? plannedDurationSeconds;
  final String? instructions;
  final SessionStructure? structure;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: _readString(json['id']) ?? '',
    date: _readString(json['date']) ?? '',
    sport: sportFromWireName(_readString(json['sport'])) ?? Sport.other,
    type: _readString(json['type']) ?? '',
    optional: _readBool(json['optional']) ?? false,
    plannedDurationSeconds: _readInt(json['planned_duration_seconds']),
    instructions: _readString(json['instructions']),
    structure: json['structure'] is Map<String, dynamic>
        ? SessionStructure.fromJson(json['structure'] as Map<String, dynamic>)
        : null,
  );

  /// Tolerantes Lesen (Storage): liefert `null`, wenn Pflichtfelder fehlen
  /// oder ungültig sind – es wird nichts "repariert".
  static Session? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = _readString(raw['id']);
    if (id == null || id.trim().isEmpty) return null;
    final date = _readString(raw['date']);
    if (parseIsoDate(date) == null) return null;
    if (sportFromWireName(_readString(raw['sport'])) == null) return null;
    return Session.fromJson(raw);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'date': date,
    'sport': sport.wireName,
    'type': type,
    'optional': optional,
    'planned_duration_seconds': plannedDurationSeconds,
    'instructions': instructions,
    'structure': structure?.toJson(),
  };

  String get structureSummaryText => structure?.structureSummary() ?? '';
}

// ─────────────────────────────────────────────────────────────────────────────
// Plan
// ─────────────────────────────────────────────────────────────────────────────

/// Trainingsplan-Revision. Eindeutiger Schlüssel ist (id, revision).
class Plan {
  const Plan({
    required this.id,
    required this.revision,
    required this.title,
    this.sessions = const <Session>[],
  });

  final String id;
  final int revision;
  final String title;
  final List<Session> sessions;

  String get key => '$id@$revision';

  factory Plan.fromJson(Map<String, dynamic> json) {
    final sessions = <Session>[];
    for (final raw in _readList(json['sessions'])) {
      final session = Session.tryFromJson(raw);
      if (session != null) sessions.add(session);
    }
    return Plan(
      id: _readString(json['id']) ?? '',
      revision: _readInt(json['revision']) ?? 0,
      title: _readString(json['title']) ?? '',
      sessions: sessions,
    );
  }

  static Plan? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final plan = Plan.fromJson(raw);
    if (plan.id.trim().isEmpty || plan.revision < 1) return null;
    return plan;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'revision': revision,
    'title': title,
    'sessions': sessions.map((session) => session.toJson()).toList(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Activity
// ─────────────────────────────────────────────────────────────────────────────

/// Tatsächlich absolvierte (oder ausgelassene) Einheit.
///
/// [startedAt] ist ein ISO-String mit Offset und wird unverändert gespeichert,
/// damit der ursprüngliche Offset erhalten bleibt.
class Activity {
  const Activity({
    required this.id,
    required this.startedAt,
    required this.status,
    this.planId,
    this.planRevision,
    this.plannedSessionId,
    this.sport,
    this.elapsedDurationSeconds,
    this.movingDurationSeconds,
    this.distanceMeters,
    this.averageHeartRateBpm,
    this.averagePowerWatts,
    this.rpe,
    this.notes,
  });

  final String id;
  final String? planId;
  final int? planRevision;
  final String? plannedSessionId;

  /// Nur für ungeplante Einheiten gesetzt (String, damit unbekannte
  /// Sport-Werte verlustfrei erhalten bleiben).
  final String? sport;
  final String startedAt;
  final ActivityStatus status;
  final int? elapsedDurationSeconds;
  final int? movingDurationSeconds;
  final double? distanceMeters;
  final int? averageHeartRateBpm;
  final int? averagePowerWatts;
  final int? rpe;
  final String? notes;

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
    id: _readString(json['id']) ?? '',
    planId: _readString(json['plan_id']),
    planRevision: _readInt(json['plan_revision']),
    plannedSessionId: _readString(json['planned_session_id']),
    sport: _readString(json['sport']),
    startedAt: _readString(json['started_at']) ?? '',
    status:
        activityStatusFromWireName(_readString(json['status'])) ??
        ActivityStatus.completed,
    elapsedDurationSeconds: _readInt(json['elapsed_duration_seconds']),
    movingDurationSeconds: _readInt(json['moving_duration_seconds']),
    distanceMeters: _readDouble(json['distance_meters']),
    averageHeartRateBpm: _readInt(json['average_heart_rate_bpm']),
    averagePowerWatts: _readInt(json['average_power_watts']),
    rpe: _readInt(json['rpe']),
    notes: _readString(json['notes']),
  );

  static Activity? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = _readString(raw['id']);
    if (id == null || id.trim().isEmpty) return null;
    final startedAt = _readString(raw['started_at']);
    if (startedAt == null || DateTime.tryParse(startedAt) == null) return null;
    if (activityStatusFromWireName(_readString(raw['status'])) == null) {
      return null;
    }
    return Activity.fromJson(raw);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'plan_id': planId,
    'plan_revision': planRevision,
    'planned_session_id': plannedSessionId,
    'sport': sport,
    'started_at': startedAt,
    'status': status.wireName,
    'elapsed_duration_seconds': elapsedDurationSeconds,
    'moving_duration_seconds': movingDurationSeconds,
    'distance_meters': distanceMeters,
    'average_heart_rate_bpm': averageHeartRateBpm,
    'average_power_watts': averagePowerWatts,
    'rpe': rpe,
    'notes': notes,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// JournalEntry
// ─────────────────────────────────────────────────────────────────────────────

/// Tagebuch-Eintrag. [overallFeeling] ist bewusst ein einziger,
/// undifferenzierter Wert 0..100 ("wie ich mich insgesamt fühle"); `null`
/// bedeutet "nicht erfasst" und ist ausdrücklich NICHT 0.
///
/// Drei Zeitpunkte werden getrennt geführt:
/// * [timestamp] – erstellt (ändert sich nie),
/// * [updatedAt] – zuletzt geändert,
/// * [finalizedAt] – Tagesnotiz abgeschlossen (`null` = Entwurf).
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.timestamp,
    this.updatedAt,
    this.finalizedAt,
    this.finalizedAutomatically = false,
    this.overallFeeling,
    this.text,
  });

  final String id;

  /// Erstellungszeitpunkt (ISO-8601 mit lokalem Offset).
  final String timestamp;

  /// Zeitpunkt der letzten Änderung (ISO-8601 mit lokalem Offset).
  ///
  /// `null` nur bei Altbeständen aus Schema 1.0; dort gilt [timestamp] als
  /// letzte Änderung (siehe [lastChangedAt]).
  final String? updatedAt;

  /// Abschluss der Tagesnotiz; `null` = Entwurf.
  final String? finalizedAt;

  /// `true`, wenn die App den Abschluss gesetzt hat (Entwurf blieb offen und
  /// wurde rückwirkend um 23:59 des Eintragstags abgeschlossen).
  ///
  /// Manuelles Abschließen setzt das Feld auf `false`; Altbestände ohne Feld
  /// lesen `false`.
  final bool finalizedAutomatically;

  /// Gesamtbefinden 0..100 (0 = sehr schlecht, 100 = sehr gut).
  final int? overallFeeling;
  final String? text;

  /// Tagesnotiz ist abgeschlossen (kein Entwurf mehr).
  bool get isFinalized => finalizedAt != null;

  /// Abgeschlossen, aber nicht vom Athleten bestätigt (automatisch um 23:59).
  bool get isAutomaticallyFinalized => isFinalized && finalizedAutomatically;

  /// Letzte Änderung – bei Altbeständen ohne `updated_at` der Zeitstempel.
  String get lastChangedAt => updatedAt ?? timestamp;

  /// Zeitpunkt der letzten Änderung als lokale Zeit (oder `null`).
  DateTime? get lastChangedLocal => DateTime.tryParse(lastChangedAt)?.toLocal();

  /// Abschlusszeitpunkt als lokale Zeit (oder `null` = Entwurf).
  DateTime? get finalizedLocal =>
      finalizedAt == null ? null : DateTime.tryParse(finalizedAt!)?.toLocal();

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
    id: _readString(json['id']) ?? '',
    timestamp: _readString(json['timestamp']) ?? '',
    updatedAt: _readIsoTimestamp(json['updated_at']),
    finalizedAt: _readIsoTimestamp(json['finalized_at']),
    finalizedAutomatically: _readBool(json['finalized_automatically']) ?? false,
    overallFeeling: _readInt(json['overall_feeling']),
    text: _readString(json['text']),
  );

  static JournalEntry? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = _readString(raw['id']);
    if (id == null || id.trim().isEmpty) return null;
    final timestamp = _readString(raw['timestamp']);
    if (timestamp == null || DateTime.tryParse(timestamp) == null) return null;
    return JournalEntry.fromJson(raw);
  }

  /// Alle Felder werden immer geschrieben (fehlend = `null`,
  /// `finalized_automatically` immer als bool).
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'timestamp': timestamp,
    'updated_at': updatedAt,
    'finalized_at': finalizedAt,
    'finalized_automatically': finalizedAutomatically,
    'overall_feeling': overallFeeling,
    'text': text,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// AppState (das komplette Dokument)
// ─────────────────────────────────────────────────────────────────────────────

/// Das vollständige Dokument – genau das, was in Storage und Export landet.
class AppState {
  const AppState({
    this.schemaVersion = kSchemaVersion,
    this.exportedAt,
    this.timezone = kTimezone,
    this.plans = const <Plan>[],
    this.activities = const <Activity>[],
    this.journal = const <JournalEntry>[],
  });

  final String schemaVersion;
  final String? exportedAt;
  final String timezone;
  final List<Plan> plans;
  final List<Activity> activities;
  final List<JournalEntry> journal;

  factory AppState.empty() => const AppState();

  factory AppState.fromJson(Map<String, dynamic> json) {
    final plans = <Plan>[];
    for (final raw in _readList(json['plans'])) {
      final plan = Plan.tryFromJson(raw);
      if (plan != null) plans.add(plan);
    }
    final activities = <Activity>[];
    for (final raw in _readList(json['activities'])) {
      final activity = Activity.tryFromJson(raw);
      if (activity != null) activities.add(activity);
    }
    final journal = <JournalEntry>[];
    for (final raw in _readList(json['journal'])) {
      final entry = JournalEntry.tryFromJson(raw);
      if (entry != null) journal.add(entry);
    }
    return AppState(
      schemaVersion: _readString(json['schema_version']) ?? kSchemaVersion,
      exportedAt: _readString(json['exported_at']),
      timezone: _readString(json['timezone']) ?? kTimezone,
      plans: plans,
      activities: activities,
      journal: journal,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': schemaVersion,
    'exported_at': exportedAt,
    'timezone': timezone,
    'plans': plans.map((plan) => plan.toJson()).toList(),
    'activities': activities.map((activity) => activity.toJson()).toList(),
    'journal': journal.map((entry) => entry.toJson()).toList(),
  };

  AppState copyWith({
    String? schemaVersion,
    String? exportedAt,
    String? timezone,
    List<Plan>? plans,
    List<Activity>? activities,
    List<JournalEntry>? journal,
  }) => AppState(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    exportedAt: exportedAt ?? this.exportedAt,
    timezone: timezone ?? this.timezone,
    plans: plans ?? this.plans,
    activities: activities ?? this.activities,
    journal: journal ?? this.journal,
  );

  /// Jeweils die höchste Revision pro plan.id (für die Anzeige).
  List<Plan> get latestPlans {
    final byId = <String, Plan>{};
    for (final plan in plans) {
      final current = byId[plan.id];
      if (current == null || plan.revision > current.revision) {
        byId[plan.id] = plan;
      }
    }
    return byId.values.toList();
  }

  Plan? latestPlanFor(String planId) {
    Plan? latest;
    for (final plan in plans) {
      if (plan.id != planId) continue;
      if (latest == null || plan.revision > latest.revision) latest = plan;
    }
    return latest;
  }

  /// Höchste vorhandene Revision einer plan.id (0, wenn unbekannt).
  int latestRevisionFor(String planId) => latestPlanFor(planId)?.revision ?? 0;

  /// Alle Sitzungen des Kalendertags – nur aus der jeweils neuesten Revision.
  List<Session> sessionsOnDate(DateTime date) {
    final wanted = formatDateIso(date);
    final result = <Session>[];
    for (final plan in latestPlans) {
      for (final session in plan.sessions) {
        if (session.date == wanted) result.add(session);
      }
    }
    result.sort((a, b) {
      final bySport = a.sport.sortIndex.compareTo(b.sport.sortIndex);
      if (bySport != 0) return bySport;
      return a.type.compareTo(b.type);
    });
    return result;
  }
}
