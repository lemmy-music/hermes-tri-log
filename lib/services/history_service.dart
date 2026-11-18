import '../models/models.dart';
import '../utils/formats.dart';

/// Reine, seiteneffektfreie Helfer für den Verlaufs-Tab (geplant vs. tatsächlich)
/// und für die Gruppierung des Tagebuchs.
///
/// Bewusst ohne UI- und ohne Repository-Abhängigkeit: alles lässt sich damit
/// unit-testen. Die Ableitung der Tage mit Inhalt passiert genau einmal pro
/// Aufbau (Maps statt quadratischer Suche pro Zeile).

/// Wählbarer Zeitraum im Verlauf.
///
/// Alle Zeiträume liegen als **Zeitscheibe um heute**: „7 Tage“ sind heute −7
/// bis heute +7 (15 Kalendertage), „30 Tage“ entsprechend ±30. „Alles“ reicht
/// vom frühesten bis zum spätesten Datum mit Inhalt, mindestens aber ±7 – damit
/// die Liste nie leer wirkt und der heutige Tag immer als Anker existiert.
enum HistoryRange { last7Days, last30Days, all }

/// Inklusiver Kalendertag-Bereich (jeweils 00:00 des ersten/letzten Tages).
class HistoryWindow {
  const HistoryWindow({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  /// Anzahl der enthaltenen Kalendertage (beide Grenzen inklusiv).
  int get dayCount =>
      DateTime(
        to.year,
        to.month,
        to.day,
      ).difference(DateTime(from.year, from.month, from.day)).inDays +
      1;

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(DateTime(from.year, from.month, from.day)) &&
        !day.isAfter(DateTime(to.year, to.month, to.day));
  }
}

extension HistoryRangeX on HistoryRange {
  String get labelDe => switch (this) {
    HistoryRange.last7Days => '7 Tage',
    HistoryRange.last30Days => '30 Tage',
    HistoryRange.all => 'Alles',
  };

  /// Halbe Breite der Zeitscheibe in Tagen (`null` bei „Alles“).
  int? get halfSpanDays => switch (this) {
    HistoryRange.last7Days => 7,
    HistoryRange.last30Days => 30,
    HistoryRange.all => null,
  };

  /// Konkreter Bereich um [today].
  ///
  /// [contentDates] (alle Tage mit Sitzung/Aktivität/Tagebucheintrag) wirkt nur
  /// bei [HistoryRange.all]: dort bestimmt der Inhalt die Grenzen, mindestens
  /// aber heute ±7.
  HistoryWindow window({
    required DateTime today,
    Iterable<DateTime> contentDates = const <DateTime>[],
  }) {
    final day = DateTime(today.year, today.month, today.day);

    final span = halfSpanDays;
    if (span != null) {
      return HistoryWindow(
        from: DateTime(day.year, day.month, day.day - span),
        to: DateTime(day.year, day.month, day.day + span),
      );
    }

    var from = DateTime(day.year, day.month, day.day - 7);
    var to = DateTime(day.year, day.month, day.day + 7);
    for (final content in contentDates) {
      final contentDay = DateTime(content.year, content.month, content.day);
      if (contentDay.isBefore(from)) from = contentDay;
      if (contentDay.isAfter(to)) to = contentDay;
    }
    return HistoryWindow(from: from, to: to);
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

/// Ein Kalendertag im Verlauf (geplante Sitzung, Aktivität oder
/// Tagebucheintrag). Der heutige Tag ist immer enthalten – auch ohne Inhalt,
/// damit er als Anker für die Zentrierung existiert.
class HistoryDayRecord {
  const HistoryDayRecord({
    required this.dateIso,
    required this.date,
    this.sessions = const <HistorySessionRecord>[],
    this.unplanned = const <Activity>[],
    this.journal = const <JournalEntry>[],
    this.isToday = false,
    this.isFuture = false,
  });

  final String dateIso;
  final DateTime date;
  final List<HistorySessionRecord> sessions;

  /// Ungeplante Aktivitäten des Tages, aufsteigend nach Startzeit.
  final List<Activity> unplanned;

  /// Tagebucheinträge des Tages, aufsteigend nach Zeitstempel.
  final List<JournalEntry> journal;

  /// Kalendertag ist heute (Anker der Liste).
  final bool isToday;

  /// Kalendertag liegt nach heute – geplant, bewusst gedämpft dargestellt.
  final bool isFuture;

  /// Gesamtbefinden des letzten Eintrags des Tages (`null` = nicht erfasst).
  int? get lastFeeling => journal.isEmpty ? null : journal.last.overallFeeling;

  /// Gibt es mindestens einen Eintrag mit Freitext?
  bool get hasJournalText =>
      journal.any((entry) => (entry.text?.trim().isNotEmpty) ?? false);

  /// Mindestens ein Tagebucheintrag des Tages ist abgeschlossen
  /// (`finalized_at` gesetzt) – kleines Häkchen im Tageskopf.
  bool get hasFinalizedJournal => journal.any((entry) => entry.isFinalized);

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
    this.plannedInFuture = 0,
    this.actualSeconds,
    this.plannedSeconds,
  });

  final int completed;
  final int partial;
  final int skipped;

  /// Geplante Einheiten ohne jede Aufzeichnung – UNBEKANNT, nicht „ausgelassen“.
  /// Zählt nur Tage ≤ heute (Zukunft ist nicht „offen“).
  final int unknown;

  /// Geplante Einheiten nach heute – bewusst kein Status, nur „geplant“.
  final int plannedInFuture;

  /// Summe der tatsächlichen Dauern (nur wo Werte existieren, ohne
  /// „ausgelassen“), sonst `null`.
  final int? actualSeconds;

  /// Summe der geplanten Dauern der Tage ≤ heute (nur wo Werte existieren),
  /// sonst `null`. Zukunft zählt hier bewusst nicht mit.
  final int? plannedSeconds;

  int get total => completed + partial + skipped + unknown;

  String get countsLabelDe =>
      '$completed erledigt · $partial teilweise · $skipped ausgelassen · '
      '$unknown offen'
      '${plannedInFuture > 0 ? ' · $plannedInFuture geplant (Zukunft)' : ''}';

  String get minutesLabelDe =>
      'Ist: ${formatMinutesWithUnit(actualSeconds)} / '
      'Plan: ${formatMinutesWithUnit(plannedSeconds)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Ableitung der Tage mit Inhalt
// ─────────────────────────────────────────────────────────────────────────────

/// Alle Tage im Zeitraum, **aufsteigend** (Vergangenheit oben, Zukunft unten).
///
/// Inhalte: geplante Sitzungen (nur neueste Plan-Revision), ungeplante
/// Aktivitäten und Tagebucheinträge. Eine Sitzung mit einer Aktivität an einem
/// anderen Kalendertag bleibt am Sitzungstag – die Aktivität gehört zur Sitzung.
/// Der heutige Tag ist immer enthalten (auch ohne Inhalt), damit der Verlauf
/// ihn zentrieren kann.
List<HistoryDayRecord> buildHistoryDays({
  required AppState state,
  required HistoryRange range,
  required DateTime today,
}) {
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
    unplannedByDate
        .putIfAbsent(formatDateIso(local), () => <Activity>[])
        .add(activity);
  }

  final journalByDate = <String, List<JournalEntry>>{};
  for (final entry in state.journal) {
    final local = DateTime.tryParse(entry.timestamp)?.toLocal();
    if (local == null) continue;
    journalByDate
        .putIfAbsent(formatDateIso(local), () => <JournalEntry>[])
        .add(entry);
  }

  // Alle Tage mit Inhalt (unabhängig vom Zeitraum) – nur „Alles“ braucht sie
  // als Grenzen.
  final contentDates = <DateTime>[
    for (final dateIso in <String>{
      ...sessionsByDate.keys,
      ...unplannedByDate.keys,
      ...journalByDate.keys,
    })
      ?parseIsoDate(dateIso),
  ];
  final window = range.window(today: today, contentDates: contentDates);

  final todayIso = formatDateIso(today);
  final dates =
      <String>{
          ...sessionsByDate.keys,
          ...unplannedByDate.keys,
          ...journalByDate.keys,
        }.where((dateIso) {
          final date = parseIsoDate(dateIso);
          return date != null && window.contains(date);
        }).toSet()
        ..add(todayIso);

  final sortedDates = dates.toList()..sort();

  final days = <HistoryDayRecord>[];
  for (final dateIso in sortedDates) {
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
        isToday: dateIso == todayIso,
        isFuture: dateIso.compareTo(todayIso) > 0,
      ),
    );
  }
  return days;
}

/// Geplante Sitzungen der nächsten [dayCount] Kalendertage (heute+1 … heute+n),
/// gruppiert nach Tag und aufsteigend. Tage ohne Sitzung fehlen komplett – eine
/// leere Liste heißt „nichts geplant“.
List<HistoryDayRecord> buildUpcomingDays({
  required AppState state,
  required DateTime today,
  int dayCount = 7,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final fromIso = formatDateIso(DateTime(day.year, day.month, day.day + 1));
  final toIso = formatDateIso(
    DateTime(day.year, day.month, day.day + dayCount),
  );

  final sessionsByDate = <String, List<HistorySessionRecord>>{};
  for (final plan in state.latestPlans) {
    for (final session in plan.sessions) {
      if (session.date.compareTo(fromIso) < 0) continue;
      if (session.date.compareTo(toIso) > 0) continue;
      sessionsByDate
          .putIfAbsent(session.date, () => <HistorySessionRecord>[])
          .add(HistorySessionRecord(plan: plan, session: session));
    }
  }

  final dates = sessionsByDate.keys.toList()..sort();
  final days = <HistoryDayRecord>[];
  for (final dateIso in dates) {
    final date = parseIsoDate(dateIso);
    if (date == null) continue;
    days.add(
      HistoryDayRecord(
        dateIso: dateIso,
        date: date,
        sessions: sessionsByDate[dateIso]!..sort(_compareSessionRecords),
        isFuture: true,
      ),
    );
  }
  return days;
}

/// Zählt geplante Einheiten und summiert Minuten über [days].
///
/// Statuszähler und Plan-Minuten betrachten ausschließlich Tage ≤ heute –
/// Zukunft ist „geplant“, nicht „offen“. Minuten werden ausschließlich aus
/// vorhandenen Werten gebildet: fehlende Angaben bleiben fehlend (`null`), sie
/// werden nicht als 0 gezählt.
RangeSummary summarizeHistory(Iterable<HistoryDayRecord> days) {
  var completed = 0;
  var partial = 0;
  var skipped = 0;
  var unknown = 0;
  var plannedInFuture = 0;
  int? actualSeconds;
  int? plannedSeconds;

  for (final day in days) {
    for (final record in day.sessions) {
      if (day.isFuture) {
        plannedInFuture++;
        continue;
      }
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
    plannedInFuture: plannedInFuture,
    actualSeconds: actualSeconds,
    plannedSeconds: plannedSeconds,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Flache Zeilenliste (für die Liste und die Zentrierung auf heute)
// ─────────────────────────────────────────────────────────────────────────────

/// Eine Zeile der Verlaufsliste: Tageskopf, Sitzung oder ungeplante Einheit.
sealed class HistoryRow {
  const HistoryRow(this.day);

  final HistoryDayRecord day;
}

class HistoryDayRow extends HistoryRow {
  const HistoryDayRow(super.day);
}

class HistorySessionRow extends HistoryRow {
  const HistorySessionRow(super.day, this.record);

  final HistorySessionRecord record;
}

class HistoryUnplannedRow extends HistoryRow {
  const HistoryUnplannedRow(super.day, this.activity);

  final Activity activity;
}

/// Flacht [days] (aufsteigend) in Zeilen ab: erst der Tageskopf, dann die
/// geplanten Sitzungen, dann die ungeplanten Einheiten des Tages.
List<HistoryRow> buildHistoryRows(Iterable<HistoryDayRecord> days) {
  final rows = <HistoryRow>[];
  for (final day in days) {
    rows.add(HistoryDayRow(day));
    for (final record in day.sessions) {
      rows.add(HistorySessionRow(day, record));
    }
    for (final activity in day.unplanned) {
      rows.add(HistoryUnplannedRow(day, activity));
    }
  }
  return rows;
}

/// Index des heutigen Tageskopfs in [rows] (`-1`, falls nicht vorhanden).
/// Reine Funktion – die Liste wird damit auf heute zentriert.
int indexOfTodayRow(List<HistoryRow> rows) {
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    if (row is HistoryDayRow && row.day.isToday) return index;
  }
  return -1;
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
