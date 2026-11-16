import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/export_service.dart';
import '../services/history_service.dart';
import '../services/import_service.dart';
import '../services/merge_service.dart';
import '../services/storage.dart';
import '../utils/formats.dart';
import '../utils/ids.dart';

/// Eine Sitzung des Tages inkl. zugehörigem Plan (für die Heute-Liste).
class TodaySession {
  const TodaySession({required this.plan, required this.session});

  final Plan plan;
  final Session session;
}

/// Zentraler App-Zustand: lädt/speichert das JSON-Dokument und stellt die
/// Import-/Export-Operationen bereit.
class AppRepository extends ChangeNotifier with WidgetsBindingObserver {
  AppRepository({
    StorageService? storage,
    DateTime Function()? clock,
    Duration? saveDebounce,
    ExportService? exporter,
    ImportService? importer,
    IdGenerator? ids,
  }) : _storage = storage ?? const StorageService(),
       _clock = clock ?? DateTime.now,
       _saveDebounce = saveDebounce ?? const Duration(milliseconds: 300),
       _exporter = exporter ?? const ExportService(),
       _importer = importer ?? const ImportService(),
       _ids = ids ?? IdGenerator() {
    WidgetsBinding.instance.addObserver(this);
  }

  final StorageService _storage;
  final DateTime Function() _clock;
  final Duration _saveDebounce;
  final ExportService _exporter;
  final ImportService _importer;
  final IdGenerator _ids;

  AppState _state = AppState.empty();
  bool _loaded = false;
  String? _storageWarning;
  Timer? _saveTimer;
  String? _pendingDocument;
  bool _disposed = false;

  AppState get state => _state;
  bool get isLoaded => _loaded;

  /// Meldung für Banner/SnackBar, wenn der Speicherinhalt nicht lesbar war.
  String? get storageWarning => _storageWarning;

  DateTime get now => _clock();

  // ─── Laden / Speichern ─────────────────────────────────────────────────────

  Future<void> load() async {
    String? raw;
    try {
      raw = await _storage.read();
    } catch (_) {
      _storageWarning =
          'Der lokale Speicher konnte nicht gelesen werden. '
          'Es wurde ein leerer Zustand geladen.';
    }

    if (raw == null || raw.trim().isEmpty) {
      _state = AppState.empty();
    } else {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Kein JSON-Objekt.');
        }
        _state = AppState.fromJson(decoded);
      } catch (_) {
        _state = AppState.empty();
        _storageWarning =
            'Gespeicherte Daten konnten nicht gelesen werden. '
            'Es wurde ein leerer Zustand geladen.';
      }
    }

    _loaded = true;
    _notify();
  }

  void dismissStorageWarning() {
    if (_storageWarning == null) return;
    _storageWarning = null;
    _notify();
  }

  void _scheduleSave() {
    _pendingDocument = jsonEncode(_state.toJson());
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      _saveTimer = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    final document = _pendingDocument;
    if (document == null) return;
    _pendingDocument = null;
    try {
      await _storage.write(document);
    } catch (_) {
      _storageWarning =
          'Speichern fehlgeschlagen – Änderungen sind eventuell '
          'nicht dauerhaft gesichert.';
      _notify();
    }
  }

  /// Schreibt ausstehende Änderungen sofort (z. B. beim Pausieren der App).
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _flush();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(flush());
    }
  }

  // ─── Heute ─────────────────────────────────────────────────────────────────

  /// Sitzungen eines Kalendertags aus allen Plänen (nur neueste Revision),
  /// sortiert swim → bike → run → strength → other.
  List<TodaySession> sessionsForDate(DateTime date) {
    final result = <TodaySession>[];
    for (final plan in _state.latestPlans) {
      for (final session in plan.sessions) {
        if (session.date == formatDateIso(date)) {
          result.add(TodaySession(plan: plan, session: session));
        }
      }
    }
    result.sort((a, b) {
      final bySport = a.session.sport.sortIndex.compareTo(
        b.session.sport.sortIndex,
      );
      if (bySport != 0) return bySport;
      return a.session.type.compareTo(b.session.type);
    });
    return result;
  }

  List<TodaySession> get todaySessions => sessionsForDate(_clock());

  // ─── Aktivitäten (Erfassen / Abhaken) ──────────────────────────────────────

  /// Neue, garantiert noch nicht verwendete Aktivitäts-ID.
  String nextActivityId() => _ids.nextActivity();

  /// Die eine primäre Aktivität einer geplanten Sitzung (1:1-Regel) oder null.
  Activity? activityForSession(String? plannedSessionId) {
    if (plannedSessionId == null || plannedSessionId.isEmpty) return null;
    for (final activity in _state.activities) {
      if (activity.plannedSessionId == plannedSessionId) return activity;
    }
    return null;
  }

  /// Ungeplante Einheiten eines Kalendertags, sortiert nach Startzeit.
  List<Activity> unplannedActivitiesForDate(DateTime date) {
    final wanted = formatDateIso(date);
    final result = <Activity>[
      for (final activity in _state.activities)
        if (activity.plannedSessionId == null)
          if (_activityDateIso(activity) == wanted) activity,
    ];
    result.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return result;
  }

  List<Activity> get todayUnplannedActivities =>
      unplannedActivitiesForDate(_clock());

  /// Legt eine Aktivität an bzw. überschreibt sie (Upsert per [Activity.id]).
  void saveActivity(Activity activity) {
    final activities = <Activity>[..._state.activities];
    final index = activities.indexWhere((item) => item.id == activity.id);
    if (index >= 0) {
      activities[index] = activity;
    } else {
      activities.add(activity);
    }
    _state = _state.copyWith(activities: activities);
    _scheduleSave();
    _notify();
  }

  /// Legt die Aktivität einer geplanten Sitzung an **oder** aktualisiert sie.
  ///
  /// Es gibt bewusst höchstens eine primäre Aktivität pro
  /// `planned_session_id`; ein zweiter Aufruf erzeugt kein Duplikat, sondern
  /// überschreibt die bestehende Aktivität (ID und Startzeit bleiben erhalten).
  Activity saveActivityForSession({
    required Plan plan,
    required Session session,
    required ActivityStatus status,
    int? elapsedDurationSeconds,
    int? movingDurationSeconds,
    double? distanceMeters,
    int? averageHeartRateBpm,
    int? averagePowerWatts,
    int? rpe,
    String? notes,
    String? startedAt,
  }) {
    final existing = activityForSession(session.id);
    final activity = Activity(
      id: existing?.id ?? nextActivityId(),
      planId: plan.id,
      planRevision: plan.revision,
      plannedSessionId: session.id,
      sport: session.sport.wireName,
      startedAt: existing?.startedAt ?? startedAt ?? isoWithOffset(_clock()),
      status: status,
      elapsedDurationSeconds: elapsedDurationSeconds,
      movingDurationSeconds: movingDurationSeconds,
      distanceMeters: distanceMeters,
      averageHeartRateBpm: averageHeartRateBpm,
      averagePowerWatts: averagePowerWatts,
      rpe: rpe,
      notes: notes,
    );
    saveActivity(activity);
    return activity;
  }

  /// Löscht eine Aktivität (z. B. „Rückgängig“ nach dem Abhaken).
  void deleteActivity(String id) {
    final activities = _state.activities
        .where((activity) => activity.id != id)
        .toList();
    if (activities.length == _state.activities.length) return;
    _state = _state.copyWith(activities: activities);
    _scheduleSave();
    _notify();
  }

  // ─── Tagebuch ──────────────────────────────────────────────────────────────

  /// Neue, garantiert noch nicht verwendete Tagebuch-ID.
  String nextJournalEntryId() => _ids.nextJournalEntry();

  /// Alle Einträge, neueste zuerst.
  List<JournalEntry> get journalEntriesNewestFirst =>
      sortJournalNewestFirst(_state.journal);

  JournalEntry? journalEntryById(String id) {
    for (final entry in _state.journal) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Einträge eines Kalendertags, aufsteigend nach Uhrzeit.
  List<JournalEntry> journalEntriesForDate(DateTime date) {
    final wanted = formatDateIso(date);
    final result = <JournalEntry>[
      for (final entry in _state.journal)
        if (_journalDateIso(entry) == wanted) entry,
    ];
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  /// Gesamtbefinden des letzten Eintrags eines Tages (oder `null`).
  int? latestJournalFeelingForDate(DateTime date) {
    final entries = journalEntriesForDate(date);
    return entries.isEmpty ? null : entries.last.overallFeeling;
  }

  /// Legt einen Tagebucheintrag an bzw. überschreibt ihn (Upsert per id).
  void saveJournalEntry(JournalEntry entry) {
    final journal = <JournalEntry>[..._state.journal];
    final index = journal.indexWhere((item) => item.id == entry.id);
    if (index >= 0) {
      journal[index] = entry;
    } else {
      journal.add(entry);
    }
    _state = _state.copyWith(journal: journal);
    _scheduleSave();
    _notify();
  }

  /// Löscht einen Tagebucheintrag.
  void deleteJournalEntry(String id) {
    final journal = _state.journal.where((entry) => entry.id != id).toList();
    if (journal.length == _state.journal.length) return;
    _state = _state.copyWith(journal: journal);
    _scheduleSave();
    _notify();
  }

  /// Kalendertag eines Tagebucheintrags in lokaler Zeit (`YYYY-MM-DD`).
  String? _journalDateIso(JournalEntry entry) {
    final local = DateTime.tryParse(entry.timestamp)?.toLocal();
    return local == null ? null : formatDateIso(local);
  }

  // ─── Import ────────────────────────────────────────────────────────────────

  ImportResult parseImport(String jsonText) => _importer.parse(jsonText);

  /// Vorschau ohne Zustandsänderung.
  MergeResult previewImport(ImportResult imported) =>
      computeMerge(current: _state, imported: imported);

  /// Übernimmt den Import, wenn kein Konflikt vorliegt.
  MergeResult importPlans(ImportResult imported) {
    final merge = previewImport(imported);
    final proposed = merge.proposedState;
    if (merge.hasConflict || proposed == null) return merge;
    _state = proposed;
    _scheduleSave();
    _notify();
    return merge;
  }

  // ─── Export ────────────────────────────────────────────────────────────────

  String exportJson({DateTime? from, DateTime? to}) =>
      _exporter.buildJson(_state, from: from, to: to, now: _clock());

  String exportMarkdown({DateTime? from, DateTime? to}) =>
      _exporter.buildMarkdown(_state, from: from, to: to, now: _clock());

  String exportFileNameJson() => _exporter.fileNameJson(_clock());

  String exportFileNameMarkdown() => _exporter.fileNameMarkdown(_clock());

  // ─── Alles löschen ─────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _pendingDocument = null;
    _state = AppState.empty();
    _storageWarning = null;
    _notify();
    try {
      await _storage.clear();
    } catch (_) {
      _storageWarning = 'Löschen des Speichers fehlgeschlagen.';
      _notify();
    }
  }

  /// Kalendertag einer Aktivität in lokaler Zeit (`YYYY-MM-DD`) oder null.
  String? _activityDateIso(Activity activity) {
    final local = DateTime.tryParse(activity.startedAt)?.toLocal();
    return local == null ? null : formatDateIso(local);
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _saveTimer = null;
    final document = _pendingDocument;
    _pendingDocument = null;
    if (document != null) {
      unawaited(_storage.write(document).catchError((Object _) {}));
    }
    super.dispose();
  }
}
