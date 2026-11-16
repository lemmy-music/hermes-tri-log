import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_repository.dart';
import '../utils/formats.dart';

/// Zeigt ausschließlich den heutigen Tag (keine Aktionen – die kommen in
/// Phase 3).
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final today = repository.now;
    final sessions = repository.todaySessions;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Text(formatDateGerman(today), style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Geplante Einheiten',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (sessions.isEmpty)
          const _EmptyState()
        else
          for (final entry in sessions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SessionCard(entry: entry),
            ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.event_available_outlined,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Heute keine Einheit geplant.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Pläne lassen sich im Tab „Daten“ als JSON importieren.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.entry});

  final TodaySession entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = entry.session;
    final summary = session.structureSummaryText;
    final instructions = session.instructions?.trim();
    final title = session.type.trim().isEmpty
        ? session.sport.labelDe
        : session.type;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  sportIcon(session.sport),
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${session.sport.labelDe} · '
                        '${formatMinutesWithUnit(entry.session.plannedDurationSeconds)}'
                        '${entry.plan.title.trim().isEmpty ? '' : ' · ${entry.plan.title}'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (session.optional) const _OptionalBadge(),
              ],
            ),
            if (summary.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
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
            if (instructions != null && instructions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                instructions,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionalBadge extends StatelessWidget {
  const _OptionalBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'optional',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// Sport-Icon für die Heute-Karten (auch von anderen Screens nutzbar).
IconData sportIcon(Sport sport) => switch (sport) {
  Sport.swim => Icons.pool,
  Sport.bike => Icons.directions_bike,
  Sport.run => Icons.directions_run,
  Sport.strength => Icons.fitness_center,
  Sport.other => Icons.sports,
};
