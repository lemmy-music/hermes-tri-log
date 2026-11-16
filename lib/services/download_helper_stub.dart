/// Stub für Nicht-Web-Plattformen (Android/Desktop).
///
/// Es gibt in dieser Phase keinen echten Datei-Speichern-Pfad; die UI zeigt
/// deshalb eine verständliche Meldung statt eines Absturzes.
void downloadTextFile({
  required String filename,
  required String content,
  required String mimeType,
}) {
  throw UnsupportedError(
    'Datei-Download ist nur in der Web-Version verfügbar.',
  );
}
