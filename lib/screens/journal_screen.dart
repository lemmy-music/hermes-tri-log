import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/history_service.dart';
import '../state/app_repository.dart';
import '../utils/formats.dart';
import 'journal_sheet.dart';

/// Tagebuch-Tab: ganz oben die „Tagesnotiz“ von heute (Entwurf oder
/// abgeschlossen), darunter alle übrigen Einträge nach Tag gruppiert (neueste
/// zuerst). Der heutige Eintrag der Tagesnotiz erscheint bewusst NICHT doppelt
/// in der Liste.
class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final theme = Theme.of(context);

    final todayEntry = repository.todayJournalEntry;
    final groups = groupJournalByDay(repository.state.journal);

    // Heutigen Eintrag der Tagesnotiz aus der chronologischen Liste nehmen –
    // sonst stünde derselbe Eintrag zweimal auf dem Schirm.
    final listGroups = <JournalDayGroup>[];
    for (final group in groups) {
      final entries = <JournalEntry>[
        for (final entry in group.entries)
          if (entry.id != todayEntry?.id) entry,
      ];
      if (entries.isEmpty) continue;
      listGroups.add(
        JournalDayGroup(
          dateIso: group.dateIso,
          date: group.date,
          entries: entries,
        ),
      );
    }

    final rows = _buildRows(listGroups);
    final entryCount = repository.state.journal.length;
    final isEmpty = entryCount == 0;

    return ListView.builder(
      // 96 px unten: Freiraum, damit der FloatingActionButton nichts verdeckt.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: rows.length + 2 + (isEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Tagebuch', style: theme.textTheme.headlineSmall),
                if (!isEmpty)
                  Text(
                    '${pluralEintraege(entryCount)} an '
                    '${pluralTageDativ(groups.length)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        }
        if (index == 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: _DailyNoteCard(entry: todayEntry),
          );
        }
        if (index == 2 && isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: _JournalEmptyState(),
          );
        }
        final rowOffset = isEmpty ? 3 : 2;
        final row = rows[index - rowOffset];
        return switch (row) {
          _JournalDayRow() => _DayHeader(group: row.group),
          _JournalEntryRow() => _EntryTile(entry: row.entry),
        };
      },
    );
  }
}

/// Flacht die Tagesgruppen in eine Zeilenliste (Tageskopf + Einträge).
/// Bewusst außerhalb von `build()` – keine Logik im Widget-Aufbau.
List<_JournalRow> _buildRows(List<JournalDayGroup> groups) {
  final rows = <_JournalRow>[];
  for (final group in groups) {
    rows.add(_JournalDayRow(group));
    for (final entry in group.entries) {
      rows.add(_JournalEntryRow(entry));
    }
  }
  return rows;
}

sealed class _JournalRow {
  const _JournalRow();
}

class _JournalDayRow extends _JournalRow {
  const _JournalDayRow(this.group);
  final JournalDayGroup group;
}

class _JournalEntryRow extends _JournalRow {
  const _JournalEntryRow(this.entry);
  final JournalEntry entry;
}

/// Karte „Tagesnotiz“ für heute – genau ein Eintrag pro Tag:
/// * kein Eintrag → „Noch nichts notiert“
/// * Entwurf (`finalized_at == null`) → Badge „Entwurf“ + Vorschau
/// * abgeschlossen → Häkchen + „abgeschlossen um HH:MM“, gedämpft
class _DailyNoteCard extends StatelessWidget {
  const _DailyNoteCard({required this.entry});

  final JournalEntry? entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final current = entry;
    final finalized = current?.isFinalized ?? false;
    final text = current?.text?.trim();

    final background = finalized
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
        : scheme.primaryContainer.withValues(alpha: 0.45);

    return Card(
      elevation: 0,
      color: background,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('dailyNoteCard'),
        onTap: () => showJournalEntrySheet(context, entry: current),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // Bei „abgeschlossen“ steht das Häkchen ausschließlich in der
                  // Statuszeile („abgeschlossen um HH:MM“) – kein zweites Icon
                  // im Titel, das wirkt doppelt.
                  if (!finalized) ...<Widget>[
                    Icon(
                      Icons.edit_note,
                      size: 20,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      'Tagesnotiz',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: finalized ? muted : null,
                      ),
                    ),
                  ),
                  if (current == null)
                    Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: scheme.primary,
                    )
                  else if (!finalized)
                    _Badge(
                      key: const Key('dailyNoteDraftBadge'),
                      label: 'Entwurf',
                      background: scheme.secondaryContainer,
                      foreground: scheme.onSecondaryContainer,
                    ),
                ],
              ),
              if (current == null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  'Noch nichts notiert',
                  key: const Key('dailyNoteEmpty'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 2),
                Text(
                  'Antippen und den Tag über ergänzen – abends abschließen.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ] else ...<Widget>[
                if (finalized) ...<Widget>[
                  const SizedBox(height: 4),
                  Row(
                    key: const Key('dailyNoteFinalizedBadge'),
                    children: <Widget>[
                      Icon(Icons.check_circle, size: 14, color: muted),
                      const SizedBox(width: 5),
                      Text(
                        'abgeschlossen um ${_timeLabel(current.finalizedLocal)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ],
                if (text != null && text.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: finalized ? muted : null,
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'Noch kein Text – kurz notieren, was auffällt.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    _FeelingChip(feeling: current.overallFeeling),
                    const Spacer(),
                    if (_showLastChanged(current))
                      Flexible(
                        child: Text(
                          'zuletzt geändert ${_timeLabel(current.lastChangedLocal)}',
                          key: const Key('dailyNoteLastChanged'),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
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

  /// Beim Abschluss nur zeigen, wenn die letzte Änderung danach/davor
  /// abweicht – sonst wäre die Zeile nur Rauschen.
  bool _showLastChanged(JournalEntry entry) {
    final changed = entry.lastChangedLocal;
    if (changed == null) return false;
    final finalized = entry.finalizedLocal;
    if (finalized == null) return true;
    return !_sameMinute(changed, finalized);
  }
}

String _timeLabel(DateTime? time) => time == null ? '–' : formatTime(time);

bool _sameMinute(DateTime a, DateTime b) =>
    a.year == b.year &&
    a.month == b.month &&
    a.day == b.day &&
    a.hour == b.hour &&
    a.minute == b.minute;

/// „zuletzt 18:40“ (gleicher Tag) bzw. „zuletzt 16.11. 21:12“.
String _lastChangedLabel(DateTime changed, DateTime created) {
  if (changed.year == created.year &&
      changed.month == created.month &&
      changed.day == created.day) {
    return 'zuletzt ${formatTime(changed)}';
  }
  return 'zuletzt ${twoDigits(changed.day)}.${twoDigits(changed.month)}. '
      '${formatTime(changed)}';
}

class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Tageskopf, z. B. `Mo, 16.11.2026` (+ Befinden des letzten Eintrags).
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.group});

  final JournalDayGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              formatDateGerman(group.date),
              key: ValueKey<String>('journal-day-${group.dateIso}'),
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (group.lastFeeling != null)
            Text(
              'Tag ${formatPercent(group.lastFeeling)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Ein Eintrag: Uhrzeit · Befinden-Chip · „zuletzt“ · Text (2 Zeilen).
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final local = DateTime.tryParse(entry.timestamp)?.toLocal();
    final changed = entry.lastChangedLocal;
    final autoFinalized = entry.isAutomaticallyFinalized;
    final showChanged =
        !autoFinalized &&
        local != null &&
        changed != null &&
        changed.isAfter(local);
    final text = entry.text?.trim();
    final feeling = entry.overallFeeling;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('journal-entry-${entry.id}'),
          onTap: () => showJournalEntrySheet(context, entry: entry),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      local == null ? '–' : formatTime(local),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FeelingChip(feeling: feeling),
                    if (showChanged) ...<Widget>[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _lastChangedLabel(changed, local),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (entry.isFinalized) ...<Widget>[
                      Tooltip(
                        message: autoFinalized
                            ? 'automatisch abgeschlossen'
                            : 'Tagesnotiz abgeschlossen',
                        child: Icon(
                          Icons.check_circle,
                          key: ValueKey<String>(
                            'journal-entry-final-${entry.id}',
                          ),
                          size: 14,
                          color: muted,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Icon(Icons.edit_outlined, size: 16, color: muted),
                  ],
                ),
                // Eigene Statuszeile statt Häkchen-Tooltip: der Abschluss kam
                // von der App, der Athlet hat ihn nicht bestätigt.
                if (autoFinalized) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'automatisch abgeschlossen',
                    key: ValueKey<String>('journal-entry-auto-${entry.id}'),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
                if (text != null && text.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeelingChip extends StatelessWidget {
  const _FeelingChip({required this.feeling});

  final int? feeling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = feeling != null;
    final background = hasValue
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = hasValue
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      key: const Key('journalFeelingChip'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        formatPercent(feeling),
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

class _JournalEmptyState extends StatelessWidget {
  const _JournalEmptyState();

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
              Icons.book_outlined,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('Noch keine Einträge', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Einträge sind frei formuliert – Gefühl, Schlaf oder Beschwerden. '
              'Sie werden zusammen mit den Einheiten exportiert und geben dem '
              'Coach Kontext.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Neuer Eintrag über den Stift-Button unten rechts.',
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
