import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<Habit> plant(GardenStore store) => store.plant(
  aspiration: 'Calm',
  anchor: 'pour my coffee',
  behavior: 'take one slow breath',
  celebration: 'smile',
  species: 'Cosmos',
);

void main() {
  testWidgets(
    'explicit rest reason offers an accessible, optional recipe edit only',
    (tester) async {
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'recovery-guest'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      if (Platform.isWindows) {
        await tester.runAsync(() async {
          final font = await File(r'C:\Windows\Fonts\segoeui.ttf')
              .readAsBytes();
          await (FontLoader(
            'Segoe UI',
          )..addFont(Future.value(ByteData.sublistView(font)))).load();
        });
      }
      final habit = (await tester.runAsync(() => plant(store)))!;
      await tester.runAsync(
        () =>
            store.checkIn(habit.id, CheckInResult.notToday, reason: 'too hard'),
      );
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: BloomstepTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(1.5),
            ),
            child: RepaintBoundary(
              key: boundaryKey,
              child: GardenScreen(
                store: store,
                deviceGuest: true,
                testDisableServices: true,
              ),
            ),
          ),
        ),
      );
      await waitFor(tester, find.text('Adjust my recipe'));
      expect(find.textContaining('One optional idea:'), findsOneWidget);
      expect(find.text('Resting today. Growth stays.'), findsOneWidget);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
        Duration.zero,
      );
      expect(tester.takeException(), isNull);
      final screenshotDirectory = Platform.environment['BLOOMSTEP_SCREENSHOTS'];
      if (screenshotDirectory != null) {
        await tester.ensureVisible(find.text('Adjust my recipe'));
        await tester.pumpAndSettle();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(screenshotDirectory).create(recursive: true);
          await File(
            p.join(screenshotDirectory, 'recovery-rest-day-400x900.png'),
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.ensureVisible(find.text('Adjust my recipe'));
      await tester.tap(find.text('Adjust my recipe'));
      await tester.pumpAndSettle();
      expect(find.text('Adjust your recipe'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(store.habits))!.single.behavior,
        'take one slow breath',
      );

      await tester.ensureVisible(find.text('Adjust my recipe'));
      await tester.tap(find.text('Adjust my recipe'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'I will...'),
        'take one easy breath',
      );
      await tester.ensureVisible(find.text('Save recipe'));
      await tester.tap(find.text('Save recipe'));
      await waitFor(tester, find.text('Adjust my recipe'));
      final adjusted = (await tester.runAsync(store.habits))!.single;
      expect(adjusted.behavior, 'take one easy breath');
      expect(adjusted.today, CheckInResult.notToday);
      expect(adjusted.todayReason, 'too hard');
      expect(adjusted.practiceCount, 0);
      expect(adjusted.stage, GrowthStage.seed);
      expect(find.textContaining('One optional idea:'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(1.5),
            ),
            child: GardenScreen(
              store: store,
              deviceGuest: true,
              testDisableServices: true,
            ),
          ),
        ),
      );
      await waitFor(tester, find.text('Adjust my recipe'));
      expect(find.textContaining('One optional idea:'), findsOneWidget);

      await tester.ensureVisible(find.text('Undo today'));
      await tester.tap(find.text('Undo today'));
      await waitFor(tester, find.text('Did it'));
      expect(find.textContaining('One optional idea:'), findsNothing);
      expect((await tester.runAsync(store.habits))!.single.todayReason, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'no activity and a reasonless rest choice never infer a recovery reason',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'recovery-skip'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      final habit = (await tester.runAsync(() => plant(store)))!;
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(
            store: store,
            deviceGuest: true,
            testDisableServices: true,
          ),
        ),
      );
      await waitFor(tester, find.text('Not today'));
      expect(find.textContaining('One optional idea:'), findsNothing);

      await tester.ensureVisible(find.text('Not today'));
      await tester.tap(find.text('Not today'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('No reason needed'));
      await tester.tap(find.text('No reason needed'));
      await waitFor(tester, find.text('Resting today. Growth stays.'));
      expect(find.textContaining('One optional idea:'), findsNothing);
      final skipped = (await tester.runAsync(store.habits))!.single;
      expect(skipped.today, CheckInResult.notToday);
      expect(skipped.todayReason, isNull);

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(
        (await tester.runAsync(() => store.habits(now: tomorrow)))!
            .single
            .today,
        isNull,
      );
      expect(
        (await tester.runAsync(() => store.habits(now: tomorrow)))!
            .single
            .todayReason,
        isNull,
      );
      expect((await tester.runAsync(store.habits))!.single.id, habit.id);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('graduated habits never show recovery guidance', (tester) async {
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'recovery-graduated'),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    final habit = (await tester.runAsync(() => plant(store)))!;
    final today = DateTime.now();
    for (var day = 1; day <= 28; day++) {
      await tester.runAsync(
        () => store.checkIn(
          habit.id,
          CheckInResult.did,
          now: today.subtract(Duration(days: day)),
        ),
      );
    }
    await tester.runAsync(
      () => store.reflect(habit.id, [
        7,
        7,
        7,
        7,
      ], now: today.subtract(const Duration(days: 14))),
    );
    await tester.runAsync(
      () => store.reflect(habit.id, [7, 7, 7, 7], now: today),
    );
    await tester.runAsync(
      () => store.checkIn(
        habit.id,
        CheckInResult.notToday,
        reason: 'too hard',
        now: today,
      ),
    );
    expect((await tester.runAsync(store.habits))!.single.status, 'graduated');

    await tester.pumpWidget(
      MaterialApp(
        home: GardenScreen(
          store: store,
          deviceGuest: true,
          testDisableServices: true,
        ),
      ),
    );
    await waitFor(tester, find.text('Evergreen Grove'));
    expect(find.textContaining('One optional idea:'), findsNothing);
    expect(find.text('Did it'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed check-in save shows the existing error and no recovery content',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'bloomstep-recovery-failure-',
      );
      addTearDown(() => root.delete(recursive: true));
      final path = '${root.path}${Platform.pathSeparator}garden.sqlite';
      final store = (await tester.runAsync(
        () => GardenStore.open(path, 'recovery-failure'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      final habit = (await tester.runAsync(() => plant(store)))!;
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(
            store: store,
            deviceGuest: true,
            testDisableServices: true,
          ),
        ),
      );
      await waitFor(tester, find.text('Not today'));
      await tester.runAsync(() async {
        final db = await databaseFactoryFfi.openDatabase(path);
        try {
          await db.execute(
            "CREATE TRIGGER fail_checkin BEFORE INSERT ON checkins "
            "BEGIN SELECT RAISE(ABORT, 'planned check-in failure'); END",
          );
        } finally {
          await db.close();
        }
      });

      await tester.ensureVisible(find.text('Not today'));
      await tester.tap(find.text('Not today'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('I forgot'));
      await tester.tap(find.text('I forgot'));
      await waitFor(tester, find.textContaining('planned check-in failure'));
      expect(find.textContaining('One optional idea:'), findsNothing);
      expect(find.text('Resting today. Growth stays.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      final unchanged = (await tester.runAsync(store.habits))!.single;
      expect(unchanged.id, habit.id);
      expect(unchanged.today, isNull);
      expect(unchanged.todayReason, isNull);
      expect(unchanged.practiceCount, 0);
      expect(unchanged.behavior, 'take one slow breath');
    },
  );
}
