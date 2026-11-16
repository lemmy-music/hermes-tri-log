import '../models/models.dart';
import '../utils/formats.dart';

/// Reine, seiteneffektfreie Helfer für den Verlaufs-Tab (geplant vs. tatsächlich)
/// und für die Gruppierung des Tagebuchs.
///
/// Bewusst ohne UI- und ohne Repository-Abhängigkeit: alles lässt sich damit
/// unit-testen. Die Ableitung der Tage mit Inhalt passiert genau einmal pro
/// Aufbau (Maps statt quadratischer Suche pro Zeile).

/// Wählbarer Zeitraum im Verlauf.
enum HistoryRange { last7Days, last30Days, all }

extension HistoryRangeX on HistoryRange {
  String get labelDe => switch (this) {
    HistoryRange.last7Days => '7 Tage',
    HistoryRange.last30Days => '30 Tage',
    HistoryRange.all => 'Alles',
  };

  /// Erster Tag des Zeitraums (00:00) oder `null` für „Alles“.
  DateTime? startDate(DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    return switch (this) {
      HistoryRange.last7Days => DateTime(day.year, day.month, day.day - 6),
      HistoryRange.last30Days => DateTime(day.year, day.month, day.day - 29),
      HistoryRange.all => null,
    };
  }

  /// Letzter Tag des Zeitraums (00:00) oder `null` für „Alles“.
  DateTime? endDate(DateTime today) {
    if (this == HistoryRange.all) return null;
    return DateTime(today.year, today.month, today.day);
  }
}

/// Text für eine geplante Einheit ohne jede Aufzeichnung. Ausdrücklich
/// UNBEKANNT – nicht „ausgelassen“ (das ist ein eigener Status).
const String kNoRecordingLabelDe = 'keine Aufzeichnung';

/// Eine geplante Sitzung inkl. der (optionalen) zugehörigen Aktivität.
class HistorySessionRecord {
  const HistorySessionRecord({
    required this.plan,
    required this.session,
    this.activity,
  });

  final Plan plan;
  final Session session;
  final Activity? activity;

  /// Keine Aufzeichnung vorhanden → Status unbekannt.
  bool get isUnknown => activity == null;

  ActivityStatus? get status => activity?.status;

  int? get plannedSeconds => session.plannedDurationSeconds;

  /// Tatsächliche Dauer (Gesamt- vor Bewegungszeit) – auch bei „ausgelassen“,
  /// damit hier nichts erfunden oder verschluckt wird.
  int? get actualSeconds =>
      activity?.elapsedDurationSeconds ?? activity?.movingDurationSeconds;

  String get title =>
      session.type.trim().isEmpty ? session.sport.labelDe : session.type;

  /// `Erledigt` / `Teilweise` / `Ausgelassen` / `keine Aufzeichnung`.
  String get statusLabelDe =>
      activity?.status.shortLabelDe ?? kNoRecordingLabelDe;

  /// Vergleich Ist gegen Plan (`15 min kürzer`), `null` wenn Werte fehlen.
  String? get deltaLabelDe => durationDeltaLabel(plannedSeconds, actualSeconds);
}

/// Ein Kalendertag mit Inhalt (geplante Sitzung, Aktivität oder Tagebucheintrag).
class HistoryDayRecord {
  const HistoryDayRecord({
    required this.dateIso,
    required this.date,
    this.sessions = const <HistorySessionRecord>[],
    this.unplanned = const <Activity>[],
    this.journal = const <JournalEntry>[],
  });

  final String dateIso;
  final DateTime date;
  final List<HistorySessionRecord> sessions;

  /// Ungeplante Aktivitäten des Tages, aufsteigend nach Startzeit.
  final List<Activity> unplanned;

  /// Tagebucheinträge des Tages, aufsteigend nach Zeitstempel.
  final List<JournalEntry> journal;

  /// Gesamtbefinden des letzten Eintrags des Tages (`null` = nicht erfasst).
  int? get lastFeeling => journal.isEmpty ? null : journal.last.overallFeeling;

  /// Gibt es mindestens einen Eintrag mit Freitext?
  bool get hasJournalText =>
      journal.any((entry) => (entry.text?.trim().isNotEmpty) ?? false);

  bool get hasContent =>
      sessions.isNotEmpty || unplanned.isNotEmpty || journal.isNotEmpty;
}

/// Zähler und Minuten-Summen eines Zeitraums.
class RangeSummary {
  const RangeSummary({
    this.completed = 0,
    this.partial = 0,
    this.skipped = 0,
    this.unknown = 0,
    this.actualSeconds,
    this.plannedSeconds,
  });

  final int completed;
  final int partial;
  final int skipped;

  /// Geplante Einheiten ohne jede Aufzeichnung – UNBEKANNT, nicht „ausgelassen“.
  final int unknown;

  /// Summe der tatsächlichen Dauern (nur wo Werte existieren, ohne
  /// „ausgelassen“), sonst `null`.
  final int? actualSeconds;

  /// Summe der geplanten Dauern (nur wo Werte existieren), sonst `null`.
  final int? plannedSeconds;

  int get total => completed + partial + skipped + unknown;

  String get countsLabelDe =>
      '$completed erledigt · $partial teilweise · $skipped ausgelassen · '
      '$unknown offen';

  String get minutesLabelDe =>
      'Ist: ${formatMinutesWithUnit(actualSeconds)} / '
      'Plan: ${formatMinutesWithUnit(plannedSeconds)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Ableitung der Tage mit Inhalt
// ─────────────────────────────────────────────────────────────────────────────

/// Alle Tage mit Inhalt innerhalb [range], neueste zuerst.
///
/// Inhalte: geplante Sitzungen (nur neueste Plan-Revision), ungeplante
/// Aktivitäten und Tagebucheinträge. Eine Sitzung mit einer Aktivität an einem
/// anderen Kalendertag bleibt am Sitzungstag – die Aktivität gehört zur Sitzung.
List<HistoryDayRecord> buildHistoryDays({
  required AppState state,
  required HistoryRange range,
  required DateTime today,
}) {
  final fromIso = _isoOrNull(range.startDate(today));
  final toIso = _isoOrNull(range.endDate(today));

  // 1:1-Regel wie im Repository: die erste Aktivität je Sitzung zählt.
  final activityBySessionId = <String, Activity>{};
  for (final activity in state.activities) {
    final sessionId = activity.plannedSessionId;
    if (sessionId == null || sessionId.isEmpty) continue;
    activityBySessionId.putIfAbsent(sessionId, () => activity);
  }

  final sessionsByDate = <String, List<HistorySessionRecord>>{};
  for (final plan in state.latestPlans) {
    for (final session in plan.sessions) {
      if (!_inRange(session.date, fromIso, toIso)) continue;
      sessionsByDate
          .putIfAbsent(session.date, () => <HistorySessionRecord>[])
          .add(
            HistorySessionRecord(
              plan: plan,
              session: session,
              activity: activityBySessionId[session.id],
            ),
          );
    }
  }

  final unplannedByDate = <String, List<Activity>>{};
  for (final activity in state.activities) {
    if (activity.plannedSessionId != null) continue;
    final local = DateTime.tryParse(activity.startedAt)?.toLocal();
    if (local == null) continue;
    final dateIso = formatDateIso(local);
    if (!_inRange(dateIso, fromIso, toIso)) continue;
    unplannedByDate.putIfAbsent(dateIso, () => <Activity>[]).add(activity);
  }

  final journalByDate = <String, List<JournalEntry>>{};
  for (final entry in state.journal) {
    final local = DateTime.tryParse(entry.timestamp)?.toLocal();
    if (local == null) continue;
    final dateIso = formatDateIso(local);
    if (!_inRange(dateIso, fromIso, toIso)) continue;
    journalByDate.putIfAbsent(dateIso, () => <JournalEntry>[]).add(entry);
  }

  final dates = <String>{
    ...sessionsByDate.keys,
    ...unplannedByDate.keys,
    ...journalByDate.keys,
  }.toList()..sort((a, b) => b.compareTo(a));

  final days = <HistoryDayRecord>[];
  for (final dateIso in dates) {
    final date = parseIsoDate(dateIso);
    if (date == null) continue;
    final sessions =
        (sessionsByDate[dateIso] ?? const <HistorySessionRecord>[]).toList()
          ..sort(_compareSessionRecords);
    final unplanned = (unplannedByDate[dateIso] ?? const <Activity>[]).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final journal = (journalByDate[dateIso] ?? const <JournalEntry>[]).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    days.add(
      HistoryDayRecord(
        dateIso: dateIso,
        date: date,
        sessions: sessions,
        unplanned: unplanned,
        journal: journal,
      ),
    );
  }
  return days;
}

/// Zählt geplante Einheiten und summiert Minuten über [days].
///
/// Minuten werden ausschließlich aus vorhandenen Werten gebildet – fehlende
/// Angaben bleiben fehlend (`null`), sie werden nicht als 0 gezählt.
RangeSummary summarizeHistory(Iterable<HistoryDayRecord> days) {
  var completed = 0;
  var partial = 0;
  var skipped = 0;
  var unknown = 0;
  int? actualSeconds;
  int? plannedSeconds;

  for (final day in days) {
    for (final record in day.sessions) {
      switch (record.status) {
        case null:
          unknown++;
        case ActivityStatus.completed:
          completed++;
        case ActivityStatus.partial:
          partial++;
        case ActivityStatus.skipped:
          skipped++;
      }
      final planned = record.plannedSeconds;
      if (planned != null) plannedSeconds = (plannedSeconds ?? 0) + planned;
      if (record.status != ActivityStatus.skipped) {
        final actual = record.actualSeconds;
        if (actual != null) actualSeconds = (actualSeconds ?? 0) + actual;
      }
    }
  }

  return RangeSummary(
    completed: completed,
    partial: partial,
    skipped: skipped,
    unknown: unknown,
    actualSeconds: actualSeconds,
    plannedSeconds: plannedSeconds,
  );
}

/// Sortiert Sitzungen eines Tages: Schwimmen → Rad → Laufen → Kraft →
/// Sonstiges, danach nach Typ.
int _compareSessionRecords(HistorySessionRecord a, HistorySessionRecord b) {
  final bySport = a.session.sport.sortIndex.compareTo(
    b.session.sport.sortIndex,
  );
  if (bySport != 0) return bySport;
  return a.session.type.compareTo(b.session.type);
}

String? _isoOrNull(DateTime? date) => date == null ? null : formatDateIso(date);

bool _inRange(String dateIso, String? fromIso, String? toIso) {
  if (fromIso != null && dateIso.compareTo(fromIso) < 0) return false;
  if (toIso != null && dateIso.compareTo(toIso) > 0) return false;
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tagebuch-Gruppierung
// ─────────────────────────────────────────────────────────────────────────────

/// Alle Einträge eines Kalendertags (aufsteigend nach Zeitstempel).
class JournalDayGroup {
  const JournalDayGroup({
    required this.dateIso,
    required this.date,
    required this.entries,
  });

  final String dateIso;
  final DateTime date;
  final List<JournalEntry> entries;

  /// Gesamtbefinden des letzten Eintrags (`null` = nicht angegeben).
  int? get lastFeeling => entries.isEmpty ? null : entries.last.overallFeeling;
}

/// Sortiert Einträge neueste zuerst (unlesbare Zeitstempel nach hinten).
List<JournalEntry> sortJournalNewestFirst(Iterable<JournalEntry> entries) {
  final sorted = entries.toList()
    ..sort((a, b) {
      final left = DateTime.tryParse(a.timestamp);
      final right = DateTime.tryParse(b.timestamp);
      if (left == null && right == null) return a.id.compareTo(b.id);
      if (left == null) return 1;
      if (right == null) return -1;
      final byTime = right.compareTo(left);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  return sorted;
}

/// Gruppiert Einträge nach Kalendertag, neueste Tage zuerst und innerhalb
/// eines Tages aufsteigend nach Uhrzeit.
List<JournalDayGroup> groupJournalByDay(Iterable<JournalEntry> entries) {
  final byDate = <String, List<JournalEntry>>{};
  for (final entry in entries) {
    final local = DateTime.tryParse(entry.timestamp)?.toLocal();
    if (local == null) continue;
    byDate.putIfAbsent(formatDateIso(local), () => <JournalEntry>[]).add(entry);
  }
  final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
  final groups = <JournalDayGroup>[];
  for (final dateIso in dates) {
    final date = parseIsoDate(dateIso);
    if (date == null) continue;
    final sorted = byDate[dateIso]!
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    groups.add(JournalDayGroup(dateIso: dateIso, date: date, entries: sorted));
  }
  return groups;
}
