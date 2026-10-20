import 'package:budlark/core/models.dart';
import 'package:budlark/features/garden/garden_moment.dart';
import 'package:budlark/features/garden/garden_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'garden_learning_test.dart' show fixture, settleDatabase;

List<String> visibleWords(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text).hitTestable())
    .expand((text) => (text.data ?? text.textSpan?.toPlainText() ?? '')
        .split(RegExp(r'\s+')))
    .where((word) => word.isNotEmpty)
    .toList();

void expectCalm(WidgetTester tester, {required String heading}) {
  expect(find.text(heading).hitTestable(), findsOneWidget);
  expect(
    tester.widgetList<Semantics>(find.byType(Semantics)).where(
      (semantics) => semantics.properties.header == true,
    ),
    hasLength(1),
  );
  expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
  expect(find.byType(FloatingActionButton), findsNothing);
  expect(visibleWords(tester).length, lessThanOrEqualTo(28));
  final bodyWords = tester
      .widgetList<Text>(find.byType(Text).hitTestable())
      .where((text) => ![
        heading,
        'I did it',
        'Plant a habit',
        'More',
      ].contains(text.data))
      .expand((text) => (text.data ?? '').split(RegExp(r'\s+')))
      .where((word) => RegExp('[A-Za-z0-9]').hasMatch(word));
  expect(bodyWords.length, lessThanOrEqualTo(16));
  expect(find.text('More').hitTestable(), findsOneWidget);
  expect(find.text('Did more'), findsNothing);
  expect(find.byTooltip('Settings and privacy'), findsNothing);
}

void main() {
  testWidgets('completion shows only the stage that storage actually grew',
      (tester) async {
    final (store, habit) = await fixture(tester);
    final now = DateTime.now();
    await tester.runAsync(() async {
      for (var day = 1; day <= 2; day++) {
        await store.checkIn(habit.id, CheckInResult.did,
            now: now.subtract(Duration(days: day)));
      }
    });
    await tester.pumpWidget(MaterialApp(
      home: GardenScreen(store: store, testDisableServices: true),
    ));
    await settleDatabase(tester);
    expect(tester.widget<GardenMoment>(find.byType(GardenMoment)).stage,
        GrowthStage.seed);
    await tester.tap(find.text('I did it'));
    await settleDatabase(tester);
    final moment = tester.widget<GardenMoment>(find.byType(GardenMoment));
    expect(moment.previousStage, GrowthStage.seed);
    expect(moment.stage, GrowthStage.sprout);
    expect((await tester.runAsync(store.habits))!.single.stage, moment.stage);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to your habit'));
    await tester.pumpAndSettle();
    expect(tester.widget<GardenMoment>(find.byType(GardenMoment)).animate,
        isFalse);
  });

  testWidgets('initial, completion, return and next-day have one calm focus',
      (tester) async {
    final (store, habit) = await fixture(tester);
    var now = DateTime.now();
    await tester.runAsync(() async {
      await store.setSetting('reminders', 'false');
      await store.setSetting('reminderMinute', '1110');
    });
    await tester.pumpWidget(MaterialApp(
      home: GardenScreen(
        store: store,
        clock: () => now,
        testDisableServices: true,
      ),
    ));
    await settleDatabase(tester);
    expectCalm(tester, heading: 'Calm');
    expect(find.text('After I coffee'), findsOneWidget);
    await tester.tap(find.text('I did it'));
    await settleDatabase(tester);
    expect((await tester.runAsync(() => store.habits(now: now)))!.single.today,
        CheckInResult.did);
    expectCalm(tester, heading: 'Calm');
    expect(find.text('Done today'), findsOneWidget);
    expect(find.text('See you tomorrow after I coffee.'), findsOneWidget);
    expect(find.text('Check-in 18:30 · reminders off'), findsOneWidget);
    final moment = tester.widget<GardenMoment>(find.byType(GardenMoment));
    expect(moment.stage,
        (await tester.runAsync(() => store.habits(now: now)))!.single.stage);
    final completion = moment.completion;
    await tester.tap(find.text('I did it'));
    await settleDatabase(tester);
    expect(tester.widget<GardenMoment>(find.byType(GardenMoment)).completion,
        completion, reason: 'Duplicate durable day/revision must not replay.');
    now = now.add(const Duration(days: 1));
    await tester.pumpWidget(MaterialApp(
      home: GardenScreen(
        store: store,
        clock: () => now,
        contentRevision: 1,
        testDisableServices: true,
      ),
    ));
    await settleDatabase(tester);
    expectCalm(tester, heading: habit.aspiration);
    expect(find.text('After I coffee'), findsOneWidget);
    expect(find.text('Done today'), findsNothing);
    expect(find.textContaining('See you tomorrow'), findsNothing);
  });

  testWidgets('200 percent short window keeps primary reachable', (tester) async {
    final (store, _) = await fixture(tester);
    await tester.binding.setSurfaceSize(const Size(640, 360));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: GardenScreen(store: store, testDisableServices: true),
    ));
    await settleDatabase(tester);
    expect(find.text('I did it').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('More'));
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Settings and privacy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed durable write never produces a completion', (tester) async {
    final (store, _) = await fixture(tester);
    await tester.pumpWidget(MaterialApp(
      home: GardenScreen(store: store, testDisableServices: true),
    ));
    await settleDatabase(tester);
    // Keep the rendered recipe, but remove its durable record.
    await tester.runAsync(() async {
      final habit = (await store.habits()).single;
      await store.deleteRecord('habits', habit.id);
    });
    await tester.tap(find.text('I did it'));
    await settleDatabase(tester);
    expect(tester.widget<GardenMoment>(find.byType(GardenMoment)).completion,
        isNull);
    expect(find.textContaining("Couldn't save"), findsOneWidget);
    expect(find.text('Reload garden'), findsOneWidget);
  });
}
