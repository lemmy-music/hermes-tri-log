import '../models/models.dart';
import '../utils/formats.dart';
import 'settings_service.dart';

/// Art einer geplanten Erinnerung (Wire-Wert, bewusst stabil).
const String kReminderKindMorning = 'morning';
const String kReminderKindEvening = 'evening';

/// Gemeinsamer Titel beider Erinnerungen.
const String kReminderTitle = 'Tri-Log';

/// Body, wenn morgens alle geplanten Einheiten bereits erfasst sind.
const String kMorningAllDoneBody =
    'Alles erfasst – heute steht nichts mehr aus.';

/// Body der Abend-Erinnerung, wenn die Tagesnotiz noch fehlt.
const String kEveningMissingBody = 'Tagesnotiz füllen und abschließen';

/// Body der Abend-Erinnerung, wenn die Tagesnotiz nur ein Entwurf ist.
const String kEveningDraftBody = 'Tagesnotiz ist noch Entwurf';

/// Eine konkrete, zu planende Erinnerung (reines Datenobjekt).
class PlannedReminder {
  const PlannedReminder({
    required this.kind,
    required this.dueAt,
    required this.title,
    required this.body,
  });

  /// `morning` oder `evening`.
  final String kind;

  /// Fälligkeit in lokaler Zeit (Datum von `now`, Uhrzeit aus den Settings).
  final DateTime dueAt;
  final String title;
  final String body;

  bool get isMorning => kind == kReminderKindMorning;
  bool get isEvening => kind == kReminderKindEvening;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.kind == kind &&
      other.dueAt == dueAt &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(kind, dueAt, title, body);

  @override
  String toString() => 'PlannedReminder($kind, ${formatTime(dueAt)}: $body)';
}

/// Plant die Erinnerungen für den Kalendertag von [now] – **pure Funktion**,
/// ohne Seiteneffekte, ohne Plugin, ohne Uhr.
///
/// Regeln:
/// * Morgen: nur wenn heute mindestens eine geplante Sitzung existiert und
///   `settings.morningEnabled` gilt. Body = kompakte Aufzählung; sind alle
///   Einheiten bereits ganz/teilweise erfasst, steht dort
///   [kMorningAllDoneBody].
/// * Abend: nur wenn die Tagesnotiz heute fehlt ([kEveningMissingBody]) oder
///   ein Entwurf ist (`finalizedAt == null` → [kEveningDraftBody]); eine
///   abgeschlossene Tagesnotiz erzeugt keine Erinnerung.
/// * Ungültige Uhrzeiten (Stunde außerhalb 0..23 bzw. Minute außerhalb 0..59)
///   erzeugen für diesen Typ keine Erinnerung.
///
/// Ergebnis ist nach [PlannedReminder.dueAt] aufsteigend sortiert.
List<PlannedReminder> planReminders({
  required AppState state,
  required DateTime now,
  required ReminderSettings settings,
}) {
  final reminders = <PlannedReminder>[];
  final day = DateTime(now.year, now.month, now.day);

  if (settings.morningEnabled &&
      _isValidTime(settings.morningHour, settings.morningMinute)) {
    final sessions = state.sessionsOnDate(day);
    if (sessions.isNotEmpty) {
      reminders.add(
        PlannedReminder(
          kind: kReminderKindMorning,
          dueAt: DateTime(
            day.year,
            day.month,
            day.day,
            settings.morningHour,
            settings.morningMinute,
          ),
          title: kReminderTitle,
          body: describeMorningBody(sessions, activities: state.activities),
        ),
      );
    }
  }

  if (settings.eveningEnabled &&
      _isValidTime(settings.eveningHour, settings.eveningMinute)) {
    final entry = latestJournalEntryOn(state, day);
    final String? body = switch (entry) {
      null => kEveningMissingBody,
      JournalEntry(finalizedAt: null) => kEveningDraftBody,
      _ => null,
    };
    if (body != null) {
      reminders.add(
        PlannedReminder(
          kind: kReminderKindEvening,
          dueAt: DateTime(
            day.year,
            day.month,
            day.day,
            settings.eveningHour,
            settings.eveningMinute,
          ),
          title: kReminderTitle,
          body: body,
        ),
      );
    }
  }

  reminders.sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return reminders;
}

/// Body der Morgen-Übersicht: eine Zeile je Einheit, maximal [maxEntries]
/// Einträge, danach „… und N weitere“.
///
/// Sind alle Einheiten bereits (teilweise) erfasst, wird statt der Aufzählung
/// [kMorningAllDoneBody] geliefert. Ohne Sitzungen kommt ein leerer String.
String describeMorningBody(
  List<Session> sessions, {
  List<Activity> activities = const <Activity>[],
  int maxEntries = 3,
}) {
  if (sessions.isEmpty) return '';
  if (allSessionsRecorded(sessions, activities)) return kMorningAllDoneBody;

  final limit = maxEntries < 1 ? 1 : maxEntries;
  final lines = <String>[
    for (final session in sessions.take(limit)) describeSessionLine(session),
  ];
  final hidden = sessions.length - lines.length;
  if (hidden > 0) lines.add('… und $hidden weitere');
  return lines.join(' · ');
}

/// Eine Zeile der Morgen-Übersicht, z. B. `Rad · Schwellen-Intervalle (60 min)`.
///
/// Fehlt der Typ, bleibt nur das Sport-Label; fehlt die geplante Dauer, wird
/// der Klammer-Zusatz weggelassen (es wird nichts erfunden).
String describeSessionLine(Session session) {
  final buffer = StringBuffer(session.sport.labelDe);
  final type = session.type.trim();
  // Typ nur anhängen, wenn er etwas anderes sagt als das Sport-Label
  // (sonst entsteht „Kraft · Kraft“).
  if (type.isNotEmpty && type != session.sport.labelDe) {
    buffer.write(' · $type');
  }
  final seconds = session.plannedDurationSeconds;
  if (seconds != null && seconds > 0) {
    buffer.write(' (${formatMinutes(seconds)} min)');
  }
  return buffer.toString();
}

/// `true`, wenn zu JEDER Sitzung eine Aktivität mit Status „abgeschlossen“
/// oder „teilweise“ existiert.
///
/// „Ausgelassen“ zählt bewusst NICHT als erfasst: Die Morgen-Übersicht soll
/// dann weiterhin zeigen, was noch aussteht.
bool allSessionsRecorded(List<Session> sessions, List<Activity> activities) {
  if (sessions.isEmpty) return false;
  for (final session in sessions) {
    final recorded = activities.any(
      (activity) =>
          activity.plannedSessionId == session.id &&
          (activity.status == ActivityStatus.completed ||
              activity.status == ActivityStatus.partial),
    );
    if (!recorded) return false;
  }
  return true;
}

/// Neuester Tagebucheintrag eines Kalendertags (oder `null`).
///
/// Gleiche Semantik wie `AppRepository.latestJournalEntryForDate`, aber ohne
/// Seiteneffekte – die Planung darf den Zustand nicht anfassen.
JournalEntry? latestJournalEntryOn(AppState state, DateTime date) {
  final wanted = formatDateIso(date);
  JournalEntry? latest;
  DateTime? latestAt;
  for (final entry in state.journal) {
    final local = DateTime.tryParse(entry.timestamp)?.toLocal();
    if (local == null || formatDateIso(local) != wanted) continue;
    if (latestAt == null || !local.isBefore(latestAt)) {
      latest = entry;
      latestAt = local;
    }
  }
  return latest;
}

bool _isValidTime(int hour, int minute) =>
    hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
