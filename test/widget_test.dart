import 'package:crabify/src/theme/crabify_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Crabify theme renders a smoke widget', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CrabifyTheme.dark(),
        home: const Scaffold(body: Center(child: Text('Crabify'))),
      ),
    );

    expect(find.text('Crabify'), findsOneWidget);
  });
}
