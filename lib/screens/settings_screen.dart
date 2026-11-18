import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/reminder_service.dart';
import '../state/app_repository.dart';
import '../state/settings_controller.dart';
import '../utils/formats.dart';

/// Einstellungen: Erinnerungszeiten (nur Android löst sie aus), App-Infos.
///
/// Alle Änderungen werden sofort persistiert – es gibt bewusst keinen
/// „Speichern“-Knopf.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.version = '1.0.0'});

  /// Angezeigte App-Version (bewusst hart kodiert, passend zur pubspec).
  final String version;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Öffnet die Zeitwahl (deutsche MaterialLocalizations via `flutter_localizations`).
  Future<void> _pickTime({required bool morning}) async {
    final controller = context.read<SettingsController>();
    final settings = controller.settings;
    final initial = morning
        ? TimeOfDay(hour: settings.morningHour, minute: settings.morningMinute)
        : TimeOfDay(hour: settings.eveningHour, minute: settings.eveningMinute);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: morning ? 'Morgen-Übersicht' : 'Tagesnotiz-Erinnerung',
      cancelText: 'Abbrechen',
      confirmText: 'Übernehmen',
      builder: (dialogContext, child) => MediaQuery(
        data: MediaQuery.of(
          dialogContext,
        ).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    if (morning) {
      controller.setMorningTime(picked.hour, picked.minute);
    } else {
      controller.setEveningTime(picked.hour, picked.minute);
    }
  }

  Future<void> _showPreview() async {
    final repository = context.read<AppRepository>();
    final settings = context.read<SettingsController>().settings;
    final reminders = planReminders(
      state: repository.state,
      now: repository.now,
      settings: settings,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          key: const Key('reminderPreviewDialog'),
          title: const Text('Vorschau: heutige Erinnerungen'),
          content: reminders.isEmpty
              ? const Text(
                  'Heute keine Erinnerungen geplant.\n\n'
                  'Morgens erscheint nur dann eine Übersicht, wenn Einheiten '
                  'geplant sind; abends nur, solange die Tagesnotiz fehlt oder '
                  'Entwurf ist.',
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final reminder in reminders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${formatTime(reminder.dueAt)} · ${reminder.title}',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              reminder.body,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    Text(
                      'Nur die Android-App löst diese Meldungen tatsächlich '
                      'aus – hier ist es eine reine Vorschau.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
          actions: <Widget>[
            TextButton(
              key: const Key('closePreview'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Schließen'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        key: const Key('settingsList'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          Text('Erinnerungen', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Erinnerungen werden nur in der Android-App ausgelöst. '
                      'In der PWA/Browser erscheinen sie nicht.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('morningSwitch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Morgen-Übersicht'),
            subtitle: const Text('Zeigt morgens die geplanten Einheiten.'),
            value: settings.morningEnabled,
            onChanged: controller.setMorningEnabled,
          ),
          ListTile(
            key: const Key('morningTime'),
            contentPadding: EdgeInsets.zero,
            enabled: settings.morningEnabled,
            title: const Text('Uhrzeit'),
            subtitle: const Text('Tägliche Zusammenfassung des Plans'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _formatSettingTime(
                    settings.morningHour,
                    settings.morningMinute,
                  ),
                  style: theme.textTheme.titleMedium,
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: settings.morningEnabled
                ? () => _pickTime(morning: true)
                : null,
          ),
          const Divider(),
          SwitchListTile(
            key: const Key('eveningSwitch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Tagesnotiz-Erinnerung'),
            subtitle: const Text(
              'Erinnert abends an die Tagesnotiz, solange sie nicht '
              'abgeschlossen ist.',
            ),
            value: settings.eveningEnabled,
            onChanged: controller.setEveningEnabled,
          ),
          ListTile(
            key: const Key('eveningTime'),
            contentPadding: EdgeInsets.zero,
            enabled: settings.eveningEnabled,
            title: const Text('Uhrzeit'),
            subtitle: const Text('Erinnerung an die Tagesnotiz'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _formatSettingTime(
                    settings.eveningHour,
                    settings.eveningMinute,
                  ),
                  style: theme.textTheme.titleMedium,
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: settings.eveningEnabled
                ? () => _pickTime(morning: false)
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            key: const Key('previewReminders'),
            onPressed: _showPreview,
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Vorschau: heutige Erinnerungen'),
          ),
          const SizedBox(height: 32),
          Text('App', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Version'),
            trailing: Text(widget.version),
          ),
          Text(
            'Daten bleiben lokal: Pläne, Aktivitäten, Tagebuch und '
            'Einstellungen liegen ausschließlich auf diesem Gerät. '
            'Es gibt kein Backend und keine Anmeldung.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSettingTime(int hour, int minute) =>
      '${twoDigits(hour)}:${twoDigits(minute)}';
}
