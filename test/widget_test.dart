import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tri_log/main.dart';

void main() {
  testWidgets('zeigt AppBar-Titel und Platzhaltertext', (tester) async {
    await tester.pumpWidget(const TriLogApp());

    expect(find.widgetWithText(AppBar, 'Tri-Log'), findsOneWidget);
    expect(find.text('Gerüst steht. Features folgen.'), findsOneWidget);
  });
}
