import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/core/coach.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/coach_widgets.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/features/garden/recipe_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'first_habit_invitation_test.dart' show ready;

Future<void> loadFonts(WidgetTester tester) async {
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  if (Platform.isWindows) {
    await tester.runAsync(() async {
      final bytes = await File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytes();
      await (FontLoader(
        'Segoe UI',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    });
  }
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  expect(tester.takeException(), isNull);
  final out = Platform.environment['BLOOMSTEP_SCREENSHOTS'];
  if (out == null) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(out).create(recursive: true);
      await File('$out\\$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  for (final variant in [
    (
      name: 'light',
      size: const Size(1000, 800),
      dark: false,
      scale: 1.0,
      reduce: false,
    ),
    (
      name: 'dark',
      size: const Size(1000, 800),
      dark: true,
      scale: 1.0,
      reduce: false,
    ),
    (
      name: 'compact-large-static',
      size: const Size(420, 820),
      dark: false,
      scale: 2.0,
      reduce: true,
    ),
  ]) {
    testWidgets('earned reveal is accessible and rendered ${variant.name}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(variant.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      await loadFonts(tester);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: variant.dark
                ? BloomstepTheme.dark()
                : BloomstepTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(
                size: variant.size,
                textScaler: TextScaler.linear(variant.scale),
                disableAnimations: variant.reduce,
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: BadgeReveal(
                    badges: [badgeCatalog.first],
                    onDismiss: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('First seed'), findsOneWidget);
      expect(find.text('Growing possibilities'), findsNothing);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('A small surprise.*First seed')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
      final out = Platform.environment['BLOOMSTEP_SCREENSHOTS'];
      if (out != null) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(out).create(recursive: true);
            await File('$out\\badge-${variant.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      semantics.dispose();
    });
  }
  testWidgets('empty earned collection never leaks the catalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BadgeCollection(state: CoachState())),
      ),
    );
    for (final badge in badgeCatalog) {
      expect(find.text(badge.name), findsNothing);
    }
    expect(find.textContaining('No ranks'), findsOneWidget);
  });
  testWidgets('coach Later dismisses without opening a route', (tester) async {
    var dismissed = false, acted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoachCard(
            suggestion: const CoachSuggestion(
              CoachRule.firstSeed,
              'One small beginning.',
              'Plant a habit',
            ),
            onAction: () => acted = true,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Later'));
    expect(dismissed, isTrue);
    expect(acted, isFalse);
  });
  testWidgets(
    'saved planting reveals inside confirmation, practice waits for celebration',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadFonts(tester);
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'synthetic-live-coach'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: BloomstepTheme.light(),
            home: GardenScreen(store: store, testDisableServices: true),
          ),
        ),
      );
      await ready(tester, find.text('A little is enough.'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plant a habit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('custom-anchor')),
        'put my cup away',
      );
      await tester.pump();
      await tester.tap(find.text('Choose a tiny action'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('custom-action')),
        'take one breath',
      );
      await tester.pump();
      await tester.tap(find.text('Choose a celebration'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('custom-celebration')),
        'smile quietly',
      );
      await tester.pump();
      await tester.tap(find.text('Plant this seed'));
      await ready(tester, find.byType(PlantedRecipeDialog));
      await tester.pumpAndSettle();
      expect(find.text('First seed'), findsOneWidget);
      expect(find.byType(BadgeReveal), findsNothing);
      final saved = (await tester.runAsync(store.habits))!.single;
      expect(
        tester
            .widget<PlantedRecipeDialog>(find.byType(PlantedRecipeDialog))
            .habit
            .id,
        saved.id,
      );
      await capture(tester, key, 'live-first-seed');
      await tester.tap(find.text('See my seed'));
      await tester.pumpAndSettle();
      expect(find.byType(BadgeReveal), findsNothing);
      await tester.tap(find.text('Did it'));
      await ready(tester, find.textContaining('That tiny step counts!'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await ready(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is FilledButton &&
              w.enabled &&
              w.child is Text &&
              (w.child as Text).data == 'Did it',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BadgeReveal), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await ready(tester, find.text('Tiny step, real win'));
      expect(find.text('First seed'), findsNothing);
      expect(find.text('Enjoying your garden?'), findsNothing);
      await capture(tester, key, 'live-tiny-win');
      await tester.tap(find.text('Keep growing quietly'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Your small wins'));
      await tester.pumpAndSettle();
      expect(find.text('First seed'), findsOneWidget);
      expect(find.text('Tiny step, real win'), findsOneWidget);
      expect(find.text('Roots taking hold'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
