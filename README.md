# Tri-Log

Minimalistische Flutter-App zum **Anzeigen und Abhaken von Triathlon-Trainingsplänen**, die eine andere KI als JSON liefert. Alles läuft lokal auf dem Gerät – kein Backend, kein Account, kein Netzwerkzugriff zur Laufzeit.

> **Status: Phase 2 – Datenmodell, lokale Persistenz, Import mit Vorschau, Export.**
> Enthalten: Datenmodell (Pläne/Sitzungen/Aktivitäten/Tagebuch), Speicherung als ein
> JSON-Dokument, JSON-Import mit Änderungs-Vorschau, JSON-/Markdown-Export und eine
> schlichte Heute-Liste. Logging-UI, Tagebuch-Oberfläche, Benachrichtigungen und
> Statistik folgen in späteren Phasen.

## Stack

- Flutter 3.44.2 (stable) / Dart
- Material 3, deutsche UI, ThemeMode.system
- Zielplattformen: Web (GitHub Pages) und Android (später APK mit lokalen Notifications)
- `provider` (State), `shared_preferences` (Persistenz), `file_picker` (Import),
  `web` (nur für den Download im Browser)
- Kein Codegen, kein drift/sqflite, kein intl

## Lokale Befehle

```bash
flutter pub get
flutter run -d chrome        # Web lokal starten
flutter test                 # Unit- und Widget-Tests
flutter build web --release  # Build nach build/web
dart analyze                 # Statische Analyse
```

## Datenformat

Die App speichert **ein einziges JSON-Dokument** unter dem `shared_preferences`-Key
`tri_log_state_v1` und exportiert dasselbe Format:

```json
{
  "schema_version": "1.0",
  "exported_at": "2026-11-16T20:05:00+01:00",
  "timezone": "Europe/Berlin",
  "plans": [],
  "activities": [],
  "journal": []
}
```

- **Pläne** haben den Schlüssel `(id, revision)`, enthalten `sessions` und werden
  beim Import nie überschrieben: existiert die Revision bereits mit anderem Inhalt,
  blockiert der Import und verlangt eine höhere Revision. Ältere Revisionen bleiben
  erhalten.
- **Sitzungen** haben einen reinen Kalendertag (`YYYY-MM-DD`), eine Sportart
  (`swim`, `bike`, `run`, `strength`, `other`), eine geplante Dauer in Sekunden und
  optional eine Intervall-`structure`. Unbekannte Struktur-Felder bleiben erhalten.
- **Aktivitäten** und **Tagebucheinträge** werden beim Import nur ergänzt (Merge per
  `id`), nie gelöscht.
- `null` heißt „nicht erfasst“ und ist **nicht** 0.

Vollständige Feldbeschreibungen: [`docs/schema.json`](docs/schema.json) (JSON Schema
draft 2020-12). Realistisches Beispiel: [`docs/example-plan.json`](docs/example-plan.json) –
eine reine Plan-Datei, die der Importer fehlerfrei annimmt.

Der JSON-Export enthält immer alle Pläne (inkl. aller Revisionen) als Kontext; ein
optionaler Zeitraumfilter (`from`/`to`, inklusiv) wirkt nur auf Aktivitäten und
Tagebucheinträge. Der Markdown-Export liefert eine kompakte Wochen-/Tagesübersicht
mit geplanten vs. tatsächlichen Einheiten und den Tagebuchwerten.

## Deployment

Die App wird bei jedem Push auf `main` automatisch über GitHub Actions (`.github/workflows/deploy.yml`) gebaut und auf den Branch `gh-pages` deployt.

- Live-URL: https://lemmy-music.github.io/hermes-tri-log/
- In den Repo-Settings unter **Settings → Pages** muss als Source **„Deploy from a branch" → Branch `gh-pages` / `/ (root)`** ausgewählt sein.
- Wichtig: `web/index.html` nutzt `<base href="/hermes-tri-log/">`, weil die App als Project Page unter einem Unterpfad läuft.

## Android

Der Ordner `android/` ist vorhanden, wird in dieser Phase aber weder gebaut noch in der CI behandelt. Signatur-Dateien (`key.properties`, `*.jks`, `*.keystore`) sind via `.gitignore` ausgeschlossen.
