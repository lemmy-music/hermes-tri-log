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

  testWidgets('App startet mit drei Navigationszielen und Leerzustand', (
    tester,
  ) async {
    await tester.pumpWidget(const TriLogApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    final destinations = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((destination) => destination.label)
        .toList();
    expect(destinations, <String>['Heute', 'Tagebuch', 'Daten']);

    expect(find.text('Heute keine Einheit geplant.'), findsOneWidget);
    expect(
      find.text('Pläne lassen sich im Tab „Daten“ als JSON importieren.'),
      findsOneWidget,
    );
  });

  testWidgets('Daten-Tab zeigt Import- und Export-Buttons', (tester) async {
    await tester.pumpWidget(const TriLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pumpAndSettle();

    expect(find.text('Plan importieren'), findsOneWidget);
    expect(find.text('JSON exportieren'), findsOneWidget);
    expect(find.text('Markdown exportieren'), findsOneWidget);
    expect(find.text('Alle Daten löschen'), findsOneWidget);
  });

  testWidgets('Tagebuch-Tab zeigt den Platzhalter', (tester) async {
    await tester.pumpWidget(const TriLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();

    expect(find.text('Tagebuch folgt.'), findsOneWidget);
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
