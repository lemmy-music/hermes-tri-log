import '../models/models.dart';
import '../utils/formats.dart';

// Reine Tagebuch-Logik: nachträglicher Abschluss vergessener Entwürfe.
//
// Bewusst hier (eigene `journal_service.dart`) und nicht in
// `reminder_service.dart` (dort geht es ausschließlich um die *Planung* von
// Erinnerungen) und nicht in `history_service.dart` (dort nur Gruppierung/
// Sortierung für die Anzeige): Diese Funktion verändert fachlich den
// Tagebuch-Zustand, bleibt aber frei von IO, UI und Uhr.

/// Uhrzeit, zu der ein vergessener Entwurf rückwirkend abgeschlossen wird.
const int kAutoFinalizeHour = 23;
const int kAutoFinalizeMinute = 59;

/// Liefert die Einträge, die als vergessene Entwürfe gelten – **ohne** den
/// übergebenen Zustand zu verändern.
///
/// Ein Eintrag wird abgeschlossen, wenn
/// * `finalized_at == null` (Entwurf) **und**
/// * sein Kalendertag (lokale Zeit) **vor** dem Kalendertag von [today] liegt.
///
/// Für jeden Treffer wird eine Kopie mit
/// * `finalized_at` = Eintragstag um **23:59:00 lokale Zeit** (ISO mit lokalem
///   Offset, also auch über Sommer-/Winterzeit korrekt),
/// * `finalized_automatically = true`,
/// * unverändertem `timestamp` und **unverändertem `updated_at`**
/// zurückgegeben.
///
/// Einträge von heute oder aus der Zukunft, bereits abgeschlossene Einträge
/// und Einträge ohne auswertbaren Zeitstempel bleiben unangetastet (sie werden
/// gar nicht zurückgegeben). Dadurch ist wiederholtes Anwenden idempotent:
/// ein zweiter Lauf liefert eine leere Liste.
List<JournalEntry> staleDraftFinalizations(
  List<JournalEntry> entries,
  DateTime today,
) {
  final todayDay = DateTime(today.year, today.month, today.day);
  final result = <JournalEntry>[];

  for (final entry in entries) {
    if (entry.finalizedAt != null) continue;
    final local = DateTime.tryParse(entry.timestamp)?.toLocal();
    if (local == null) continue;

    final entryDay = DateTime(local.year, local.month, local.day);
    if (!entryDay.isBefore(todayDay)) continue;

    result.add(
      JournalEntry(
        id: entry.id,
        timestamp: entry.timestamp,
        updatedAt: entry.updatedAt,
        finalizedAt: isoWithOffset(
          DateTime(
            entryDay.year,
            entryDay.month,
            entryDay.day,
            kAutoFinalizeHour,
            kAutoFinalizeMinute,
          ),
        ),
        finalizedAutomatically: true,
        overallFeeling: entry.overallFeeling,
        text: entry.text,
      ),
    );
  }

  return result;
}

/// Nächste lokale Mitternacht **nach** [from] (wall-clock, also auch über eine
/// Zeitumstellung hinweg 00:00 Uhr lokal).
DateTime nextLocalMidnight(DateTime from) =>
    DateTime(from.year, from.month, from.day + 1);
