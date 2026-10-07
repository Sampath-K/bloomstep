import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/features/garden/recipe_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  for (final variant in [
    (name: 'desktop', size: const Size(1200, 920), dark: false, scale: 1.0),
    (name: 'compact', size: const Size(420, 820), dark: false, scale: 1.0),
    (name: 'dark', size: const Size(1200, 920), dark: true, scale: 1.0),
    (name: 'large-text', size: const Size(420, 820), dark: false, scale: 1.5),
  ]) {
    testWidgets('primary picker renders ${variant.name} without clipping', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(variant.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
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
      final boundaryKey = GlobalKey();
      Future<void> capture(String stage) async {
        expect(tester.takeException(), isNull);
        final output = Platform.environment['BLOOMSTEP_SCREENSHOTS'];
        if (output == null) return;
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(output).create(recursive: true);
            await File(p.join(output, 'picker-${variant.name}-$stage.png'))
                .writeAsBytes(bytes!.buffer.asUint8List());
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
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      final draft = await showDialog<RecipeDraft>(
                        context: context,
                        builder: (_) => const RecipeBuilder(),
                      );
                      if (draft != null && context.mounted) {
                        await showDialog<void>(
                          context: context,
                          builder: (_) => PlantedRecipeDialog(recipe: draft),
                        );
                      }
                    },
                    child: const Text('Render synthetic recipe'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Render synthetic recipe'));
      await tester.pumpAndSettle();
      await capture('1-anchor');
      await tester.ensureVisible(find.text('pour my morning drink'));
      await tester.tap(find.text('pour my morning drink'));
      await tester.pumpAndSettle();
      await capture('2-action');
      await tester.ensureVisible(find.text('take one slow breath'));
      await tester.tap(find.text('take one slow breath'));
      await tester.pumpAndSettle();
      await capture('3-celebration');
      await tester.ensureVisible(find.text('relax my shoulders and smile'));
      await tester.tap(find.text('relax my shoulders and smile'));
      await tester.pumpAndSettle();
      await capture('complete');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.text('Plant this seed'));
      await tester.pumpAndSettle();
      await capture('planted');
      expect(find.text('Your seed is planted'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'See my seed'), findsOneWidget);
      semantics.dispose();
    });
  }
}
