import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:convert';

import 'package:web/web.dart' as web;

/// Regt im Browser einen Datei-Download über ein verstecktes Anchor-Element an.
void downloadTextFile({
  required String filename,
  required String content,
  required String mimeType,
}) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
