import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/formats.dart';

/// Kompakte, rein lesende Planungs-Zusammenfassung einer geplanten Sitzung:
/// Typ, Sport · Plan-Titel, Plan-Dauer, Struktur-Kurzfassung und die
/// vollständige Beschreibung (bewusst ohne Kürzung).
///
/// Wird an zwei Stellen genutzt:
/// * im Erfassungs-Sheet (`showActivityEntrySheet`) als Kontext „was war
///   geplant“,
/// * im rein lesenden Sheet „Planung ansehen“ (`showPlanDetailSheet`) für
///   kommende Tage.
///
/// Der Key `plannedSummary` bleibt erhalten, damit bestehende Tests, die den
/// Block im Erfassungs-Sheet prüfen, unverändert greifen.
class PlanSummary extends StatelessWidget {
  const PlanSummary({
    super.key,
    required this.plan,
    required this.session,
    this.heading = 'Planung',
  });

  final Plan plan;
  final Session session;

  /// Überschrift des Blocks (klein, in Versalien-Optik).
  final String heading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = session.type.trim().isEmpty
        ? session.sport.labelDe
        : session.type;
    final planTitle = plan.title.trim();
    final summary = session.structureSummaryText;
    final instructions = session.instructions?.trim() ?? '';
    final sportAndPlan = planTitle.isEmpty
        ? session.sport.labelDe
        : '${session.sport.labelDe} · $planTitle';

    return Container(
      key: const Key('plannedSummary'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            heading,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(type, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            sportAndPlan,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            'Plan: ${formatMinutesWithUnit(session.plannedDurationSeconds)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (summary.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.timeline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(summary, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ],
          if (instructions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(instructions, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
