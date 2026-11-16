import 'dart:math';

/// Kleiner ID-Generator ohne externe Abhängigkeit (kein uuid-Paket).
///
/// Format: `<prefix>-<millis>-<4 Zeichen>`, z. B. `act-1763323200000-k3f9`.
/// [clock] und [random] sind injizierbar, damit Tests deterministisch sind.
class IdGenerator {
  IdGenerator({DateTime Function()? clock, Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? Random();

  final DateTime Function() _clock;
  final Random _random;

  static const String _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  /// Erzeugt eine ID mit beliebigem Präfix.
  String next(String prefix) {
    final millis = _clock().millisecondsSinceEpoch;
    final suffix = String.fromCharCodes(
      List<int>.generate(
        4,
        (_) => _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
      ),
    );
    return '$prefix-$millis-$suffix';
  }

  String nextActivity() => next('act');
  String nextJournalEntry() => next('jnl');
  String nextPlan() => next('plan');
  String nextSession() => next('ses');
}
