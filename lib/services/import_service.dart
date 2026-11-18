import 'dart:convert';

import '../models/models.dart';
import '../utils/formats.dart';

/// Ergebnis eines Import-Parsings.
///
/// [errors] blockieren den Import, [warnings] nicht. Es wird nie etwas
/// "repariert": ungültige Einträge werden gemeldet, nicht stillschweigend
/// umgeschrieben.
class ImportResult {
  const ImportResult({
    this.plans = const <Plan>[],
    this.activities = const <Activity>[],
    this.journal = const <JournalEntry>[],
    this.errors = const <String>[],
    this.warnings = const <String>[],
    this.ignoredUnknownFields = 0,
    this.schemaVersion,
  });

  final List<Plan> plans;
  final List<Activity> activities;
  final List<JournalEntry> journal;
  final List<String> errors;
  final List<String> warnings;

  /// Anzahl unbekannter Felder, die beim Import verworfen wurden
  /// (unbekannte Struktur-Felder bleiben in `structure.extra` erhalten und
  /// zählen hier nicht mit).
  final int ignoredUnknownFields;

  /// `schema_version` aus der Datei, falls vorhanden.
  final String? schemaVersion;

  bool get hasErrors => errors.isNotEmpty;

  int get sessionCount =>
      plans.fold<int>(0, (sum, plan) => sum + plan.sessions.length);
}

class _Ctx {
  final List<String> errors = <String>[];
  final List<String> warnings = <String>[];
  int ignored = 0;

  void error(String message) => errors.add(message);
  void warn(String message) => warnings.add(message);
}

const Set<String> _rootKeys = <String>{
  'schema_version',
  'exported_at',
  'timezone',
  'plans',
  'activities',
  'journal',
};

const Set<String> _planKeys = <String>{'id', 'revision', 'title', 'sessions'};

const Set<String> _sessionKeys = <String>{
  'id',
  'date',
  'sport',
  'type',
  'optional',
  'planned_duration_seconds',
  'instructions',
  'structure',
};

const Set<String> _activityKeys = <String>{
  'id',
  'plan_id',
  'plan_revision',
  'planned_session_id',
  'sport',
  'started_at',
  'status',
  'elapsed_duration_seconds',
  'moving_duration_seconds',
  'distance_meters',
  'average_heart_rate_bpm',
  'average_power_watts',
  'rpe',
  'notes',
};

const Set<String> _journalKeys = <String>{
  'id',
  'timestamp',
  'updated_at',
  'finalized_at',
  'overall_feeling',
  'text',
};

/// Parst und validiert eine Import-Datei (Plan-Datei oder vollständiger Export).
class ImportService {
  const ImportService();

  static const int _twoYearsInDays = 731;

  /// [now] ist injizierbar, damit die "> 2 Jahre"-Hinweise testbar sind.
  ImportResult parse(String jsonText, {DateTime? now}) {
    final ctx = _Ctx();
    final reference = now ?? DateTime.now();

    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (error) {
      return ImportResult(
        errors: <String>['Ungültiges JSON: ${error.message}'],
      );
    }
    if (decoded is! Map<String, dynamic>) {
      return const ImportResult(
        errors: <String>['Das Dokument muss ein JSON-Objekt sein.'],
      );
    }

    _countUnknownFields(decoded, _rootKeys, 'Dokument', ctx);

    final schemaVersion = decoded['schema_version'];
    if (schemaVersion != null) {
      if (schemaVersion is! String) {
        ctx.error('"schema_version" muss ein Text sein.');
      } else if (!kAcceptedSchemaVersions.contains(schemaVersion)) {
        ctx.warn(
          'schema_version "$schemaVersion" ist unbekannt '
          '(erwartet: "$kSchemaVersion", akzeptiert: '
          '${kAcceptedSchemaVersions.join(', ')}).',
        );
      }
    }

    final timezone = decoded['timezone'];
    if (timezone != null && timezone is! String) {
      ctx.error('"timezone" muss ein Text sein.');
    } else if (timezone is String && timezone != kTimezone) {
      ctx.warn(
        'timezone "$timezone" weicht von "$kTimezone" ab; '
        'Zeitstempel werden unverändert übernommen.',
      );
    }

    final plans = _parsePlans(decoded['plans'], ctx, reference);
    final activities = _parseActivities(decoded['activities'], ctx, reference);
    final journal = _parseJournal(decoded['journal'], ctx, reference);

    if (plans.isEmpty) {
      ctx.warn('Die Datei enthält keine Pläne.');
    }

    return ImportResult(
      plans: plans,
      activities: activities,
      journal: journal,
      errors: ctx.errors,
      warnings: ctx.warnings,
      ignoredUnknownFields: ctx.ignored,
      schemaVersion: schemaVersion is String ? schemaVersion : null,
    );
  }

  // ─── Pläne ─────────────────────────────────────────────────────────────────

  List<Plan> _parsePlans(Object? raw, _Ctx ctx, DateTime now) {
    final plans = <Plan>[];
    if (raw == null) return plans;
    if (raw is! List) {
      ctx.error('"plans" muss eine Liste sein.');
      return plans;
    }

    final seenPlanRevisions = <String>{};

    for (var index = 0; index < raw.length; index++) {
      final entry = raw[index];
      final where = 'Plan ${index + 1}';
      if (entry is! Map<String, dynamic>) {
        ctx.error('$where: Eintrag ist kein JSON-Objekt.');
        continue;
      }
      _countUnknownFields(entry, _planKeys, where, ctx);

      final rawId = entry['id'];
      final id = rawId is String ? rawId.trim() : null;
      if (id == null || id.isEmpty) {
        ctx.error('$where: id fehlt oder ist leer.');
      }

      var valid = id != null && id.isNotEmpty;

      final rawRevision = entry['revision'];
      int? revision;
      if (rawRevision is! int) {
        ctx.error('$where: revision muss eine ganze Zahl ≥ 1 sein.');
        valid = false;
      } else if (rawRevision < 1) {
        ctx.error('$where: revision muss ≥ 1 sein (war $rawRevision).');
        valid = false;
      } else {
        revision = rawRevision;
      }

      final rawTitle = entry['title'];
      if (rawTitle is! String) {
        ctx.error('$where: title fehlt oder ist kein Text.');
        valid = false;
      }

      if (id != null && revision != null) {
        final key = '$id@$revision';
        if (!seenPlanRevisions.add(key)) {
          ctx.error(
            'Doppelte Plan-Revision: "$id" Revision $revision kommt in der '
            'Datei mehrfach vor.',
          );
          valid = false;
        }
      }

      final sessions = <Session>[];
      final rawSessions = entry['sessions'];
      if (rawSessions == null) {
        ctx.warn('$where: enthält keine Sitzungen.');
      } else if (rawSessions is! List) {
        ctx.error('$where: sessions muss eine Liste sein.');
        valid = false;
      } else {
        final sessionIds = <String>{};
        for (var i = 0; i < rawSessions.length; i++) {
          final rawSession = rawSessions[i];
          final sessionWhere = '$where, Sitzung ${i + 1}';
          if (rawSession is! Map<String, dynamic>) {
            ctx.error('$sessionWhere: Eintrag ist kein JSON-Objekt.');
            valid = false;
            continue;
          }
          final session = _parseSession(
            rawSession,
            sessionWhere,
            ctx,
            now,
            sessionIds,
          );
          if (session == null) {
            valid = false;
          } else {
            sessions.add(session);
          }
        }
      }

      if (valid) {
        plans.add(
          Plan(
            id: id!,
            revision: revision!,
            title: rawTitle as String,
            sessions: sessions,
          ),
        );
      }
    }

    return plans;
  }

  Session? _parseSession(
    Map<String, dynamic> json,
    String where,
    _Ctx ctx,
    DateTime now,
    Set<String> seenIds,
  ) {
    _countUnknownFields(json, _sessionKeys, where, ctx);
    var valid = true;

    final rawId = json['id'];
    final id = rawId is String ? rawId.trim() : null;
    if (id == null || id.isEmpty) {
      ctx.error('$where: id fehlt oder ist leer.');
      valid = false;
    } else if (!seenIds.add(id)) {
      ctx.error('$where: doppelte session.id "$id".');
      valid = false;
    }

    final rawDate = json['date'];
    DateTime? date;
    if (rawDate is! String) {
      ctx.error('$where: date fehlt.');
      valid = false;
    } else {
      date = parseIsoDate(rawDate);
      if (date == null) {
        ctx.error(
          '$where: date "$rawDate" ist kein gültiges Datum im Format '
          'YYYY-MM-DD.',
        );
        valid = false;
      } else if (_isFarFromNow(date, now)) {
        ctx.warn('$where: Datum $rawDate liegt mehr als 2 Jahre entfernt.');
      }
    }

    final rawSport = json['sport'];
    final sport = rawSport is String ? sportFromWireName(rawSport) : null;
    if (rawSport is! String) {
      ctx.error('$where: sport fehlt.');
      valid = false;
    } else if (sport == null) {
      ctx.error(
        '$where: sport "$rawSport" ist unbekannt '
        '(erlaubt: swim, bike, run, strength, other).',
      );
      valid = false;
    }

    final rawType = json['type'];
    var type = '';
    if (rawType == null) {
      ctx.warn('$where: type fehlt.');
    } else if (rawType is! String) {
      ctx.error('$where: type muss ein Text sein.');
      valid = false;
    } else {
      type = rawType;
    }

    var optional = false;
    final rawOptional = json['optional'];
    if (rawOptional != null) {
      if (rawOptional is! bool) {
        ctx.error('$where: optional muss true oder false sein.');
        valid = false;
      } else {
        optional = rawOptional;
      }
    }

    final plannedDuration = _intField(
      json,
      'planned_duration_seconds',
      where,
      ctx,
      nonNegative: true,
    );
    if (plannedDuration == null && json['planned_duration_seconds'] != null) {
      valid = false;
    }

    String? instructions;
    final rawInstructions = json['instructions'];
    if (rawInstructions != null) {
      if (rawInstructions is! String) {
        ctx.error('$where: instructions muss ein Text sein.');
        valid = false;
      } else {
        instructions = rawInstructions;
      }
    }

    SessionStructure? structure;
    final rawStructure = json['structure'];
    if (rawStructure != null) {
      if (rawStructure is! Map<String, dynamic>) {
        ctx.error('$where: structure muss ein JSON-Objekt sein.');
        valid = false;
      } else {
        structure = _parseStructure(rawStructure, '$where, structure', ctx);
        if (structure == null) valid = false;
      }
    }

    if (!valid) return null;
    return Session(
      id: id!,
      date: formatDateIso(date!),
      sport: sport!,
      type: type,
      optional: optional,
      plannedDurationSeconds: plannedDuration,
      instructions: instructions,
      structure: structure,
    );
  }

  SessionStructure? _parseStructure(
    Map<String, dynamic> json,
    String where,
    _Ctx ctx,
  ) {
    var valid = true;
    for (final key in json.keys) {
      if (SessionStructure.knownKeys.contains(key)) continue;
      ctx.warn('$where: unbekanntes Feld "$key" wird unverändert erhalten.');
    }

    int? readSeconds(String key) {
      final raw = json[key];
      if (raw == null) return null;
      if (raw is! int) {
        ctx.error('$where: $key muss eine ganze Zahl sein.');
        valid = false;
        return null;
      }
      if (raw < 0) {
        ctx.error('$where: $key darf nicht negativ sein.');
        valid = false;
        return null;
      }
      return raw;
    }

    final warmup = readSeconds('warmup_seconds');
    final repetitions = readSeconds('repetitions');
    final work = readSeconds('work_seconds');
    final recovery = readSeconds('recovery_seconds');
    final cooldown = readSeconds('cooldown_seconds');

    bool? recoveryAfterLast;
    final rawRecoveryAfterLast = json['recovery_after_last'];
    if (rawRecoveryAfterLast != null) {
      if (rawRecoveryAfterLast is! bool) {
        ctx.error('$where: recovery_after_last muss true oder false sein.');
        valid = false;
      } else {
        recoveryAfterLast = rawRecoveryAfterLast;
      }
    }

    if (!valid) return null;
    return SessionStructure(
      warmupSeconds: warmup,
      repetitions: repetitions,
      workSeconds: work,
      recoverySeconds: recovery,
      recoveryAfterLast: recoveryAfterLast,
      cooldownSeconds: cooldown,
      extra: <String, dynamic>{
        for (final entry in json.entries)
          if (!SessionStructure.knownKeys.contains(entry.key))
            entry.key: entry.value,
      },
    );
  }

  // ─── Activities ────────────────────────────────────────────────────────────

  List<Activity> _parseActivities(Object? raw, _Ctx ctx, DateTime now) {
    final activities = <Activity>[];
    if (raw == null) return activities;
    if (raw is! List) {
      ctx.error('"activities" muss eine Liste sein.');
      return activities;
    }

    final seenIds = <String>{};
    for (var index = 0; index < raw.length; index++) {
      final where = 'Aktivität ${index + 1}';
      final entry = raw[index];
      if (entry is! Map<String, dynamic>) {
        ctx.error('$where: Eintrag ist kein JSON-Objekt.');
        continue;
      }
      _countUnknownFields(entry, _activityKeys, where, ctx);

      var valid = true;

      final rawId = entry['id'];
      final id = rawId is String ? rawId.trim() : null;
      if (id == null || id.isEmpty) {
        ctx.error('$where: id fehlt oder ist leer.');
        valid = false;
      } else if (!seenIds.add(id)) {
        ctx.warn('$where: doppelte Aktivitäts-ID "$id" in der Datei.');
      }

      final rawStartedAt = entry['started_at'];
      final startedAt = rawStartedAt is String
          ? DateTime.tryParse(rawStartedAt)
          : null;
      if (rawStartedAt is! String) {
        ctx.error('$where: started_at fehlt.');
        valid = false;
      } else if (startedAt == null) {
        ctx.error(
          '$where: started_at "$rawStartedAt" ist kein ISO-Zeitstempel.',
        );
        valid = false;
      } else if (_isFarFromNow(startedAt.toLocal(), now)) {
        ctx.warn('$where: started_at liegt mehr als 2 Jahre entfernt.');
      }

      final rawStatus = entry['status'];
      final status = rawStatus is String
          ? activityStatusFromWireName(rawStatus)
          : null;
      if (rawStatus is! String) {
        ctx.error('$where: status fehlt.');
        valid = false;
      } else if (status == null) {
        ctx.error(
          '$where: status "$rawStatus" ist unbekannt '
          '(erlaubt: completed, partial, skipped).',
        );
        valid = false;
      }

      final rawSport = entry['sport'];
      if (rawSport != null && rawSport is! String) {
        ctx.error('$where: sport muss ein Text sein.');
        valid = false;
      } else if (rawSport is String && sportFromWireName(rawSport) == null) {
        ctx.warn(
          '$where: unbekannter sport-Wert "$rawSport" '
          '(wird unverändert übernommen).',
        );
      }

      for (final key in <String>['plan_id', 'planned_session_id', 'notes']) {
        if (entry[key] != null && entry[key] is! String) {
          ctx.error('$where: $key muss ein Text sein.');
          valid = false;
        }
      }

      final planRevision = _intField(
        entry,
        'plan_revision',
        where,
        ctx,
        nonNegative: false,
        min: 1,
      );
      if (planRevision == null && entry['plan_revision'] != null) {
        valid = false;
      }

      final elapsed = _intField(
        entry,
        'elapsed_duration_seconds',
        where,
        ctx,
        nonNegative: true,
      );
      if (elapsed == null && entry['elapsed_duration_seconds'] != null) {
        valid = false;
      }
      final moving = _intField(
        entry,
        'moving_duration_seconds',
        where,
        ctx,
        nonNegative: true,
      );
      if (moving == null && entry['moving_duration_seconds'] != null) {
        valid = false;
      }
      final heartRate = _intField(
        entry,
        'average_heart_rate_bpm',
        where,
        ctx,
        nonNegative: true,
      );
      if (heartRate == null && entry['average_heart_rate_bpm'] != null) {
        valid = false;
      }
      final power = _intField(
        entry,
        'average_power_watts',
        where,
        ctx,
        nonNegative: true,
      );
      if (power == null && entry['average_power_watts'] != null) {
        valid = false;
      }

      final rpe = _intField(entry, 'rpe', where, ctx);
      if (rpe != null && (rpe < 1 || rpe > 10)) {
        ctx.error('$where: rpe muss zwischen 1 und 10 liegen (war $rpe).');
        valid = false;
      } else if (rpe == null && entry['rpe'] != null) {
        valid = false;
      }

      double? distance;
      final rawDistance = entry['distance_meters'];
      if (rawDistance != null) {
        if (rawDistance is! num) {
          ctx.error('$where: distance_meters muss eine Zahl sein.');
          valid = false;
        } else if (rawDistance < 0) {
          ctx.error('$where: distance_meters darf nicht negativ sein.');
          valid = false;
        } else {
          distance = rawDistance.toDouble();
        }
      }

      if (!valid) continue;
      activities.add(
        Activity(
          id: id!,
          planId: entry['plan_id'] as String?,
          planRevision: planRevision,
          plannedSessionId: entry['planned_session_id'] as String?,
          sport: rawSport as String?,
          startedAt: rawStartedAt,
          status: status!,
          elapsedDurationSeconds: elapsed,
          movingDurationSeconds: moving,
          distanceMeters: distance,
          averageHeartRateBpm: heartRate,
          averagePowerWatts: power,
          rpe: rpe,
          notes: entry['notes'] as String?,
        ),
      );
    }
    return activities;
  }

  // ─── Journal ───────────────────────────────────────────────────────────────

  List<JournalEntry> _parseJournal(Object? raw, _Ctx ctx, DateTime now) {
    final entries = <JournalEntry>[];
    if (raw == null) return entries;
    if (raw is! List) {
      ctx.error('"journal" muss eine Liste sein.');
      return entries;
    }

    final seenIds = <String>{};
    for (var index = 0; index < raw.length; index++) {
      final where = 'Tagebucheintrag ${index + 1}';
      final entry = raw[index];
      if (entry is! Map<String, dynamic>) {
        ctx.error('$where: Eintrag ist kein JSON-Objekt.');
        continue;
      }
      _countUnknownFields(entry, _journalKeys, where, ctx);

      var valid = true;

      final rawId = entry['id'];
      final id = rawId is String ? rawId.trim() : null;
      if (id == null || id.isEmpty) {
        ctx.error('$where: id fehlt oder ist leer.');
        valid = false;
      } else if (!seenIds.add(id)) {
        ctx.warn('$where: doppelte Tagebuch-ID "$id" in der Datei.');
      }

      final rawTimestamp = entry['timestamp'];
      final timestamp = rawTimestamp is String
          ? DateTime.tryParse(rawTimestamp)
          : null;
      if (rawTimestamp is! String) {
        ctx.error('$where: timestamp fehlt.');
        valid = false;
      } else if (timestamp == null) {
        ctx.error(
          '$where: timestamp "$rawTimestamp" ist kein ISO-Zeitstempel.',
        );
        valid = false;
      } else if (_isFarFromNow(timestamp.toLocal(), now)) {
        ctx.warn('$where: timestamp liegt mehr als 2 Jahre entfernt.');
      }

      // Sekundäre Zeitstempel: gleiche ISO-Prüfung wie timestamp, dürfen aber
      // nicht vor der Erstellung liegen (Altbestand aus 1.0 hat beide nicht).
      String? readSecondaryTimestamp(String key, String label) {
        final rawValue = entry[key];
        if (rawValue == null) return null;
        if (rawValue is! String) {
          ctx.error('$where: $key muss ein ISO-Zeitstempel sein.');
          valid = false;
          return null;
        }
        final parsed = DateTime.tryParse(rawValue);
        if (parsed == null) {
          ctx.error('$where: $key "$rawValue" ist kein ISO-Zeitstempel.');
          valid = false;
          return null;
        }
        if (timestamp != null && parsed.isBefore(timestamp)) {
          ctx.error('$where: $key ($label) darf nicht vor timestamp liegen.');
          valid = false;
          return null;
        }
        return rawValue;
      }

      final updatedAt = readSecondaryTimestamp(
        'updated_at',
        'zuletzt geändert',
      );
      final finalizedAt = readSecondaryTimestamp(
        'finalized_at',
        'abgeschlossen',
      );

      int? overallFeeling;
      final rawFeeling = entry['overall_feeling'];
      if (rawFeeling != null) {
        if (rawFeeling is! int) {
          ctx.error(
            '$where: overall_feeling muss eine ganze Zahl zwischen 0 und 100 '
            'sein.',
          );
          valid = false;
        } else if (rawFeeling < 0 || rawFeeling > 100) {
          ctx.error(
            '$where: overall_feeling muss zwischen 0 und 100 liegen '
            '(war $rawFeeling).',
          );
          valid = false;
        } else {
          overallFeeling = rawFeeling;
        }
      }

      String? text;
      final rawText = entry['text'];
      if (rawText != null) {
        if (rawText is! String) {
          ctx.error('$where: text muss ein Text sein.');
          valid = false;
        } else {
          text = rawText;
        }
      }

      if (!valid) continue;
      entries.add(
        JournalEntry(
          id: id!,
          timestamp: rawTimestamp,
          updatedAt: updatedAt,
          finalizedAt: finalizedAt,
          overallFeeling: overallFeeling,
          text: text,
        ),
      );
    }
    return entries;
  }

  // ─── Helfer ────────────────────────────────────────────────────────────────

  void _countUnknownFields(
    Map<String, dynamic> json,
    Set<String> known,
    String where,
    _Ctx ctx,
  ) {
    for (final key in json.keys) {
      if (known.contains(key)) continue;
      ctx.ignored++;
      ctx.warn('$where: unbekanntes Feld "$key" wird ignoriert.');
    }
  }

  int? _intField(
    Map<String, dynamic> json,
    String key,
    String where,
    _Ctx ctx, {
    bool nonNegative = false,
    int? min,
  }) {
    final raw = json[key];
    if (raw == null) return null;
    if (raw is! int) {
      ctx.error('$where: $key muss eine ganze Zahl sein.');
      return null;
    }
    if (nonNegative && raw < 0) {
      ctx.error('$where: $key darf nicht negativ sein (war $raw).');
      return null;
    }
    if (min != null && raw < min) {
      ctx.error('$where: $key muss ≥ $min sein (war $raw).');
      return null;
    }
    return raw;
  }

  bool _isFarFromNow(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    return day.difference(today).inDays.abs() > _twoYearsInDays;
  }
}
