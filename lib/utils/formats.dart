/// Kleine, lokalisierungsfreie Formatierungs-Helfer (deutsche Schreibweise).
///
/// Bewusst ohne `intl`: Die App hat kein `flutter_localizations`-Setup, deshalb
/// werden Datum, Uhrzeit, Dauer und Distanz hier von Hand formatiert.
library;

const List<String> _weekdaysShort = <String>[
  'Mo',
  'Di',
  'Mi',
  'Do',
  'Fr',
  'Sa',
  'So',
];

/// Zweistellig mit führender Null.
String twoDigits(int value) => value.toString().padLeft(2, '0');

/// `2026-11-26`
String formatDateIso(DateTime date) =>
    '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';

/// `26.11.2026`
String formatDateNumeric(DateTime date) =>
    '${twoDigits(date.day)}.${twoDigits(date.month)}.${date.year}';

/// `Do, 26.11.2026`
String formatDateGerman(DateTime date) =>
    '${_weekdaysShort[date.weekday - 1]}, ${formatDateNumeric(date)}';

/// `20:05`
String formatTime(DateTime date) =>
    '${twoDigits(date.hour)}:${twoDigits(date.minute)}';

/// `26.11.2026, 20:05`
String formatDateTimeGerman(DateTime date) =>
    '${formatDateNumeric(date)}, ${formatTime(date)}';

/// Parst ausschließlich `YYYY-MM-DD` (kein Zeitzonen-/Zeitanteil).
DateTime? parseIsoDate(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  // Fängt z. B. 2026-02-31 ab (DateTime rollt sonst weiter).
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Zahl mit deutschem Dezimalkomma.
String decimalGerman(double value, int fractionDigits) =>
    value.toStringAsFixed(fractionDigits).replaceAll('.', ',');

/// Minutenanzeige: ganzzahlig wenn möglich, sonst eine Dezimale (`1,5`).
String formatMinutes(int? seconds, {String empty = '–'}) {
  if (seconds == null) return empty;
  if (seconds % 60 == 0) return (seconds ~/ 60).toString();
  return decimalGerman(seconds / 60, 1);
}

/// `45 min`, `1,5 min`
String formatMinutesWithUnit(int? seconds, {String empty = '–'}) {
  final value = formatMinutes(seconds, empty: empty);
  return value == empty ? empty : '$value min';
}

/// `1,8 km` (Meter → Kilometer, eine Dezimale; ganze Kilometer ohne Dezimale).
String formatDistanceKm(double? meters, {String empty = '–'}) {
  if (meters == null) return empty;
  final km = meters / 1000;
  if ((km - km.roundToDouble()).abs() < 0.05) return '${km.round()} km';
  return '${decimalGerman(km, 1)} km';
}

/// `70 %`
String formatPercent(int? value, {String empty = '–'}) =>
    value == null ? empty : '$value %';

/// Parst eine Dezimalzahl mit deutschem Komma ODER Punkt (`35,5` / `35.5`).
/// Leere oder unparsbare Eingaben liefern `null` (nichts wird geraten).
double? parseDecimalGerman(String? input) {
  if (input == null) return null;
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed.replaceAll(',', '.'));
}

/// Minuteneingabe → Sekunden. Leer/ungültig/negativ → `null`.
int? parseMinutesToSeconds(String? input) {
  final minutes = parseDecimalGerman(input);
  if (minutes == null || minutes < 0) return null;
  return (minutes * 60).round();
}

/// Sekunden → Text für ein Minuten-Eingabefeld (ohne Einheit), `''` bei null.
String minutesInputText(int? seconds) =>
    seconds == null ? '' : formatMinutes(seconds);

/// Kilometereingabe → Meter. Leer/ungültig/negativ → `null`.
double? parseKilometersToMeters(String? input) {
  final km = parseDecimalGerman(input);
  if (km == null || km < 0) return null;
  return km * 1000;
}

/// Meter → Text für ein Kilometer-Eingabefeld (ohne Einheit), `''` bei null.
String kilometersInputText(double? meters) {
  if (meters == null) return '';
  final fixed = (meters / 1000).toStringAsFixed(2);
  final trimmed = fixed
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
  return trimmed.replaceAll('.', ',');
}

/// Vergleich Ist- gegen Plan-Dauer als kurzer deutscher Text:
/// `wie geplant`, `15 min kürzer`, `5 min länger`.
///
/// Liefert `null`, wenn eine der beiden Angaben fehlt – es wird nichts
/// erfunden.
String? durationDeltaLabel(int? planSeconds, int? actualSeconds) {
  if (planSeconds == null || actualSeconds == null) return null;
  final diffSeconds = actualSeconds - planSeconds;
  if (diffSeconds == 0) return 'wie geplant';
  final amount = formatMinutes(diffSeconds.abs());
  return diffSeconds < 0 ? '$amount min kürzer' : '$amount min länger';
}

/// ISO-8601-Zeitstempel mit explizitem lokalem Offset (`2026-11-16T20:05:00+01:00`).
String isoWithOffset(DateTime dateTime) {
  final local = dateTime.isUtc ? dateTime.toLocal() : dateTime;
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  final offsetText =
      '$sign${twoDigits(absolute.inHours)}:${twoDigits(absolute.inMinutes % 60)}';
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}'
      'T${twoDigits(local.hour)}:${twoDigits(local.minute)}:'
      '${twoDigits(local.second)}$offsetText';
}

/// Montag der Woche, in der [date] liegt (00:00 Uhr).
DateTime startOfWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// ISO-8601-Kalenderwoche (Woche 1 enthält den ersten Donnerstag des Jahres).
int isoWeekNumber(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final thursday = day.add(Duration(days: 4 - day.weekday));
  final january4 = DateTime(thursday.year, 1, 4);
  final firstThursday = january4.add(Duration(days: 4 - january4.weekday));
  return 1 + thursday.difference(firstThursday).inDays ~/ 7;
}
