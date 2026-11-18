import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/models.dart';
import '../services/history_service.dart';
import '../state/app_repository.dart';
import '../utils/formats.dart';
import 'activity_sheet.dart';
import 'plan_detail_sheet.dart';
import 'today_screen.dart' show sportIcon;

/// Verlaufs-Tab als Zeitscheibe um heute (−7/+7, −30/+30 oder „Alles“).
///
/// Alle Ableitungen (Zeitraum, Tage, Zeilen, Zähler, Minuten, Index des
/// heutigen Tages) kommen aus [HistoryRangeX.window], [buildHistoryDays],
/// [buildHistoryRows], [indexOfTodayRow] und [summarizeHistory] – im `build()`
/// steht keine Logik.
///
/// Die Liste ist aufsteigend (Vergangenheit oben, Zukunft unten) und wird mit
/// `ScrollablePositionedList` auf den heutigen Tag zentriert: die Liste erhält
/// oben und unten je eine halbe Viewport-Höhe Padding, damit der heutige
/// Tageskopf auch bei kurzem Inhalt exakt auf `initialAlignment` liegen kann.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  HistoryRange _range = HistoryRange.last30Days;

  /// Korrigiert die geschätzte Startposition nach dem ersten Frame: der
  /// heutige Tag sitzt danach exakt auf [_todayAlignment].
  final ItemScrollController _itemScrollController = ItemScrollController();
  bool _centerPending = true;

  /// Leicht über der Mitte: der heutige Block (Kopf + Zeilen) wirkt dadurch
  /// insgesamt mittig, nicht nur seine Oberkante.
  static const double _todayAlignment = 0.45;

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
    final rows = buildHistoryRows(days);
    final hasContent = days.any((day) => day.hasContent);
    final todayIndex = indexOfTodayRow(rows);

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
                onSelectionChanged: (selection) => setState(() {
                  _range = selection.first;
                  // Neuer Zeitraum → erneut auf heute zentrieren.
                  _centerPending = true;
                }),
              ),
              const SizedBox(height: 12),
              _SummaryCard(summary: summary, days: days.length),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Halbe Viewport-Höhe oben/unten: nur so kann der heutige
              // Tageskopf auch dann auf 45 % liegen, wenn der Zeitraum wenige
              // Zeilen enthält (sonst würde die Scroll-Position geklemmt).
              final filler = constraints.maxHeight * 0.5;
              if (_centerPending) {
                _centerPending = false;
                _jumpToToday(todayIndex);
              }
              return ScrollablePositionedList.builder(
                // Neuer Key je Zeitraum → die Liste wird frisch mit dem
                // heutigen Tag als Startposition aufgebaut.
                key: ValueKey<String>('historyList-${_range.name}'),
                itemScrollController: _itemScrollController,
                initialScrollIndex: todayIndex < 0 ? 0 : todayIndex,
                initialAlignment: _todayAlignment,
                padding: EdgeInsets.fromLTRB(16, filler, 16, filler + 24),
                itemCount: rows.length + (hasContent ? 0 : 1),
                itemBuilder: (context, index) {
                  if (index >= rows.length) return const _HistoryEmptyState();
                  return switch (rows[index]) {
                    HistoryDayRow(:final day) => _DayHeader(day: day),
                    HistorySessionRow(:final day, :final record) =>
                      _SessionTile(
                        day: day,
                        record: record,
                        onTap: () => _openSession(day, record),
                      ),
                    HistoryUnplannedRow(:final day, :final activity) =>
                      _UnplannedTile(
                        activity: activity,
                        onTap: () => _openUnplanned(day, activity),
                      ),
                  };
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Zentriert die Liste nach dem Layout auf den heutigen Tageskopf.
  ///
  /// Der Sprung passiert zweimal: direkt nach dem ersten Frame und noch einmal
  /// kurz danach. `ScrollablePositionedList` korrigiert seine geschätzte
  /// Startposition selbst über mehrere Frames – der zweite Sprung setzt die
  /// exakte Position danach.
  void _jumpToToday(int index) {
    if (index < 0) return;
    void jump() {
      if (!mounted || !_itemScrollController.isAttached) return;
      _itemScrollController.jumpTo(index: index, alignment: _todayAlignment);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => jump());
    Future<void>.delayed(const Duration(milliseconds: 250), jump);
  }

  /// Vergangenheit/heute → Erfassungs-Sheet, Zukunft → rein lesendes Sheet
  /// „Planung ansehen“ (kein Erfassen/Abhaken für zukünftige Tage).
  void _openSession(HistoryDayRecord day, HistorySessionRecord record) {
    if (day.isFuture) {
      showPlanDetailSheet(
        context,
        plan: record.plan,
        session: record.session,
        date: day.date,
      );
      return;
    }

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

/// Tageskopf: Wochentag/Datum, „Heute“-Kennzeichnung, „· geplant“ für die
/// Zukunft und Indikatoren für das Tagebuch.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final HistoryDayRecord day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feeling = day.lastFeeling;
    final muted = theme.colorScheme.onSurfaceVariant;
    final futureColor = muted.withValues(alpha: 0.55);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                formatDateGerman(day.date),
                key: ValueKey<String>('history-day-${day.dateIso}'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: day.isFuture ? futureColor : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (day.isToday) ...<Widget>[
              const SizedBox(width: 8),
              Container(
                key: const Key('history-today-chip'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Heute',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
            if (day.isFuture) ...<Widget>[
              const SizedBox(width: 6),
              Text(
                '· geplant',
                style: theme.textTheme.labelSmall?.copyWith(color: futureColor),
              ),
            ],
            if (feeling != null) ...<Widget>[
              const SizedBox(width: 6),
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
            ],
            if (day.hasJournalText) ...<Widget>[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Tagebucheintrag vorhanden',
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 16,
                  color: muted,
                ),
              ),
            ],
            if (day.hasFinalizedJournal) ...<Widget>[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Tagesnotiz abgeschlossen',
                child: Icon(
                  Icons.check_circle,
                  key: ValueKey<String>('history-journal-final-${day.dateIso}'),
                  size: 14,
                  color: muted,
                ),
              ),
            ],
          ],
        ),
        if (day.isToday && !day.hasContent)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'keine Einheit geplant',
              key: const Key('history-today-empty'),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
      ],
    );

    if (!day.isToday) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
        child: content,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.55),
          ),
        ),
        child: content,
      ),
    );
  }
}

/// Eine geplante Sitzung. Vergangenheit/heute mit Plan/Ist-Vergleich,
/// Zukunft gedämpft und ohne Status (nur „geplant“).
class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.day,
    required this.record,
    required this.onTap,
  });

  final HistoryDayRecord day;
  final HistorySessionRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final future = day.isFuture;
    final titleColor = future ? muted.withValues(alpha: 0.6) : null;
    final detailColor = future ? muted.withValues(alpha: 0.55) : muted;
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
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: future ? 0.2 : 0.4,
        ),
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
                  color: future ? detailColor : theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        record.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: titleColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        actualText == null ? planned : '$planned · $actualText',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: detailColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (future)
                  // Zukunft hat keinen Status – neutral „geplant“, NICHT
                  // „ohne Aufzeichnung“ (das wäre bei Zukunft falsch).
                  Text(
                    'geplant',
                    key: ValueKey<String>(
                      'history-planned-${record.session.id}',
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: future ? muted.withValues(alpha: 0.55) : muted,
                    ),
                  )
                else if (status == null)
                  // UNBEKANNT – bewusst keine Wertung und kein Badge.
                  Text(
                    kNoRecordingLabelDe,
                    key: ValueKey<String>(
                      'history-unknown-${record.session.id}',
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
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

/// Zusammenfassung des Zeitraums (Statuszähler nur für Tage ≤ heute).
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
