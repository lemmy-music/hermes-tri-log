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
  `web` (nur für den Download im Browser), `scrollable_positioned_list`
  (Positionierung des Verlaufs auf den heutigen Tag, siehe unten)
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
- **Kommende Tage:** unter dem heutigen Block, durch Abstand und Trennlinie
  abgesetzt, stehen die geplanten Sitzungen der **nächsten 7 Kalendertage**
  (heute+1 bis heute+7), gruppiert nach Tag. Tage ohne Sitzung fehlen, und ohne
  geplante Zukunft entfällt der Abschnitt komplett. Die Zeilen sind bewusst
  kompakt und gedämpft (Umriss-Karte, gedämpfte Schrift) – die Zukunft soll
  nicht mit heute konkurrieren. Ein Tap öffnet das **rein lesende** Sheet
  „Planung ansehen“ (Datum, Typ, Sport · Plantitel, `Plan: X min`,
  Struktur-Kurzfassung, vollständige Beschreibung) – **kein** Erfassen,
  Abhaken oder Speichern für zukünftige Tage.

## Bedienung (Tab „Verlauf“)

Der Verlauf ist eine **Zeitscheibe um heute**, aufsteigend sortiert
(Vergangenheit oben, Zukunft unten):

- **7 Tage** = heute −7 bis heute +7 (15 Kalendertage), **30 Tage** = ±30
  (Standard), **Alles** = vom frühesten bis zum spätesten Datum mit Inhalt,
  mindestens aber ±7 – die Liste ist damit nie leer.
- Der heutige Tag ist der **Anker**: beim Öffnen des Tabs und bei jedem
  Zeitraumwechsel wird die Liste so positioniert, dass der heutige Tageskopf
  vertikal mittig im Viewport steht. Technisch über
  `ScrollablePositionedList` mit `initialScrollIndex` (Index des heutigen
  Tageskopfs aus `indexOfTodayRow`) und `initialAlignment`; oben und unten
  liegt je eine halbe Viewport-Höhe Padding, damit die Position auch bei
  kurzem Inhalt erreichbar ist. Heute ist immer in der Liste – ohne Inhalt mit
  dem Hinweis „keine Einheit geplant“.
- **Heute** ist mit Chip „Heute“ und primary-farbener Umrandung/tönung
  hervorgehoben. **Zukunft** (Datum > heute) ist gedämpft (Text in
  `onSurfaceVariant` mit ~55 % Deckkraft), der Tageskopf trägt „· geplant“ und
  die Zeile neutral „geplant“ – nie „keine Aufzeichnung“, denn das wäre bei
  Zukunft falsch.
- Tap auf eine Sitzungszeile: Vergangenheit/heute → Erfassungs-Sheet,
  Zukunft → rein lesendes Sheet „Planung ansehen“.
- Die Summary-Card zählt Status (erledigt/teilweise/ausgelassen/offen) **nur
  für Tage ≤ heute** und ergänzt „· N geplant (Zukunft)“. Die Plan-Minuten
  stammen ebenfalls nur aus Sitzungen ≤ heute; „Ist: A min / Plan: B min“,
  sonst „–“.

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
- **Offline:** Die App funktioniert nach dem ersten Aufruf offline. Dafür sorgt
  der eigene Service Worker [`web/sw.js`](web/sw.js): Er wird von
  `web/index.html` registriert und legt Startseite, `main.dart.js` und die
  Icons in einem Cache ab. HTML, `flutter_bootstrap.js`, `main.dart.js` und
  `manifest.json` werden network-first geladen (online immer frisch, offline
  aus dem Cache), alle übrigen Dateien cache-first.
  `web/flutter_bootstrap.js` registriert Flutters Stub-Worker bewusst **nicht**
  mehr: Flutter 3.44 hat den eingebauten Service-Worker-Cache abgekündigt
  (flutter/flutter#156910), die erzeugte `flutter_service_worker.js` meldet
  sich beim Aktivieren selbst ab und würde die eigene Registrierung ersetzen.
  Beim Deploy einer neuen Version lädt die App beim nächsten kompletten
  Neustart die neue Fassung; der Cache wird dabei über die Version in
  `CACHE_NAME` erneuert.

## Android

Der Ordner `android/` ist vorhanden, wird in dieser Phase aber weder gebaut noch in der CI behandelt. Signatur-Dateien (`key.properties`, `*.jks`, `*.keystore`) sind via `.gitignore` ausgeschlossen.
