import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_log/models/models.dart';
import 'package:tri_log/services/storage.dart';
import 'package:tri_log/state/app_repository.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppRepository buildRepository() => AppRepository(
    clock: () => DateTime(2026, 11, 23, 9),
    saveDebounce: const Duration(milliseconds: 1),
  );

  test('leerer Speicher ergibt leeren Zustand ohne Warnung', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = buildRepository();
    await repository.load();

    expect(repository.isLoaded, isTrue);
    expect(repository.state.plans, isEmpty);
    expect(repository.storageWarning, isNull);
    expect(repository.todaySessions, isEmpty);

    repository.dispose();
  });

  test('kaputter Speicherinhalt crasht nicht, sondern warnt', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      StorageService.storageKey: '{"plans": [kaputt',
    });
    final repository = buildRepository();
    await repository.load();

    expect(repository.isLoaded, isTrue);
    expect(repository.state.plans, isEmpty);
    expect(repository.storageWarning, isNotNull);
    expect(repository.todaySessions, isEmpty);

    repository.dispose();
  });

  test('Import wird gespeichert und nach Neustart geladen', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = buildRepository();
    await repository.load();

    final imported = repository.parseImport(documentJson());
    final merge = repository.importPlans(imported);
    expect(merge.hasConflict, isFalse);
    expect(repository.todaySessions, hasLength(1));
    expect(repository.todaySessions.single.session.type, 'Technik');
    await repository.flush();
    repository.dispose();

    final reloaded = buildRepository();
    await reloaded.load();
    expect(reloaded.state.plans, hasLength(1));
    expect(reloaded.todaySessions.single.session.sport, Sport.swim);
    reloaded.dispose();
  });

  test('clearAll entfernt Zustand und Speicherinhalt', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = buildRepository();
    await repository.load();
    repository.importPlans(repository.parseImport(documentJson()));
    await repository.flush();

    await repository.clearAll();
    expect(repository.state.plans, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StorageService.storageKey), isNull);
    repository.dispose();
  });

  test('Export-Methoden liefern JSON und Markdown aus dem Zustand', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = buildRepository();
    await repository.load();
    repository.importPlans(repository.parseImport(documentJson()));

    final json = repository.exportJson();
    expect(json, contains('"schema_version": "1.0"'));
    expect(json, contains('"timezone": "Europe/Berlin"'));
    expect(repository.exportFileNameJson(), 'tri-log-export-2026-11-23.json');

    final markdown = repository.exportMarkdown();
    expect(markdown, contains('Schwimmen · Technik · 45 min'));

    await repository.flush();
    repository.dispose();
  });

  test('Konflikt wird gemeldet und nichts übernommen', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = buildRepository();
    await repository.load();
    repository.importPlans(repository.parseImport(documentJson()));
    await repository.flush();

    final conflicting = documentJson(
      plans: <Map<String, dynamic>>[
        <String, dynamic>{...planJson(), 'title': 'Anderer Titel'},
      ],
    );
    final merge = repository.importPlans(repository.parseImport(conflicting));
    expect(merge.hasConflict, isTrue);
    expect(repository.state.plans.single.title, 'Wintergrundlage');

    await repository.flush();
    repository.dispose();
  });
}
