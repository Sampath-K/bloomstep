import 'package:bloomstep/app/bloomstep_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app opens to an empty garden with a call to plant a habit',
      (tester) async {
    await tester.pumpWidget(const BloomstepApp());

    expect(find.text('Bloomstep'), findsOneWidget);
    expect(find.text('Your garden is ready to grow'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Plant a habit'),
        findsOneWidget);
    expect(find.byIcon(Icons.spa_outlined), findsOneWidget);
  });
}
