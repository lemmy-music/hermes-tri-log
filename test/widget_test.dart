import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_log/main.dart';
import 'package:tri_log/state/app_repository.dart';

import 'fixtures.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('App startet mit vier Navigationszielen und Leerzustand', (
    tester,
  ) async {
    await tester.pumpWidget(const TriLogApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    final destinations = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((destination) => destination.label)
        .toList();
    expect(destinations, <String>['Heute', 'Tagebuch', 'Verlauf', 'Daten']);

    expect(find.text('Heute keine Einheit geplant.'), findsOneWidget);
    expect(
      find.text('Pläne lassen sich im Tab „Daten“ als JSON importieren.'),
      findsOneWidget,
    );
  });

  testWidgets('Daten-Tab zeigt Import- und Export-Buttons', (tester) async {
    await tester.pumpWidget(const TriLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).at(3));
    await tester.pumpAndSettle();

    expect(find.text('Plan importieren'), findsOneWidget);
    expect(find.text('JSON exportieren'), findsOneWidget);
    expect(find.text('Markdown exportieren'), findsOneWidget);
    expect(find.text('Alle Daten löschen'), findsOneWidget);
  });

  testWidgets('Tagebuch-Tab zeigt den Leerzustand', (tester) async {
    await tester.pumpWidget(const TriLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();

    expect(find.text('Noch keine Einträge'), findsOneWidget);
    expect(
      find.textContaining('Gefühl, Schlaf oder Beschwerden'),
      findsOneWidget,
    );
  });

  testWidgets('NavigationBar hat vier Ziele und der Wechsel funktioniert', (
    tester,
  ) async {
    await tester.pumpWidget(const TriLogApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(4));

    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pumpAndSettle();

    expect(find.text('Noch kein Verlauf'), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 2);
    // Im Verlauf gibt es bewusst keinen FAB.
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Noch keine Einträge'), findsOneWidget);

    await tester.tap(find.byType(NavigationDestination).at(0));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets(
    'Heute listet Sitzungen nach Sport-Reihenfolge mit optional-Badge',
    (tester) async {
      final repository = AppRepository(
        clock: () => DateTime(2026, 11, 23, 9),
        saveDebounce: const Duration(milliseconds: 1),
      );
      await repository.load();
      repository.importPlans(
        repository.parseImport(
          documentJson(
            plans: <Map<String, dynamic>>[
              planJson(
                sessions: <Map<String, dynamic>>[
                  sessionJson(
                    optional: true,
                    instructions: 'Locker einschwimmen, Technik im Fokus.',
                  ),
                  sessionJson(
                    id: 's2',
                    sport: 'bike',
                    type: 'Radfahren',
                    plannedDurationSeconds: 5400,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await repository.flush();

      await tester.pumpWidget(TriLogApp(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Technik'), findsOneWidget);
      expect(find.text('Radfahren'), findsOneWidget);
      expect(find.text('optional'), findsOneWidget);
      expect(find.textContaining('45 min'), findsWidgets);
      expect(find.textContaining('90 min'), findsWidgets);
      expect(find.textContaining('Locker einschwimmen'), findsOneWidget);

      final swimY = tester.getTopLeft(find.text('Technik')).dy;
      final bikeY = tester.getTopLeft(find.text('Radfahren')).dy;
      expect(swimY, lessThan(bikeY));
    },
  );
}
