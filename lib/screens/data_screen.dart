import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/download_helper.dart';
import '../services/import_service.dart';
import '../services/merge_service.dart';
import '../state/app_repository.dart';
import '../utils/formats.dart';

/// Daten-Tab: Import (mit Vorschau), JSON-/Markdown-Export, alles löschen.
class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

enum _RangeChoice { all, custom }

class _DataScreenState extends State<DataScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final state = repository.state;
    final theme = Theme.of(context);
    final sessionCount = state.plans.fold<int>(
      0,
      (sum, plan) => sum + plan.sessions.length,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Text('Daten', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          '${pluralPlanRevisionen(state.plans.length)} · '
          '${pluralSitzungen(sessionCount)} · '
          '${pluralAktivitaeten(state.activities.length)} · '
          '${pluralEintraege(state.journal.length)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _importPlan,
          icon: const Icon(Icons.upload_file),
          label: const Text('Plan importieren'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _export(markdown: false),
          icon: const Icon(Icons.download),
          label: const Text('JSON exportieren'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _export(markdown: true),
          icon: const Icon(Icons.description_outlined),
          label: const Text('Markdown exportieren'),
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _busy ? null : _clearAll,
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Alle Daten löschen'),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        ),
      ],
    );
  }

  // ─── Import ────────────────────────────────────────────────────────────────

  Future<void> _importPlan() async {
    final repository = context.read<AppRepository>();
    setState(() => _busy = true);

    var jsonText = '';
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.first.bytes;
      if (bytes == null) {
        _showSnack('Die Datei konnte nicht gelesen werden.');
        return;
      }
      jsonText = utf8.decode(bytes, allowMalformed: true);
    } catch (error) {
      _showSnack('Datei konnte nicht ausgewählt werden: $error');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || jsonText.isEmpty) return;

    final result = repository.parseImport(jsonText);
    if (!mounted) return;

    if (result.hasErrors) {
      await _showErrorDialog(result.errors);
      return;
    }

    final merge = repository.previewImport(result);
    if (!mounted) return;

    if (merge.hasConflict) {
      await _showConflictDialog(merge);
      return;
    }

    final confirmed = await _showPreviewDialog(merge, result);
    if (!mounted || confirmed != true) return;

    final applied = repository.importPlans(result);
    if (!mounted) return;
    _showSnack(applied.summaryDe);
  }

  Future<void> _showErrorDialog(List<String> errors) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import nicht möglich'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final error in errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $error'),
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Future<void> _showConflictDialog(MergeResult merge) {
    final conflicts = merge.plans
        .where((plan) => plan.status == PlanImportStatus.conflict)
        .toList();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import blockiert'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final plan in conflicts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      plan.conflictMessage ??
                          'Revision ${plan.revision} von ${plan.planId} '
                              'existiert bereits mit anderem Inhalt.',
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Der Import wurde nicht übernommen. Bitte die Revision im '
                  'Plan erhöhen und erneut importieren.',
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showPreviewDialog(MergeResult merge, ImportResult result) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import-Vorschau'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final plan in merge.plans) _PlanDiffRow(diff: plan),
                const SizedBox(height: 12),
                Text(
                  'Betroffene Tage: ${merge.affectedDayCount}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (merge.addedActivities > 0)
                  Text('Neue Aktivitäten: ${merge.addedActivities}'),
                if (merge.addedJournalEntries > 0)
                  Text('Neue Tagebucheinträge: ${merge.addedJournalEntries}'),
                if (result.ignoredUnknownFields > 0)
                  Text(
                    'Ignorierte unbekannte Felder: '
                    '${result.ignoredUnknownFields}',
                  ),
                if (merge.allWarnings.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  const Text(
                    'Hinweise',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  for (final warning in merge.allWarnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $warning'),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
  }

  // ─── Export ────────────────────────────────────────────────────────────────

  Future<void> _export({required bool markdown}) async {
    final repository = context.read<AppRepository>();
    final now = repository.now;

    final choice = await showDialog<_RangeChoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Zeitraum für den Export'),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(_RangeChoice.all),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Alle Daten'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_RangeChoice.custom),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Zeitraum wählen …'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;

    DateTimeRange? range;
    if (choice == _RangeChoice.custom) {
      range = await _pickRange(now);
      if (!mounted || range == null) return;
    }

    final content = markdown
        ? repository.exportMarkdown(from: range?.start, to: range?.end)
        : repository.exportJson(from: range?.start, to: range?.end);
    final filename = markdown
        ? repository.exportFileNameMarkdown()
        : repository.exportFileNameJson();

    try {
      downloadTextFile(
        filename: filename,
        content: content,
        mimeType: markdown ? 'text/markdown' : 'application/json',
      );
      _showSnack('Export gestartet: $filename');
    } on UnsupportedError {
      _showSnack(
        'Download wird auf dieser Plattform nicht unterstützt. '
        'Nutze die Web-Version.',
      );
    } catch (error) {
      _showSnack('Export fehlgeschlagen: $error');
    }
  }

  /// Datumsbereich ohne `flutter_localizations` – der Material-Picker nutzt
  /// die eingebauten (englischen) Default-Lokalisierungen. Falls er in einer
  /// Umgebung doch nicht verfügbar ist, gibt es einen einfachen Fallback.
  Future<DateTimeRange?> _pickRange(DateTime now) async {
    final firstDate = DateTime(now.year - 3);
    final lastDate = DateTime(now.year + 2, 12, 31);
    try {
      return await showDateRangePicker(
        context: context,
        firstDate: firstDate,
        lastDate: lastDate,
        initialDateRange: DateTimeRange(
          start: now.subtract(const Duration(days: 28)),
          end: now,
        ),
        helpText: 'Zeitraum wählen',
        saveText: 'Übernehmen',
      );
    } catch (_) {
      if (!mounted) return null;
      final start = await showDatePicker(
        context: context,
        firstDate: firstDate,
        lastDate: lastDate,
        initialDate: now.subtract(const Duration(days: 28)),
        helpText: 'Startdatum',
      );
      if (!mounted || start == null) return null;
      final end = await showDatePicker(
        context: context,
        firstDate: start,
        lastDate: lastDate,
        initialDate: now,
        helpText: 'Enddatum',
      );
      if (end == null) return null;
      return DateTimeRange(start: start, end: end);
    }
  }

  // ─── Löschen ───────────────────────────────────────────────────────────────

  Future<void> _clearAll() async {
    final repository = context.read<AppRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Alle Daten löschen?'),
        content: const Text(
          'Pläne, Aktivitäten und Tagebucheinträge werden unwiderruflich '
          'vom Gerät entfernt.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await repository.clearAll();
    if (!mounted) return;
    _showSnack('Alle Daten wurden gelöscht.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PlanDiffRow extends StatelessWidget {
  const _PlanDiffRow({required this.diff});

  final PlanDiff diff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counters = <String>[
      '+${diff.addedSessions}',
      '~${diff.changedSessions}',
      '−${diff.removedSessions}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  '${diff.title.isEmpty ? diff.planId : diff.title} '
                  '(Rev. ${diff.revision})',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                diff.status.labelDe,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          Text(
            '${diff.planId} · ${counters.join(' / ')} Sitzungen · '
            '${pluralTage(diff.affectedDates.length)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final warning in diff.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $warning',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
