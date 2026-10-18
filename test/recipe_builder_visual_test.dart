import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/features/garden/recipe_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'support/visual_capture.dart';

void main() {
  for (final variant in [
    (name: 'desktop', size: const Size(1200, 920), dark: false, scale: 1.0),
    (name: 'compact', size: const Size(420, 820), dark: false, scale: 1.0),
    (name: 'dark', size: const Size(1200, 920), dark: true, scale: 1.0),
    (name: 'large-text', size: const Size(420, 820), dark: false, scale: 2.0),
    (name: 'dark-large-text', size: const Size(420, 820), dark: true, scale: 2.0),
    (name: 'short-light', size: const Size(800, 480), dark: false, scale: 1.0),
    (name: 'short-dark', size: const Size(800, 480), dark: true, scale: 1.0),
    (
      name: 'short-large-light',
      size: const Size(800, 600),
      dark: false,
      scale: 2.0,
    ),
    (
      name: 'short-large-dark',
      size: const Size(800, 600),
      dark: true,
      scale: 2.0,
    ),
  ]) {
    testWidgets('primary picker renders ${variant.name} without clipping', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(variant.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await loadVisualFonts(tester);
      final boundaryKey = GlobalKey();
      Future<void> capture(String stage) async {
        expect(tester.takeException(), isNull);
        final output = Platform.environment['BLOOMSTEP_SCREENSHOTS'];
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            expect(bytes, isNotNull);
            final png = bytes!.buffer.asUint8List();
            expect(png, isNotEmpty);
            if (output != null) {
              await Directory(output).create(recursive: true);
              await File(p.join(output, 'picker-${variant.name}-$stage.png'))
                  .writeAsBytes(png);
            }
          } finally {
            image.dispose();
          }
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: variant.dark
                ? BloomstepTheme.dark()
                : BloomstepTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(variant.scale)),
              child: Column(
                children: [
                  const Material(
                    child: Text(
                      'SYNTHETIC UI - disposable garden, no live account',
                    ),
                  ),
                  Expanded(child: child!),
                ],
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final draft = await showDialog<RecipeDraft>(
                      context: context,
                      builder: (_) => const RecipeBuilder(),
                    );
                    if (draft == null || !context.mounted) return;
                    await showDialog<void>(
                      context: context,
                      builder: (_) => PlantedRecipeDialog(
                        habit: Habit(
                          id: 'synthetic-visual-seed',
                          aspiration: draft.aspiration,
                          anchor: draft.anchor,
                          behavior: draft.behavior,
                          celebration: draft.celebration,
                          species: draft.species,
                          stage: GrowthStage.seed,
                          status: 'active',
                          practiceCount: 0,
                          recentPractice: 0,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open synthetic picker'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open synthetic picker'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeBuilder), findsOneWidget);
      await capture('1-moment-SYNTHETIC');
      await tester.ensureVisible(find.byKey(const ValueKey('custom-anchor')));
      await tester.enterText(
        find.byKey(const ValueKey('custom-anchor')),
        'put my synthetic mug down',
      );
      await tester.pumpAndSettle();
      await capture('1-custom-anchor-SYNTHETIC');
      await tester.ensureVisible(find.text('pour my morning drink'));
      await tester.tap(find.text('pour my morning drink'));
      await tester.pumpAndSettle();
      await capture('2-action');
      await tester.ensureVisible(find.byKey(const ValueKey('custom-action')));
      await tester.enterText(
        find.byKey(const ValueKey('custom-action')),
        'stretch one synthetic finger',
      );
      await tester.pumpAndSettle();
      await capture('2-custom-action-SYNTHETIC');
      await tester.ensureVisible(find.text('take one slow breath'));
      await tester.tap(find.text('take one slow breath'));
      await tester.pumpAndSettle();
      await capture('3-celebration');
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-celebration')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('custom-celebration')),
        'say a quiet synthetic hooray',
      );
      await tester.pumpAndSettle();
      await capture('3-custom-celebration-SYNTHETIC');
      await tester.ensureVisible(find.text('relax my shoulders and smile'));
      await tester.tap(find.text('relax my shoulders and smile'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('I practiced my celebration'));
      await tester.pumpAndSettle();
      await capture('complete');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.text('Plant this seed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PlantedRecipeDialog), findsOneWidget);
      await capture('growth-start-SYNTHETIC');
      await tester.pump(const Duration(milliseconds: 700));
      await capture('growth-middle-SYNTHETIC');
      await tester.pumpAndSettle();
      await capture('planted');
      expect(find.text('Your seed is planted'), findsOneWidget);
      final continuation = find.widgetWithText(FilledButton, 'See my garden');
      expect(continuation, findsOneWidget);
      expect(tester.getRect(continuation).bottom, lessThan(variant.size.height));
      await tester.ensureVisible(
        find.text('Try it when your moment comes. Practicing now is optional.'),
      );
      await tester.pumpAndSettle();
      await capture('planted-next-cue');
      await tester.tap(continuation);
      await tester.pumpAndSettle();
      expect(find.byType(PlantedRecipeDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    });
  }
}
