import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_repository.dart';
import '../utils/formats.dart';
import '../widgets/plan_summary.dart';

/// Öffnet das Bottom Sheet „Einheit erfassen“.
///
/// [planned] gesetzt → Ist-Daten einer geplanten Sitzung erfassen/bearbeiten.
/// [unplanned] oder beides `null` → ungeplante Einheit (mit Sport-Auswahl).
///
/// [startedAt] (nur für eine neue Aktivität einer geplanten Sitzung) setzt den
/// Zeitstempel – etwa für vergangene Tage aus dem Verlauf. Eine bestehende
/// Aktivität behält ihren Zeitstempel immer.
Future<void> showActivityEntrySheet(
  BuildContext context, {
  required DateTime day,
  TodaySession? planned,
  Activity? unplanned,
  String? startedAt,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ActivityEntrySheet(
      day: day,
      planned: planned,
      unplanned: unplanned,
      startedAt: startedAt,
    ),
  );
}

/// Sheet zum Erfassen/Bearbeiten der Ist-Daten einer Einheit.
///
/// Bewusst ohne Pflichtfelder: nur der Status ist gesetzt, alles andere ist
/// optional. Rückmeldungen erscheinen IM Sheet (SnackBars lägen hinter dem
/// offenen Modal); das Sheet schließt nach dem Speichern nicht, damit direkt
/// weiter bearbeitet werden kann.
class ActivityEntrySheet extends StatefulWidget {
  const ActivityEntrySheet({
    super.key,
    required this.day,
    this.planned,
    this.unplanned,
    this.startedAt,
  });

  final DateTime day;
  final TodaySession? planned;
  final Activity? unplanned;

  /// Zeitstempel für eine neu anzulegende Aktivität (ISO mit lokalem Offset).
  final String? startedAt;

  @override
  State<ActivityEntrySheet> createState() => _ActivityEntrySheetState();
}

class _ActivityEntrySheetState extends State<ActivityEntrySheet> {
  late final AppRepository _repository;

  late ActivityStatus _status;
  late Sport _sport;
  final TextEditingController _duration = TextEditingController();
  final TextEditingController _moving = TextEditingController();
  final TextEditingController _distance = TextEditingController();
  final TextEditingController _heartRate = TextEditingController();
  final TextEditingController _power = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  int? _rpe;
  bool _showMore = false;
  Activity? _saved;
  String? _feedback;
  String? _durationError;

  bool get _isPlanned => widget.planned != null;

  Session? get _session => widget.planned?.session;

  int? get _plannedSeconds => _session?.plannedDurationSeconds;

  @override
  void initState() {
    super.initState();
    _repository = context.read<AppRepository>();
    _saved = _isPlanned
        ? _repository.activityForSession(_session!.id)
        : widget.unplanned;
    _applyValuesFrom(_saved, prefillPlan: true);
  }

  /// Setzt Status, Sport und alle Textfelder aus einer Aktivität (oder aus dem
  /// leeren Zustand, wenn [activity] `null` ist).
  void _applyValuesFrom(Activity? activity, {required bool prefillPlan}) {
    _status = activity?.status ?? ActivityStatus.completed;
    _sport =
        _session?.sport ?? sportFromWireName(activity?.sport) ?? Sport.other;

    int? duration = activity?.elapsedDurationSeconds;
    if (duration == null && activity != null) {
      duration = activity.movingDurationSeconds;
    }
    if (activity == null && prefillPlan && _status != ActivityStatus.skipped) {
      duration = _plannedSeconds;
    }
    _duration.text = minutesInputText(duration);
    _moving.text = minutesInputText(activity?.movingDurationSeconds);
    _distance.text = kilometersInputText(activity?.distanceMeters);
    _heartRate.text = activity?.averageHeartRateBpm?.toString() ?? '';
    _power.text = activity?.averagePowerWatts?.toString() ?? '';
    _notes.text = activity?.notes ?? '';
    _rpe = activity?.rpe;
    _durationError = null;
  }

  @override
  void dispose() {
    _duration.dispose();
    _moving.dispose();
    _distance.dispose();
    _heartRate.dispose();
    _power.dispose();
    _notes.dispose();
    super.dispose();
  }

  // ─── Aktionen ──────────────────────────────────────────────────────────────

  void _onStatusChanged(ActivityStatus status) {
    setState(() {
      final previous = _status;
      _status = status;
      _durationError = null;
      if (status == ActivityStatus.skipped) {
        _duration.clear();
      } else if (previous == ActivityStatus.skipped &&
          _duration.text.trim().isEmpty) {
        _duration.text = minutesInputText(_plannedSeconds);
      }
    });
  }

  void _save() {
    final isSkipped = _status == ActivityStatus.skipped;

    String? validate(TextEditingController controller, String label) {
      if (controller.text.trim().isEmpty) return null;
      final seconds = parseMinutesToSeconds(controller.text);
      if (seconds == null) return '$label: bitte eine Zahl (z. B. 35,5).';
      return null;
    }

    final durationText = _duration.text.trim();
    if (!isSkipped &&
        durationText.isNotEmpty &&
        parseMinutesToSeconds(durationText) == null) {
      setState(
        () => _durationError = 'Gesamtzeit: bitte eine Zahl (z. B. 35,5).',
      );
      return;
    }
    final movingError = isSkipped ? null : validate(_moving, 'Bewegungszeit');
    if (movingError != null) {
      setState(() => _durationError = movingError);
      return;
    }

    final notes = _notes.text.trim();
    final int? elapsed = isSkipped
        ? null
        : parseMinutesToSeconds(_duration.text);
    final int? moving = isSkipped ? null : parseMinutesToSeconds(_moving.text);
    final double? distance = isSkipped
        ? null
        : parseKilometersToMeters(_distance.text);
    final int? heartRate = isSkipped ? null : int.tryParse(_heartRate.text);
    final int? power = isSkipped ? null : int.tryParse(_power.text);

    final Activity activity;
    if (_isPlanned) {
      activity = _repository.saveActivityForSession(
        plan: widget.planned!.plan,
        session: _session!,
        status: _status,
        elapsedDurationSeconds: elapsed,
        movingDurationSeconds: moving,
        distanceMeters: distance,
        averageHeartRateBpm: heartRate,
        averagePowerWatts: power,
        rpe: isSkipped ? null : _rpe,
        notes: notes.isEmpty ? null : notes,
        startedAt: widget.startedAt,
      );
    } else {
      activity = Activity(
        id: _saved?.id ?? _repository.nextActivityId(),
        sport: _sport.wireName,
        startedAt: _saved?.startedAt ?? isoWithOffset(_repository.now),
        status: _status,
        elapsedDurationSeconds: elapsed,
        movingDurationSeconds: moving,
        distanceMeters: distance,
        averageHeartRateBpm: heartRate,
        averagePowerWatts: power,
        rpe: isSkipped ? null : _rpe,
        notes: notes.isEmpty ? null : notes,
      );
      _repository.saveActivity(activity);
    }

    final durationLabel = formatMinutesWithUnit(
      activity.elapsedDurationSeconds ?? activity.movingDurationSeconds,
    );
    setState(() {
      _saved = activity;
      _durationError = null;
      _feedback = durationLabel == '–'
          ? 'Gespeichert · ${activity.status.shortLabelDe}'
          : 'Gespeichert · ${activity.status.shortLabelDe} · $durationLabel';
    });
  }

  Future<void> _delete() async {
    final saved = _saved;
    if (saved == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Einheit löschen?'),
        content: const Text(
          'Die Ist-Daten dieser Einheit werden entfernt. Der Status ist danach '
          'wieder unbekannt.',
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

    _repository.deleteActivity(saved.id);
    setState(() {
      _saved = null;
      _applyValuesFrom(null, prefillPlan: true);
      _feedback = 'Gelöscht · Status unbekannt';
    });
  }

  // ─── Aufbau ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _session == null
        ? 'Ungeplante Einheit'
        : (_session!.type.trim().isEmpty
              ? _session!.sport.labelDe
              : _session!.type);

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
                          'Einheit erfassen',
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          '${formatDateGerman(widget.day)} · $title',
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
                    if (_isPlanned) ...<Widget>[
                      PlanSummary(
                        plan: widget.planned!.plan,
                        session: widget.planned!.session,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (!_isPlanned) ...<Widget>[
                      DropdownButtonFormField<Sport>(
                        key: const Key('sportDropdown'),
                        initialValue: _sport,
                        decoration: const InputDecoration(
                          labelText: 'Sport',
                          border: OutlineInputBorder(),
                        ),
                        items: <DropdownMenuItem<Sport>>[
                          for (final sport in Sport.values)
                            DropdownMenuItem<Sport>(
                              value: sport,
                              child: Text(sport.labelDe),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _sport = value);
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text('Status', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    SegmentedButton<ActivityStatus>(
                      key: const Key('statusSegments'),
                      showSelectedIcon: false,
                      segments: <ButtonSegment<ActivityStatus>>[
                        for (final status in ActivityStatus.values)
                          ButtonSegment<ActivityStatus>(
                            value: status,
                            label: Text(status.shortLabelDe),
                          ),
                      ],
                      selected: <ActivityStatus>{_status},
                      onSelectionChanged: (selection) =>
                          _onStatusChanged(selection.first),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('durationField'),
                      controller: _duration,
                      enabled: _status != ActivityStatus.skipped,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Gesamtzeit (min)',
                        hintText: 'z. B. 35,5',
                        border: const OutlineInputBorder(),
                        errorText: _durationError,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _RpeField(
                      value: _rpe,
                      onChanged: (value) => setState(() => _rpe = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('notesField'),
                      controller: _notes,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notiz (optional)',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      key: const Key('moreExpansion'),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      initiallyExpanded: _showMore,
                      onExpansionChanged: (expanded) =>
                          setState(() => _showMore = expanded),
                      title: Text(
                        'Mehr Angaben',
                        style: theme.textTheme.labelLarge,
                      ),
                      children: <Widget>[
                        TextField(
                          key: const Key('movingField'),
                          controller: _moving,
                          enabled: _status != ActivityStatus.skipped,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Bewegungszeit (min)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('distanceField'),
                          controller: _distance,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Distanz (km)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                key: const Key('heartRateField'),
                                controller: _heartRate,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Ø-Puls (bpm)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                key: const Key('powerField'),
                                controller: _power,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Ø-Leistung (W)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_feedback != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Container(
                  key: const Key('sheetFeedback'),
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
                      key: const Key('deleteButton'),
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Löschen'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    key: const Key('doneButton'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fertig'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('saveButton'),
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

/// RPE-Slider 1–10 mit klarer „nicht angegeben“-Darstellung.
class _RpeField extends StatelessWidget {
  const _RpeField({required this.value, required this.onChanged});

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
            Text('RPE', style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value == null ? 'nicht angegeben' : '$value von 10',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (value != null)
              TextButton(
                onPressed: () => onChanged(null),
                child: const Text('Zurücksetzen'),
              ),
          ],
        ),
        Slider(
          key: const Key('rpeSlider'),
          min: 1,
          max: 10,
          divisions: 9,
          value: (value ?? 1).toDouble(),
          label: value == null ? '' : '$value',
          onChanged: (next) => onChanged(next.round()),
        ),
        Text(
          '1 = sehr locker … 10 = maximal',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
