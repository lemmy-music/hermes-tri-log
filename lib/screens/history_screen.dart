import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/history_service.dart';
import '../state/app_repository.dart';
import '../utils/formats.dart';
import 'activity_sheet.dart';
import 'today_screen.dart' show sportIcon;

/// Verlaufs-Tab: geplant vs. tatsächlich über einen wählbaren Zeitraum.
///
/// Alle Ableitungen (Tage mit Inhalt, Zähler, Minuten, Sortierung) kommen aus
/// [buildHistoryDays]/[summarizeHistory] – im `build()` steht keine Logik.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  HistoryRange _range = HistoryRange.last30Days;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final theme = Theme.of(context);
    final today = repository.now;
    final days = buildHistoryDays(
      state: repository.state,
      range: _range,
      today: today,
    );
    final summary = summarizeHistory(days);
    final rows = _buildRows(days);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Verlauf', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              SegmentedButton<HistoryRange>(
                key: const Key('historyRangeSegments'),
                showSelectedIcon: false,
                segments: <ButtonSegment<HistoryRange>>[
                  for (final range in HistoryRange.values)
                    ButtonSegment<HistoryRange>(
                      value: range,
                      label: Text(range.labelDe),
                    ),
                ],
                selected: <HistoryRange>{_range},
                onSelectionChanged: (selection) =>
                    setState(() => _range = selection.first),
              ),
              const SizedBox(height: 12),
              _SummaryCard(summary: summary, days: days.length),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: const <Widget>[_HistoryEmptyState()],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return switch (row) {
                      _HistoryDayRow() => _DayHeader(day: row.day),
                      _HistorySessionRow() => _SessionTile(
                        record: row.record,
                        onTap: () => _openSession(row.day, row.record),
                      ),
                      _HistoryUnplannedRow() => _UnplannedTile(
                        activity: row.activity,
                        onTap: () => _openUnplanned(row.day, row.activity),
                      ),
                    };
                  },
                ),
        ),
      ],
    );
  }

  /// Öffnet das bestehende Erfassungs-Sheet. Bei einer Sitzung ohne
  /// Aufzeichnung wird `started_at` auf das Sitzungsdatum mit der aktuellen
  /// Uhrzeit (lokaler Offset) gesetzt – nicht auf „jetzt“.
  void _openSession(HistoryDayRecord day, HistorySessionRecord record) {
    final repository = context.read<AppRepository>();
    final now = repository.now;
    final startedAt =
        record.activity?.startedAt ??
        isoWithOffset(
          DateTime(
            day.date.year,
            day.date.month,
            day.date.day,
            now.hour,
            now.minute,
            now.second,
          ),
        );
    showActivityEntrySheet(
      context,
      day: day.date,
      planned: TodaySession(plan: record.plan, session: record.session),
      startedAt: startedAt,
    );
  }

  void _openUnplanned(HistoryDayRecord day, Activity activity) {
    showActivityEntrySheet(context, day: day.date, unplanned: activity);
  }
}

/// Flacht Tage in Zeilen (Tageskopf, Sitzungen, ungeplante Einheiten).
List<_HistoryRow> _buildRows(List<HistoryDayRecord> days) {
  final rows = <_HistoryRow>[];
  for (final day in days) {
    rows.add(_HistoryDayRow(day));
    for (final record in day.sessions) {
      rows.add(_HistorySessionRow(day, record));
    }
    for (final activity in day.unplanned) {
      rows.add(_HistoryUnplannedRow(day, activity));
    }
  }
  return rows;
}

sealed class _HistoryRow {
  const _HistoryRow();
}

class _HistoryDayRow extends _HistoryRow {
  const _HistoryDayRow(this.day);
  final HistoryDayRecord day;
}

class _HistorySessionRow extends _HistoryRow {
  const _HistorySessionRow(this.day, this.record);
  final HistoryDayRecord day;
  final HistorySessionRecord record;
}

class _HistoryUnplannedRow extends _HistoryRow {
  const _HistoryUnplannedRow(this.day, this.activity);
  final HistoryDayRecord day;
  final Activity activity;
}

/// Tageskopf: Wochentag, Datum + Indikatoren für das Tagebuch.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final HistoryDayRecord day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feeling = day.lastFeeling;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              formatDateGerman(day.date),
              key: ValueKey<String>('history-day-${day.dateIso}'),
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (feeling != null) ...<Widget>[
            Container(
              key: ValueKey<String>('history-feeling-${day.dateIso}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                formatPercent(feeling),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (day.hasJournalText)
            Tooltip(
              message: 'Tagebucheintrag vorhanden',
              child: Icon(
                Icons.sticky_note_2_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Eine geplante Sitzung mit Plan/Ist-Vergleich.
class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.record, required this.onTap});

  final HistorySessionRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = record.status;
    final planned = 'Plan ${formatMinutesWithUnit(record.plannedSeconds)}';
    final actual = record.actualSeconds;
    final delta = record.deltaLabelDe;
    final actualText = actual == null
        ? null
        : 'Ist ${formatMinutesWithUnit(actual)}'
              '${delta == null ? '' : ' ($delta)'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('history-session-${record.session.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              children: <Widget>[
                Icon(
                  sportIcon(record.session.sport),
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        record.title,
                        style: theme.textTheme.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        actualText == null ? planned : '$planned · $actualText',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (status == null)
                  // UNBEKANNT – bewusst keine Wertung und kein Badge.
                  Text(
                    kNoRecordingLabelDe,
                    key: ValueKey<String>(
                      'history-unknown-${record.session.id}',
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  _StatusBadge(status: status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ungeplante Aktivität eines Tages.
class _UnplannedTile extends StatelessWidget {
  const _UnplannedTile({required this.activity, required this.onTap});

  final Activity activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sport = sportFromWireName(activity.sport);
    final duration =
        activity.elapsedDurationSeconds ?? activity.movingDurationSeconds;
    final label = sportLabelFromWireName(activity.sport);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('history-unplanned-${activity.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
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
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              label.isEmpty ? 'Sonstiges' : label,
                              style: theme.textTheme.bodyLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Text(
                              'ungeplant',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (duration != null)
                        Text(
                          formatMinutesWithUnit(duration),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: activity.status),
              ],
            ),
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

/// Zusammenfassung des Zeitraums.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.days});

  final RangeSummary summary;
  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('historySummary'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(summary.countsLabelDe, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              summary.minutesLabelDe,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (summary.unknown > 0) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'offen = keine Aufzeichnung (unbekannt, nicht ausgelassen)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (days == 0) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Keine Inhalte im gewählten Zeitraum.',
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

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

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
              Icons.insights_outlined,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('Noch kein Verlauf', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Sobald ein Plan importiert und Einheiten erfasst sind, '
              'erscheint hier der Vergleich von Plan und Ist.',
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
