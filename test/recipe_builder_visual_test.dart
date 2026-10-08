import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/app/bloomstep_app.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/recipe_builder.dart';
import 'package:bloomstep/services/identity.dart';
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
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', HabitHome.guestAccount),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
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
            home: HabitHome(
              testIdentity: IdentityService(),
              testOpenStore: (_) async => store,
            ),
          ),
        ),
      );
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(RecipeBuilder).evaluate().isNotEmpty) break;
      }
      expect(find.byType(RecipeBuilder), findsOneWidget);
      await tester.pumpAndSettle();
      await capture('1-anchor-FIRST-RUN-SYNTHETIC');
      await tester.enterText(
        find.byKey(const ValueKey('custom-anchor')),
        'put my synthetic mug down',
      );
      await tester.pump();
      await capture('1-custom-anchor-SYNTHETIC');
      await tester.ensureVisible(find.text('pour my morning drink'));
      await tester.tap(find.text('pour my morning drink'));
      await tester.pumpAndSettle();
      await capture('2-action');
      await tester.enterText(
        find.byKey(const ValueKey('custom-action')),
        'stretch one synthetic finger',
      );
      await tester.pump();
      await capture('2-custom-action-SYNTHETIC');
      await tester.ensureVisible(find.text('take one slow breath'));
      await tester.tap(find.text('take one slow breath'));
      await tester.pumpAndSettle();
      await capture('3-celebration');
      await tester.enterText(
        find.byKey(const ValueKey('custom-celebration')),
        'say a quiet synthetic hooray',
      );
      await tester.pump();
      await capture('3-custom-celebration-SYNTHETIC');
      await tester.ensureVisible(find.text('relax my shoulders and smile'));
      await tester.tap(find.text('relax my shoulders and smile'));
      await tester.pumpAndSettle();
      await capture('complete');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.text('Plant this seed'));
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(PlantedRecipeDialog).evaluate().isNotEmpty) break;
      }
      await capture('growth-start-SYNTHETIC');
      await tester.pump(const Duration(milliseconds: 700));
      await capture('growth-middle-SYNTHETIC');
      await tester.pumpAndSettle();
      await capture('planted');
      expect(find.text('Your seed is planted'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'See my seed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      semantics.dispose();
    });
  }
}
