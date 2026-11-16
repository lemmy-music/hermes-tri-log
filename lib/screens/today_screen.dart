import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_repository.dart';
import '../utils/formats.dart';
import 'activity_sheet.dart';

/// Zeigt ausschließlich den heutigen Tag: geplante Einheiten zum Abhaken,
/// darunter optional ungeplante Einheiten („Zusätzlich“).
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final today = repository.now;
    final sessions = repository.todaySessions;
    final unplanned = repository.todayUnplannedActivities;
    final theme = Theme.of(context);

    var completed = 0;
    var partial = 0;
    for (final entry in sessions) {
      final status = repository.activityForSession(entry.session.id)?.status;
      if (status == ActivityStatus.completed) completed++;
      if (status == ActivityStatus.partial) partial++;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        Text(formatDateGerman(today), style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Geplante Einheiten',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (sessions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            '$completed von ${sessions.length} erledigt'
            '${partial > 0 ? ' · $partial teilweise' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (sessions.isEmpty && unplanned.isEmpty)
          const _EmptyState()
        else ...<Widget>[
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Heute keine Einheit geplant.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final entry in sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SessionCard(entry: entry),
              ),
          if (unplanned.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Zusätzlich',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final activity in unplanned)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _UnplannedTile(activity: activity),
              ),
          ],
        ],
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

/// Eine geplante Sitzungskarte: ein Tap auf das Häkchen hakt in einem Schritt
/// ab, ein Tap auf den Kartenkörper öffnet das Erfassungs-Sheet.
class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.entry});

  final TodaySession entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repository = context.watch<AppRepository>();
    final session = entry.session;
    final activity = repository.activityForSession(session.id);
    final summary = session.structureSummaryText;
    final instructions = session.instructions?.trim();
    final notes = activity?.notes?.trim();
    final title = session.type.trim().isEmpty
        ? session.sport.labelDe
        : session.type;

    void openSheet() =>
        showActivityEntrySheet(context, day: repository.now, planned: entry);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openSheet,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(
                      sportIcon(session.sport),
                      size: 28,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${session.sport.labelDe}'
                          '${entry.plan.title.trim().isEmpty ? '' : ' · ${entry.plan.title}'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (session.optional) const _OptionalBadge(),
                  if (activity == null)
                    IconButton(
                      key: ValueKey<String>('check-${session.id}'),
                      tooltip: 'Abhaken',
                      icon: const Icon(Icons.check_circle_outline),
                      onPressed: () => _quickComplete(context, entry),
                    )
                  else
                    IconButton(
                      key: ValueKey<String>('edit-${session.id}'),
                      tooltip: 'Ist-Daten bearbeiten',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: openSheet,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (activity != null) ...<Widget>[
                      _StatusBadge(status: activity.status),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _planActualLine(session, activity),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
              if (notes != null && notes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `Plan: 45 min` bzw. `Plan: 45 min · Ist: 35 min (15 min kürzer)`.
String _planActualLine(Session session, Activity? activity) {
  final parts = <String>[
    'Plan: ${formatMinutesWithUnit(session.plannedDurationSeconds)}',
  ];
  if (activity != null) {
    final actual =
        activity.elapsedDurationSeconds ?? activity.movingDurationSeconds;
    final actualLabel = formatMinutesWithUnit(actual);
    final delta = durationDeltaLabel(session.plannedDurationSeconds, actual);
    parts.add(
      delta == null ? 'Ist: $actualLabel' : 'Ist: $actualLabel ($delta)',
    );
  }
  return parts.join(' · ');
}

/// Ein-Tap-Abhaken: erzeugt (oder aktualisiert) die eine Aktivität der Sitzung.
void _quickComplete(BuildContext context, TodaySession entry) {
  final repository = context.read<AppRepository>();
  final session = entry.session;
  final activity = repository.saveActivityForSession(
    plan: entry.plan,
    session: session,
    status: ActivityStatus.completed,
    elapsedDurationSeconds: session.plannedDurationSeconds,
  );

  final title = session.type.trim().isEmpty
      ? session.sport.labelDe
      : session.type;
  final duration = formatMinutesWithUnit(activity.elapsedDurationSeconds);

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          duration == '–' ? 'Abgehakt: $title' : 'Abgehakt: $title · $duration',
        ),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () => repository.deleteActivity(activity.id),
        ),
      ),
    );
}

/// Ungeplante Einheit des Tages („Zusätzlich“).
class _UnplannedTile extends StatelessWidget {
  const _UnplannedTile({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sport = sportFromWireName(activity.sport);
    final duration =
        activity.elapsedDurationSeconds ?? activity.movingDurationSeconds;
    final details = <String>[
      if (duration != null) formatMinutesWithUnit(duration),
      activity.status.shortLabelDe,
    ].join(' · ');

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showActivityEntrySheet(
          context,
          day:
              DateTime.tryParse(activity.startedAt)?.toLocal() ??
              DateTime.now(),
          unplanned: activity,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(
                sport == null ? Icons.sports : sportIcon(sport),
                size: 22,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      sportLabelFromWireName(activity.sport).isEmpty
                          ? 'Sonstiges'
                          : sportLabelFromWireName(activity.sport),
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      details,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ActivityStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = switch (status) {
      ActivityStatus.completed => (
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
      ),
      ActivityStatus.partial => (
        theme.colorScheme.secondaryContainer,
        theme.colorScheme.onSecondaryContainer,
      ),
      ActivityStatus.skipped => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.shortLabelDe,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
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
