import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_repository.dart';
import '../utils/formats.dart';

/// Öffnet das Bottom Sheet „Tagebucheintrag“.
///
/// [entry] gesetzt → bestehenden Eintrag bearbeiten (Zeitstempel bleibt).
/// `null` → neuer Eintrag mit dem aktuellen Zeitpunkt.
Future<void> showJournalEntrySheet(
  BuildContext context, {
  JournalEntry? entry,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => JournalEntrySheet(entry: entry),
  );
}

/// Sheet für freie Tagebucheinträge: ein Gesamtbefinden-Slider 0–100
/// (bewusst optional, Start „nicht angegeben“) und ein mehrzeiliges Textfeld.
///
/// Keine Pflichtfelder, Rückmeldung IM Sheet, Sheet bleibt nach dem Speichern
/// offen. Ein Speichervorgang schreibt genau einen Eintrag.
class JournalEntrySheet extends StatefulWidget {
  const JournalEntrySheet({super.key, this.entry});

  final JournalEntry? entry;

  @override
  State<JournalEntrySheet> createState() => _JournalEntrySheetState();
}

class _JournalEntrySheetState extends State<JournalEntrySheet> {
  late final AppRepository _repository;
  final TextEditingController _text = TextEditingController();

  /// `null` = nicht angegeben (NICHT 0).
  int? _feeling;
  JournalEntry? _saved;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _repository = context.read<AppRepository>();
    _saved = widget.entry;
    _feeling = _saved?.overallFeeling;
    _text.text = _saved?.text ?? '';
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  // ─── Aktionen ──────────────────────────────────────────────────────────────

  void _save() {
    final text = _text.text.trim();
    final entry = JournalEntry(
      id: _saved?.id ?? _repository.nextJournalEntryId(),
      // Bestehende Einträge behalten ihren Zeitstempel.
      timestamp: _saved?.timestamp ?? isoWithOffset(_repository.now),
      overallFeeling: _feeling,
      text: text.isEmpty ? null : text,
    );
    _repository.saveJournalEntry(entry);

    final feelingLabel = formatPercent(entry.overallFeeling);
    setState(() {
      _saved = entry;
      _feedback = feelingLabel == '–'
          ? 'Gespeichert · Gesamtbefinden nicht angegeben'
          : 'Gespeichert · Gesamtbefinden $feelingLabel';
    });
  }

  Future<void> _delete() async {
    final saved = _saved;
    if (saved == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tagebucheintrag löschen?'),
        content: const Text(
          'Der Eintrag mit Gesamtbefinden und Text wird unwiderruflich '
          'entfernt.',
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

    _repository.deleteJournalEntry(saved.id);
    setState(() {
      _saved = null;
      _feeling = null;
      _text.clear();
      _feedback = 'Gelöscht';
    });
  }

  // ─── Aufbau ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reference = DateTime.tryParse(_saved?.timestamp ?? '')?.toLocal();
    final subtitle = reference != null
        ? '${formatDateGerman(reference)} · ${formatTime(reference)}'
        : formatDateGerman(_repository.now);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Tagebucheintrag',
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Schließen',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _FeelingField(
                      value: _feeling,
                      onChanged: (value) => setState(() => _feeling = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('journalTextField'),
                      controller: _text,
                      minLines: 3,
                      maxLines: 8,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Notiz (optional)',
                        hintText:
                            'Gefühl, Schlaf, Beschwerden – frei formuliert.',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Einträge werden mit exportiert und stehen dem Coach '
                      'als Kontext zur Verfügung.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_feedback != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Container(
                  key: const Key('journalFeedback'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _feedback!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: <Widget>[
                  if (_saved != null)
                    TextButton.icon(
                      key: const Key('journalDeleteButton'),
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Löschen'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    key: const Key('journalDoneButton'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fertig'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('journalSaveButton'),
                    onPressed: _save,
                    icon: const Icon(Icons.check),
                    label: const Text('Speichern'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gesamtbefinden-Slider 0–100. Start bewusst ohne Wert („nicht angegeben“);
/// erstes Verschieben setzt einen Wert, „Zurücksetzen“ entfernt ihn wieder.
class _FeelingField extends StatelessWidget {
  const _FeelingField({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Gesamtbefinden', style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value == null ? 'nicht angegeben' : formatPercent(value),
                key: const Key('journalFeelingValue'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: value == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                  fontWeight: value == null ? null : FontWeight.w600,
                ),
              ),
            ),
            if (value != null)
              TextButton(
                key: const Key('journalResetFeeling'),
                onPressed: () => onChanged(null),
                child: const Text('Zurücksetzen'),
              ),
          ],
        ),
        Slider(
          key: const Key('journalFeelingSlider'),
          min: 0,
          max: 100,
          divisions: 20,
          value: (value ?? 50).toDouble(),
          label: value == null ? '' : formatPercent(value),
          onChanged: (next) => onChanged(next.round()),
        ),
        Text(
          '0 % = sehr schlecht … 100 % = sehr gut',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
