# Tri-Log

Minimalistische Flutter-App zum **Anzeigen und Abhaken von Triathlon-Trainingsplänen**, die eine andere KI als JSON liefert. Alles läuft lokal auf dem Gerät – kein Backend, kein Account, kein Netzwerkzugriff zur Laufzeit.

> **Status: Phase 3 – Einheiten abhaken und Ist-Daten erfassen.**
> Enthalten: Datenmodell (Pläne/Sitzungen/Aktivitäten/Tagebuch), Speicherung als ein
> JSON-Dokument, JSON-Import mit Änderungs-Vorschau, JSON-/Markdown-Export und der
> Heute-Screen zum Abhaken (ein Tap) inkl. optionaler Ist-Daten und ungeplanter
> Einheiten. Tagebuch-Oberfläche, Benachrichtigungen und Statistik folgen in
> späteren Phasen.

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
- **Tagebucheinträge** haben genau ein `overall_feeling` (0–100, `null` = nicht
  angegeben). Bewusst undifferenziert – keine Aufschlüsselung in Energie/Stimmung;
  das frühere `metrics`-Objekt wird nicht mehr gelesen (Import: Hinweis, kein Fehler)
  und nicht mehr geschrieben.
- Pro geplanter Sitzung gibt es höchstens **eine** Aktivität (`planned_session_id`);
  ein erneutes Abhaken/Bearbeiten aktualisiert sie, statt eine zweite anzulegen.
- `null` heißt „nicht erfasst“ und ist **nicht** 0.

Vollständige Feldbeschreibungen: [`docs/schema.json`](docs/schema.json) (JSON Schema
draft 2020-12). Realistisches Beispiel: [`docs/example-plan.json`](docs/example-plan.json) –
eine reine Plan-Datei, die der Importer fehlerfrei annimmt.

## Bedienung (Tab „Heute“)

- **Abhaken in einem Tap:** Häkchen rechts auf der Sitzungskarte → Aktivität mit
  Status „Erledigt“ und der geplanten Dauer. SnackBar „Abgehakt: … “ mit
  **Rückgängig**. Die Karte zeigt sofort das Badge; danach wird das Häkchen zum
  Stift (Bearbeiten) – ein Duplikat entsteht nie.
- **Karte antippen:** Bottom Sheet „Einheit erfassen“ mit Status
  (Erledigt/Teilweise/Ausgelassen), Gesamtzeit in Minuten (Kommazahlen erlaubt),
  optionalem RPE-Slider (1–10), Notiz und „Mehr Angaben“ (Bewegungszeit, Distanz,
  Puls, Leistung). Speichern schließt das Sheet nicht, sondern bestätigt im Sheet;
  schließen per X, Wischen oder „Fertig“. „Löschen“ entfernt die Ist-Daten wieder.
- **Ungeplante Einheit:** FAB „+“ auf dem Heute-Screen → gleiches Sheet mit
  Sport-Auswahl; der Eintrag erscheint im Abschnitt „Zusätzlich“.
- Der Kopf fasst zusammen: „X von Y erledigt“ (plus „· Z teilweise“).

Der JSON-Export enthält immer alle Pläne (inkl. aller Revisionen) als Kontext; ein
optionaler Zeitraumfilter (`from`/`to`, inklusiv) wirkt nur auf Aktivitäten und
Tagebucheinträge. Der Markdown-Export liefert eine kompakte Wochen-/Tagesübersicht
mit geplanten vs. tatsächlichen Einheiten und den Tagebuchwerten.

## Deployment

Die App wird bei jedem Push auf `main` automatisch über GitHub Actions (`.github/workflows/deploy.yml`) gebaut und auf den Branch `gh-pages` deployt.

- Live-URL: https://lemmy-music.github.io/hermes-tri-log/
- In den Repo-Settings unter **Settings → Pages** muss als Source **„Deploy from a branch" → Branch `gh-pages` / `/ (root)`** ausgewählt sein.
- Wichtig: `web/index.html` nutzt `<base href="/hermes-tri-log/">`, weil die App als Project Page unter einem Unterpfad läuft.

## Installation als PWA

Die App ist eine installierbare PWA (`web/manifest.json` mit Icons in `web/icons/`,
Theme-Farbe `#0F172A`, `display: standalone`) und läuft komplett lokal ohne Konto.

- **Android installieren:** Live-URL in Chrome öffnen → Menü (⋮) →
  „Zum Startbildschirm hinzufügen“ bzw. „App installieren“.
- **Updates:** Nach einem neuen Deploy die App einmal **komplett schließen und neu
  öffnen** – erst dann ist die neue Version aktiv. (Bewusst keine eigene
  Update-Banner-Logik.)
- **Offline (Stand heute eingeschränkt):** `flutter build web --release` erzeugt
  weiterhin `flutter_service_worker.js`, Flutter 3.44 hat den eingebauten
  Service-Worker-Cache aber abgekündigt (flutter/flutter#156910): die erzeugte Datei
  meldet sich beim Aktivieren selbst wieder ab, es gibt also keinen
  Framework-seitigen Offline-Cache mehr. Die Registrierung ist in
  `flutter_bootstrap.js` aktiv, die App hängt damit nur am HTTP-Cache des Browsers.
  Ein verlässlicher Offline-Start braucht einen eigenen Service Worker
  (Folgeaufgabe, nicht Teil dieser Phase).

## Android

Der Ordner `android/` ist vorhanden, wird in dieser Phase aber weder gebaut noch in der CI behandelt. Signatur-Dateien (`key.properties`, `*.jks`, `*.keystore`) sind via `.gitignore` ausgeschlossen.
