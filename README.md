# Tri-Log

Minimalistische Flutter-App zum **Anzeigen und Abhaken von Triathlon-Trainingsplänen**, die eine andere KI als JSON liefert. Alles läuft lokal auf dem Gerät – kein Backend, kein Account.

> **Status: Phase 1 – Gerüst.** Aktuell existiert nur ein Platzhalter-Startbildschirm. Features (JSON-Import/-Export, Tagebuch, lokale Benachrichtigungen) folgen in späteren Phasen.

## Stack

- Flutter 3.44.2 (stable) / Dart
- Material 3, deutsche UI
- Zielplattformen: Web (GitHub Pages) und Android (später APK mit lokalen Notifications)
- Keine externen Pakete, kein State-Management in Phase 1

## Lokale Befehle

```bash
flutter pub get
flutter run -d chrome        # Web lokal starten
flutter test                 # Widget-Tests
flutter build web --release  # Build nach build/web
dart analyze                 # Statische Analyse
```

## Deployment

Die App wird bei jedem Push auf `main` automatisch über GitHub Actions (`.github/workflows/deploy.yml`) gebaut und auf den Branch `gh-pages` deployt.

- Live-URL: https://lemmy-music.github.io/hermes-tri-log/
- In den Repo-Settings unter **Settings → Pages** muss als Source **„Deploy from a branch" → Branch `gh-pages` / `/ (root)`** ausgewählt sein.
- Wichtig: `web/index.html` nutzt `<base href="/hermes-tri-log/">`, weil die App als Project Page unter einem Unterpfad läuft.

## Android

Der Ordner `android/` ist vorhanden, wird in dieser Phase aber weder gebaut noch in der CI behandelt. Signatur-Dateien (`key.properties`, `*.jks`, `*.keystore`) sind via `.gitignore` ausgeschlossen.
