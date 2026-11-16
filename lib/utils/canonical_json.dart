import 'dart:convert';

/// Serialisiert [value] mit rekursiv sortierten Objekt-Schlüsseln.
///
/// Damit lassen sich zwei JSON-Strukturen inhaltlich vergleichen, ohne dass
/// die Schlüsselreihenfolge (die beim Einlesen variieren kann) eine Rolle
/// spielt. Wird für die Merge-Erkennung "Inhalt identisch" genutzt.
String canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalize).toList();
  }
  return value;
}
