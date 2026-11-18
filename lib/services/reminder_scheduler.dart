import 'reminder_service.dart';

/// Ergebnis eines Planungsversuchs durch einen [ReminderScheduler].
class ReminderScheduleResult {
  const ReminderScheduleResult({
    required this.supported,
    required this.scheduledCount,
    required this.message,
  });

  /// `false`, wenn die Plattform keine lokalen Benachrichtigungen anbietet.
  final bool supported;

  /// Anzahl der tatsächlich beim Betriebssystem hinterlegten Erinnerungen.
  final int scheduledCount;

  /// Kurze deutsche Rückmeldung für UI/Log (z. B. „nicht unterstützt“).
  final String message;

  @override
  String toString() =>
      'ReminderScheduleResult(supported: $supported, '
      'scheduled: $scheduledCount, $message)';
}

/// Schnittstelle zum Hinterlegen der geplanten Erinnerungen beim Betriebssystem.
///
/// **Aktueller Stand (Web/PWA):** Es gibt nur [UnsupportedReminderScheduler] –
/// eine No-op-Implementierung. Die App plant und zeigt Erinnerungen lediglich
/// als Vorschau; im Browser werden sie nicht ausgelöst.
///
/// **Geplante Android-Implementierung (später, NICHT Teil dieser Phase):**
/// Eine `AndroidReminderScheduler`-Klasse wird `flutter_local_notifications`
/// nutzen und die übergebenen [PlannedReminder] per `zonedSchedule` anmelden
/// (Tagesübersicht morgens, Tagesnotiz abends). Sie wird hinter einem
/// **Conditional Import** eingebunden, z. B.
///
/// ```dart
/// import 'reminder_scheduler_stub.dart'
///     if (dart.library.io) 'reminder_scheduler_android.dart';
/// ```
///
/// Aufrufer (Einstellungs-Screen, App-Start) sprechen ausschließlich diese
/// Schnittstelle an und müssen dafür nicht wissen, welche Plattform läuft.
/// Solange [isSupported] `false` ist, darf [apply] gefahrlos aufgerufen
/// werden und ändert nichts.
abstract class ReminderScheduler {
  /// Ob diese Plattform Erinnerungen tatsächlich auslösen kann.
  ///
  /// In dieser Phase (Web-Build, `flutter test`) immer `false`.
  bool get isSupported;

  /// Hinterlegt [reminders] beim Betriebssystem.
  ///
  /// Bei nicht unterstützten Plattformen ein No-op, der ein Ergebnis mit
  /// `supported: false` und `scheduledCount: 0` liefert.
  Future<ReminderScheduleResult> apply(List<PlannedReminder> reminders);

  /// Entfernt alle zuvor hinterlegten Erinnerungen (No-op, wenn nicht
  /// unterstützt).
  Future<void> cancelAll();
}

/// No-op-Implementierung für Plattformen ohne Benachrichtigungs-Support
/// (in dieser Phase: Web/PWA und alle Tests).
///
/// Sie tut bewusst nichts außer ehrlich zu melden, dass sie nichts tut – so
/// bleibt die Planungslogik testbar, ohne ein Notification-Plugin einzuführen.
class UnsupportedReminderScheduler implements ReminderScheduler {
  const UnsupportedReminderScheduler();

  /// Text, den die UI als Rückmeldung anzeigen kann.
  static const String unsupportedMessage =
      'Erinnerungen werden auf dieser Plattform nicht unterstützt.';

  @override
  bool get isSupported => false;

  @override
  Future<ReminderScheduleResult> apply(List<PlannedReminder> reminders) async =>
      const ReminderScheduleResult(
        supported: false,
        scheduledCount: 0,
        message: unsupportedMessage,
      );

  @override
  Future<void> cancelAll() async {
    // Nichts zu tun: es wurden nie Erinnerungen hinterlegt.
  }
}
