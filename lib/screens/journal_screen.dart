import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/history_service.dart';
import '../state/app_repository.dart';
import '../utils/formats.dart';
import 'journal_sheet.dart';

/// Tagebuch-Tab: alle Einträge nach Tag gruppiert (neueste zuerst), je Eintrag
/// Uhrzeit, Gesamtbefinden-Chip und Text (max. 2 Zeilen, Tap → Bearbeiten).
class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final theme = Theme.of(context);
    final groups = groupJournalByDay(repository.state.journal);

    if (groups.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          Text('Tagebuch', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          const _JournalEmptyState(),
        ],
      );
    }

    final rows = _buildRows(groups);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Tagebuch', style: theme.textTheme.headlineSmall),
                Text(
                  '${groups.fold<int>(0, (sum, group) => sum + group.entries.length)} '
                  'Eintrag/Einträge an ${groups.length} Tag(en)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }
        final row = rows[index - 1];
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

/// Ein Eintrag: Uhrzeit · Befinden-Chip · Text (2 Zeilen, Tap → Sheet).
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = DateTime.tryParse(entry.timestamp)?.toLocal();
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
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FeelingChip(feeling: feeling),
                    const Spacer(),
                    Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
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
