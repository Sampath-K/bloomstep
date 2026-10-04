import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/features/garden/plant_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('garden and all five stages render with accessible controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    if (Platform.isWindows) {
      await tester.runAsync(() async {
        final bytes = await File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytes();
        await (FontLoader(
          'Segoe UI',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
    }
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'visual-test-only'),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        final recipe = starterRecipes[i];
        final habit = await store.plant(
          aspiration: recipe.aspiration,
          anchor: recipe.anchor,
          behavior: recipe.behavior,
          celebration: recipe.celebration,
          species: ['Cosmos', 'Sunflower', 'Fern'][i],
        );
        for (var day = 0; day < [3, 21, 10][i]; day++) {
          await store.checkIn(
            habit.id,
            CheckInResult.did,
            now: DateTime.now().subtract(Duration(days: day)),
          );
        }
      }
    });
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: BloomstepTheme.light(),
        home: RepaintBoundary(
          key: boundaryKey,
          child: GardenScreen(store: store),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Did it'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    final output = Platform.environment['BLOOMSTEP_SCREENSHOTS'];
    if (output != null) {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output\\garden.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: BloomstepTheme.light(),
        home: Scaffold(
          body: Wrap(
            children: [
              for (final stage in GrowthStage.values)
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Column(
                    children: [
                      Expanded(
                        child: PlantArt(stage: stage, species: 'Cosmos'),
                      ),
                      Text(stage.name),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final stage in GrowthStage.values) {
      expect(find.text(stage.name), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
