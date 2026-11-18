import 'dart:collection';
import 'dart:convert';

import '../models/models.dart';
import '../utils/formats.dart';

/// Reine Export-Funktionen (kein IO, kein UI) für JSON und Markdown.
class ExportService {
  const ExportService();

  // ─── JSON ──────────────────────────────────────────────────────────────────

  /// Baut das vollständige Export-Dokument.
  ///
  /// [from]/[to] filtern (inklusiv, lokale Zeit) ausschließlich `activities`
  /// und `journal`. Pläne sind immer vollständig enthalten – inklusive aller
  /// Revisionen –, weil sie den Kontext für den Coach liefern.
  String buildJson(
    AppState state, {
    DateTime? from,
    DateTime? to,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final document = <String, dynamic>{
      'schema_version': kSchemaVersion,
      'exported_at': isoWithOffset(reference),
      'timezone': kTimezone,
      'plans': state.plans.map((plan) => plan.toJson()).toList(),
      'activities': state.activities
          .where((activity) => _inRangeIso(activity.startedAt, from, to))
          .map((activity) => activity.toJson())
          .toList(),
      'journal': state.journal
          .where((entry) => _inRangeIso(entry.timestamp, from, to))
          .map((entry) => entry.toJson())
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  String fileNameJson(DateTime now) =>
      'tri-log-export-${formatDateIso(now)}.json';

  String fileNameMarkdown(DateTime now) =>
      'tri-log-export-${formatDateIso(now)}.md';

  // ─── Markdown ──────────────────────────────────────────────────────────────

  /// Kompakte Zusammenfassung für einen AI-Coach.
  String buildMarkdown(
    AppState state, {
    DateTime? from,
    DateTime? to,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();

    final plannedSessions = <String, List<Session>>{};
    for (final plan in state.latestPlans) {
      for (final session in plan.sessions) {
        if (!_inRangeDate(session.date, from, to)) continue;
        plannedSessions
            .putIfAbsent(session.date, () => <Session>[])
            .add(session);
      }
    }
    for (final sessions in plannedSessions.values) {
      sessions.sort((a, b) => a.sport.sortIndex.compareTo(b.sport.sortIndex));
    }

    final activitiesByDate = <String, List<Activity>>{};
    for (final activity in state.activities) {
      final local = DateTime.tryParse(activity.startedAt)?.toLocal();
      if (local == null) continue;
      final date = formatDateIso(local);
      if (!_inRangeDate(date, from, to)) continue;
      activitiesByDate.putIfAbsent(date, () => <Activity>[]).add(activity);
    }

    final journalByDate = <String, List<JournalEntry>>{};
    for (final entry in state.journal) {
      final local = DateTime.tryParse(entry.timestamp)?.toLocal();
      if (local == null) continue;
      final date = formatDateIso(local);
      if (!_inRangeDate(date, from, to)) continue;
      journalByDate.putIfAbsent(date, () => <JournalEntry>[]).add(entry);
    }

    final days = SplayTreeSet<String>()
      ..addAll(plannedSessions.keys)
      ..addAll(activitiesByDate.keys)
      ..addAll(journalByDate.keys);

    final buffer = StringBuffer()
      ..writeln('# Tri-Log Export')
      ..writeln()
      ..writeln('Zeitraum: ${_rangeLabel(from, to)}')
      ..writeln('Exportiert: ${formatDateTimeGerman(reference)} ($kTimezone)')
      ..writeln();

    if (days.isEmpty) {
      buffer.writeln('Keine Einheiten im Zeitraum.');
      return buffer.toString();
    }

    DateTime? currentWeek;
    for (final dayIso in days) {
      final day = parseIsoDate(dayIso);
      if (day == null) continue;
      final weekStart = startOfWeek(day);
      if (currentWeek == null || weekStart != currentWeek) {
        currentWeek = weekStart;
        buffer
          ..writeln(
            '## Woche ${formatDateNumeric(weekStart)} – '
            '${formatDateNumeric(weekStart.add(const Duration(days: 6)))} '
            '(KW ${isoWeekNumber(day)})',
          )
          ..writeln();
      }

      buffer
        ..writeln('### ${formatDateGerman(day)}')
        ..writeln();

      buffer.writeln('**Geplant**');
      final sessions = plannedSessions[dayIso] ?? const <Session>[];
      if (sessions.isEmpty) {
        buffer.writeln('- –');
      } else {
        for (final session in sessions) {
          buffer.writeln('- ${_plannedLine(session)}');
        }
      }
      buffer.writeln();

      buffer.writeln('**Ist**');
      final activities = activitiesByDate[dayIso] ?? const <Activity>[];
      if (activities.isEmpty) {
        buffer.writeln('- –');
      } else {
        for (final activity in activities) {
          buffer.writeln('- ${_activityLine(activity, state, sessions)}');
        }
      }
      buffer.writeln();

      buffer.writeln('**Tagebuch**');
      final entries = journalByDate[dayIso] ?? const <JournalEntry>[];
      if (entries.isEmpty) {
        buffer.writeln('- –');
      } else {
        entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        for (final entry in entries) {
          buffer.writeln('- ${_journalLine(entry)}');
        }
      }
      buffer.writeln();
    }

    return '${buffer.toString().trimRight()}\n';
  }

  // ─── Zeilen-Bausteine ──────────────────────────────────────────────────────

  String _plannedLine(Session session) {
    final parts = <String>[
      session.sport.labelDe,
      if (session.type.trim().isNotEmpty) session.type,
      formatMinutesWithUnit(session.plannedDurationSeconds),
      if (session.optional) 'optional',
    ];
    final summary = session.structureSummaryText;
    if (summary.isNotEmpty) parts.add('Struktur: $summary');
    return parts.join(' · ');
  }

  String _activityLine(
    Activity activity,
    AppState state,
    List<Session> plannedOfDay,
  ) {
    Session? linked;
    if (activity.plannedSessionId != null) {
      for (final session in plannedOfDay) {
        if (session.id == activity.plannedSessionId) {
          linked = session;
          break;
        }
      }
      if (linked == null) {
        // Sitzung kann aus einer älteren Revision stammen: dort weitersuchen.
        final plans = state.plans.where(
          (plan) =>
              plan.id == activity.planId &&
              (activity.planRevision == null ||
                  plan.revision == activity.planRevision),
        );
        for (final plan in plans) {
          for (final session in plan.sessions) {
            if (session.id == activity.plannedSessionId) {
              linked = session;
              break;
            }
          }
          if (linked != null) break;
        }
      }
    }

    final sport = linked?.sport ?? sportFromWireName(activity.sport);
    final sportLabel =
        sport?.labelDe ??
        (activity.sport != null && activity.sport!.trim().isNotEmpty
            ? activity.sport!
            : 'Ungeplant');

    final type = linked?.type ?? '';
    final parts = <String>[
      sportLabel,
      if (type.trim().isNotEmpty) type,
      activity.status.labelDe,
    ];
    var hasDetails = false;

    final duration =
        activity.elapsedDurationSeconds ?? activity.movingDurationSeconds;
    if (duration != null) {
      parts.add(formatMinutesWithUnit(duration));
      hasDetails = true;
    }
    if (activity.distanceMeters != null) {
      parts.add(formatDistanceKm(activity.distanceMeters));
      hasDetails = true;
    }
    if (activity.averageHeartRateBpm != null) {
      parts.add('Ø HF ${activity.averageHeartRateBpm} bpm');
      hasDetails = true;
    }
    if (activity.averagePowerWatts != null) {
      parts.add('Ø ${activity.averagePowerWatts} W');
      hasDetails = true;
    }
    if (activity.rpe != null) {
      parts.add('RPE ${activity.rpe}');
      hasDetails = true;
    }

    final deviation = _deviation(activity, linked);
    if (deviation != null) {
      parts.add('Abweichung $deviation');
      hasDetails = true;
    }

    if (activity.notes != null && activity.notes!.trim().isNotEmpty) {
      parts.add('Notiz: „${activity.notes!.trim()}“');
      hasDetails = true;
    }
    if (!hasDetails) parts.add('–');

    return parts.join(' · ');
  }

  /// Differenz Ist − Plan in Minuten, z. B. `+2 min`, `−5 min`, `±0 min`.
  String? _deviation(Activity activity, Session? linked) {
    final planned = linked?.plannedDurationSeconds;
    if (planned == null) return null;
    final actual =
        activity.elapsedDurationSeconds ?? activity.movingDurationSeconds;
    if (actual == null) return null;
    final diffSeconds = actual - planned;
    if (diffSeconds == 0) return '±0 min';
    final sign = diffSeconds > 0 ? '+' : '−';
    return '$sign${formatMinutes(diffSeconds.abs())} min';
  }

  /// Eine Tagebuchzeile mit Entwurfs-/Abschluss-Kennzeichnung.
  ///
  /// `… · Gesamtbefinden: 60 % · Entwurf` bzw.
  /// `… · Gesamtbefinden: 60 % · abgeschlossen 21:14` (manuell) bzw.
  /// `… · Gesamtbefinden: 60 % · abgeschlossen 23:59 (automatisch)` (von der
  /// App gesetzt, weil der Entwurf offen blieb)
  /// und – wenn sich die letzte Änderung von der Erstellung unterscheidet –
  /// `(erstellt 07:12, zuletzt geändert 18:40)`.
  String _journalLine(JournalEntry entry) {
    final created = DateTime.tryParse(entry.timestamp)?.toLocal();
    final changed = entry.lastChangedLocal;
    final finalized = entry.finalizedLocal;

    final parts = <String>[
      if (created != null) formatTime(created),
      'Gesamtbefinden: ${formatPercent(entry.overallFeeling)}',
      if (finalized == null)
        'Entwurf'
      else
        'abgeschlossen ${formatTime(finalized)}'
            '${entry.finalizedAutomatically ? ' (automatisch)' : ''}',
    ];

    if (created != null &&
        changed != null &&
        changed.isAfter(created) &&
        !_sameMinute(created, changed)) {
      final changedLabel = _sameDay(created, changed)
          ? 'zuletzt geändert ${formatTime(changed)}'
          : 'zuletzt geändert ${formatDateNumeric(changed)}, '
                '${formatTime(changed)}';
      parts.add('(erstellt ${formatTime(created)}, $changedLabel)');
    }

    final text = entry.text?.trim();
    if (text != null && text.isNotEmpty) parts.add(text);
    return parts.join(' · ');
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _sameMinute(DateTime a, DateTime b) =>
      _sameDay(a, b) && a.hour == b.hour && a.minute == b.minute;

  // ─── Zeitraum-Helfer ───────────────────────────────────────────────────────

  String _rangeLabel(DateTime? from, DateTime? to) {
    if (from == null && to == null) return 'alle Daten';
    if (from != null && to != null) {
      return '${formatDateNumeric(from)} – ${formatDateNumeric(to)}';
    }
    if (from != null) return 'ab ${formatDateNumeric(from)}';
    return 'bis ${formatDateNumeric(to!)}';
  }

  /// Prüft einen ISO-Zeitstempel gegen den inklusiven Zeitraum (lokale Zeit).
  bool _inRangeIso(String iso, DateTime? from, DateTime? to) {
    if (from == null && to == null) return true;
    final local = DateTime.tryParse(iso)?.toLocal();
    // Unlesbare Zeitstempel werden nicht weggefiltert (nichts verschweigen).
    if (local == null) return true;
    return _inRangeDate(formatDateIso(local), from, to);
  }

  /// Prüft einen Kalendertag (`YYYY-MM-DD`) gegen den inklusiven Zeitraum.
  bool _inRangeDate(String date, DateTime? from, DateTime? to) {
    if (from == null && to == null) return true;
    final fromIso = from == null ? null : formatDateIso(from);
    final toIso = to == null ? null : formatDateIso(to);
    if (fromIso != null && date.compareTo(fromIso) < 0) return false;
    if (toIso != null && date.compareTo(toIso) > 0) return false;
    return true;
  }
}
