import '../models/models.dart';
import '../utils/canonical_json.dart';
import '../utils/formats.dart';
import 'import_service.dart';

/// Status eines importierten Plans gegenüber dem lokalen Bestand.
enum PlanImportStatus { newPlan, newRevision, unchanged, conflict }

extension PlanImportStatusX on PlanImportStatus {
  String get labelDe => switch (this) {
    PlanImportStatus.newPlan => 'neu',
    PlanImportStatus.newRevision => 'neue Revision',
    PlanImportStatus.unchanged => 'unverändert',
    PlanImportStatus.conflict => 'Konflikt',
  };
}

/// Diff eines einzelnen Plans (pure Daten für die Vorschau).
class PlanDiff {
  const PlanDiff({
    required this.planId,
    required this.revision,
    required this.title,
    required this.status,
    this.addedSessions = 0,
    this.changedSessions = 0,
    this.removedSessions = 0,
    this.affectedDates = const <String>{},
    this.warnings = const <String>[],
    this.conflictMessage,
  });

  final String planId;
  final int revision;
  final String title;
  final PlanImportStatus status;
  final int addedSessions;
  final int changedSessions;
  final int removedSessions;

  /// Betroffene Kalendertage (`YYYY-MM-DD`), z. B. für "3 Tage betroffen".
  final Set<String> affectedDates;
  final List<String> warnings;
  final String? conflictMessage;

  bool get isEmptyChange =>
      status == PlanImportStatus.unchanged ||
      (addedSessions == 0 && changedSessions == 0 && removedSessions == 0);
}

/// Gesamtergebnis eines Merges inkl. Vorschau-Daten.
class MergeResult {
  const MergeResult({
    required this.plans,
    this.warnings = const <String>[],
    this.addedActivities = 0,
    this.addedJournalEntries = 0,
    this.proposedState,
  });

  final List<PlanDiff> plans;
  final List<String> warnings;
  final int addedActivities;
  final int addedJournalEntries;

  /// Zustand nach dem Import – `null`, wenn ein Konflikt den Import blockiert.
  final AppState? proposedState;

  bool get hasConflict =>
      plans.any((plan) => plan.status == PlanImportStatus.conflict);

  int get addedSessions =>
      plans.fold<int>(0, (sum, plan) => sum + plan.addedSessions);
  int get changedSessions =>
      plans.fold<int>(0, (sum, plan) => sum + plan.changedSessions);
  int get removedSessions =>
      plans.fold<int>(0, (sum, plan) => sum + plan.removedSessions);

  /// Union aller betroffenen Tage über alle Pläne.
  Set<String> get affectedDates => <String>{
    for (final plan in plans) ...plan.affectedDates,
  };

  int get affectedDayCount => affectedDates.length;

  bool get hasChanges =>
      addedSessions > 0 ||
      changedSessions > 0 ||
      removedSessions > 0 ||
      addedActivities > 0 ||
      addedJournalEntries > 0;

  /// Kurze deutsche Zusammenfassung für die SnackBar.
  String get summaryDe {
    if (hasConflict) return 'Import blockiert: Konflikt bei einer Revision.';
    if (!hasChanges && plans.every((plan) => plan.isEmptyChange)) {
      return 'Keine Änderungen.';
    }
    final parts = <String>[];
    if (addedSessions > 0) parts.add('$addedSessions hinzugefügt');
    if (changedSessions > 0) parts.add('$changedSessions geändert');
    if (removedSessions > 0) parts.add('$removedSessions entfernt');
    final sessionText = parts.isEmpty
        ? 'keine Sitzungsänderung'
        : parts.join(', ');
    return 'Import übernommen: ${pluralPlanRevisionen(plans.length)}, '
        '$sessionText, ${pluralTage(affectedDayCount)} betroffen.';
  }

  /// Alle Warnungen (Plan-spezifisch + global) ohne Duplikate.
  List<String> get allWarnings => <String>{
    ...warnings,
    for (final plan in plans) ...plan.warnings,
  }.toList();
}

/// Berechnet den Merge eines Imports gegen den lokalen Zustand.
///
/// Regeln:
/// 1. Schlüssel eines Plans = (id, revision).
/// 2. Gleicher Schlüssel + identischer Inhalt → no-op.
/// 3. Gleicher Schlüssel + abweichender Inhalt → Konflikt (Import blockiert).
/// 4. Neuer Schlüssel → hinzufügen, ältere Revisionen bleiben erhalten.
/// 5. Neue Revision: Sitzungen werden per session.id verglichen.
/// 6. Activities werden durch Plan-Importe nie verändert/gelöscht.
/// 7. Activities/Journal aus der Datei werden per id ergänzt (nie gelöscht).
/// 8. Dieses Ergebnis enthält alle Daten für die Vorschau.
MergeResult computeMerge({
  required AppState current,
  required ImportResult imported,
}) {
  final diffs = <PlanDiff>[];
  final warnings = <String>[];
  final newPlans = <Plan>[];

  // Basis für den Sitzungsvergleich: die höchste Revision, die bereits lokal
  // existiert ODER in dieser Datei vorher hinzugefügt wurde. So wird eine
  // Revision 2 auch dann korrekt gegen Revision 1 verglichen, wenn beide in
  // derselben Datei stehen.
  Plan? latestKnownPlan(String planId) {
    var best = current.latestPlanFor(planId);
    for (final pending in newPlans) {
      if (pending.id != planId) continue;
      if (best == null || pending.revision > best.revision) best = pending;
    }
    return best;
  }

  for (final plan in imported.plans) {
    final existingWithKey = current.plans.where(
      (candidate) =>
          candidate.id == plan.id && candidate.revision == plan.revision,
    );
    if (existingWithKey.isNotEmpty) {
      final existing = existingWithKey.first;
      final identical =
          canonicalJson(existing.toJson()) == canonicalJson(plan.toJson());
      if (identical) {
        diffs.add(
          PlanDiff(
            planId: plan.id,
            revision: plan.revision,
            title: plan.title,
            status: PlanImportStatus.unchanged,
          ),
        );
      } else {
        diffs.add(
          PlanDiff(
            planId: plan.id,
            revision: plan.revision,
            title: plan.title,
            status: PlanImportStatus.conflict,
            conflictMessage:
                'Revision ${plan.revision} von ${plan.id} existiert bereits '
                'mit anderem Inhalt — bitte Revision erhöhen.',
          ),
        );
      }
      continue;
    }

    final existingPlan = latestKnownPlan(plan.id);
    if (existingPlan == null) {
      diffs.add(
        PlanDiff(
          planId: plan.id,
          revision: plan.revision,
          title: plan.title,
          status: PlanImportStatus.newPlan,
          addedSessions: plan.sessions.length,
          affectedDates: <String>{
            for (final session in plan.sessions) session.date,
          },
        ),
      );
      newPlans.add(plan);
      continue;
    }

    // Neue Revision einer bereits bekannten plan.id.
    final existingById = <String, Session>{
      for (final session in existingPlan.sessions) session.id: session,
    };
    final incomingById = <String, Session>{
      for (final session in plan.sessions) session.id: session,
    };

    final added = plan.sessions
        .where((session) => !existingById.containsKey(session.id))
        .toList();
    final changed = plan.sessions.where((session) {
      final previous = existingById[session.id];
      return previous != null &&
          canonicalJson(previous.toJson()) != canonicalJson(session.toJson());
    }).toList();
    final removed = existingPlan.sessions
        .where((session) => !incomingById.containsKey(session.id))
        .toList();

    final planWarnings = <String>[];
    if (plan.revision <= existingPlan.revision) {
      planWarnings.add(
        'Revision ${plan.revision} von ${plan.id} ist älter als die vorhandene '
        'Revision ${existingPlan.revision}.',
      );
    }
    for (final session in removed) {
      final hasActivity = current.activities.any(
        (activity) =>
            activity.planId == plan.id &&
            activity.plannedSessionId == session.id,
      );
      if (hasActivity) {
        planWarnings.add(
          'Sitzung "${session.id}" (${session.date}) wird in Revision '
          '${plan.revision} entfernt, es existiert aber bereits eine '
          'Aktivität dazu.',
        );
      }
    }

    diffs.add(
      PlanDiff(
        planId: plan.id,
        revision: plan.revision,
        title: plan.title,
        status: PlanImportStatus.newRevision,
        addedSessions: added.length,
        changedSessions: changed.length,
        removedSessions: removed.length,
        affectedDates: <String>{
          for (final session in <Session>[...added, ...changed, ...removed])
            session.date,
        },
        warnings: planWarnings,
      ),
    );
    newPlans.add(plan);
  }

  final hasConflict = diffs.any(
    (diff) => diff.status == PlanImportStatus.conflict,
  );
  if (hasConflict) {
    return MergeResult(plans: diffs, warnings: warnings, proposedState: null);
  }

  // Activities/Journal aus der Datei per id ergänzen – bestehende bleiben.
  final existingActivityIds = <String>{
    for (final activity in current.activities) activity.id,
  };
  final newActivities = imported.activities
      .where((activity) => !existingActivityIds.contains(activity.id))
      .toList();
  final existingJournalIds = <String>{
    for (final entry in current.journal) entry.id,
  };
  final newJournal = imported.journal
      .where((entry) => !existingJournalIds.contains(entry.id))
      .toList();

  final proposed = current.copyWith(
    plans: <Plan>[...current.plans, ...newPlans],
    activities: <Activity>[...current.activities, ...newActivities],
    journal: <JournalEntry>[...current.journal, ...newJournal],
  );

  return MergeResult(
    plans: diffs,
    warnings: warnings,
    addedActivities: newActivities.length,
    addedJournalEntries: newJournal.length,
    proposedState: proposed,
  );
}
