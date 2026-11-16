/// Datei-Download per conditional import.
///
/// Web → `download_helper_web.dart` (package:web, Anchor-Download).
/// Alle anderen Plattformen → `download_helper_stub.dart`, das eine klare
/// `UnsupportedError` wirft. Die UI fängt das ab und zeigt eine Meldung,
/// statt die App abstürzen zu lassen.
library;

import 'download_helper_stub.dart'
    if (dart.library.js_interop) 'download_helper_web.dart'
    as impl;

/// Startet einen Text-Download. Nur auf Web funktionsfähig.
void downloadTextFile({
  required String filename,
  required String content,
  required String mimeType,
}) => impl.downloadTextFile(
  filename: filename,
  content: content,
  mimeType: mimeType,
);
