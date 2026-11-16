{{flutter_js}}
{{flutter_build_config}}

// Eigener Bootstrap: Flutters Stub-Service-Worker (flutter_service_worker.js)
// wird bewusst NICHT registriert – er meldet sich beim Aktivieren selbst ab
// (flutter/flutter#156910) und würde unsere eigene Registrierung ersetzen.
// Ohne `serviceWorkerSettings` fasst der Loader die Service-Worker-API nicht an;
// web/index.html registriert stattdessen sw.js.
_flutter.loader.load();
