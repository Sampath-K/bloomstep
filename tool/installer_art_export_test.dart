import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/features/garden/plant_art.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const paper = Color(0xFFF7F4EF);

class _RecipeIcon extends CustomPainter {
  const _RecipeIcon(this.kind);
  final int kind;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    final ink = Paint()
      ..color = const Color(0xFF386A47)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    if (kind == 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(7, 16, 26, 24),
          const Radius.circular(5),
        ),
        ink,
      );
      canvas.drawArc(const Rect.fromLTWH(24, 20, 17, 15), -1.5, 3, false, ink);
      for (final x in [14.0, 24.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(x, 10)
            ..quadraticBezierTo(x - 3, 7, x, 3),
          ink,
        );
      }
    } else if (kind == 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, 8, 32, 25),
          const Radius.circular(3),
        ),
        ink,
      );
      canvas.drawPath(
        Path()
          ..moveTo(8, 33)
          ..lineTo(3, 40)
          ..lineTo(45, 40)
          ..lineTo(40, 33),
        ink,
      );
    } else if (kind == 2) {
      canvas.drawCircle(const Offset(24, 24), 17, ink);
      canvas.drawCircle(const Offset(24, 24), 8, ink);
    } else if (kind == 3) {
      canvas.drawLine(const Offset(12, 14), const Offset(37, 14), ink);
      canvas.drawLine(const Offset(12, 24), const Offset(30, 24), ink);
      canvas.drawLine(const Offset(12, 34), const Offset(23, 34), ink);
    } else {
      canvas.drawCircle(const Offset(24, 24), 18, ink);
      canvas.drawCircle(const Offset(18, 20), 1, ink);
      canvas.drawCircle(const Offset(30, 20), 1, ink);
      canvas.drawArc(const Rect.fromLTWH(14, 19, 20, 15), 0.2, 2.7, false, ink);
    }
  }

  @override
  bool shouldRepaint(_RecipeIcon oldDelegate) => kind != oldDelegate.kind;
}

Widget stepCircle(int kind) => Container(
  width: 190,
  height: 190,
  padding: const EdgeInsets.all(42),
  decoration: BoxDecoration(
    color: const Color(0xFFEAF0E3),
    shape: BoxShape.circle,
    border: Border.all(color: const Color(0xFFD5DFCF), width: 3),
  ),
  child: kind == 1
      ? const PlantArt(stage: GrowthStage.sprout, species: 'Cosmos')
      : CustomPaint(painter: _RecipeIcon(kind)),
);

class _Arrow extends CustomPainter {
  const _Arrow();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0xFF8BA889)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final y = size.height / 2;
    canvas.drawLine(Offset(6, y), Offset(size.width - 8, y), ink);
    canvas.drawPath(
      Path()
        ..moveTo(size.width - 26, y - 16)
        ..lineTo(size.width - 8, y)
        ..lineTo(size.width - 26, y + 16),
      ink,
    );
  }

  @override
  bool shouldRepaint(_Arrow oldDelegate) => false;
}

Widget arrow() => const SizedBox(
  width: 90,
  height: 60,
  child: CustomPaint(painter: _Arrow()),
);

Widget illustration(String name) {
  if (name == 'welcome-steps') {
    // Anchor (familiar routine), tiny action (seed sprouting), celebrate.
    // Centers sit at thirds so native word labels align beneath each step.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [stepCircle(0), arrow(), stepCircle(1), arrow(), stepCircle(4)],
    );
  }
  // One plant grows with practice; more anchors grow a garden.
  return Row(
    children: [
      const SizedBox(width: 20),
      for (final stage in GrowthStage.values)
        SizedBox(
          width: 82,
          height: 200,
          child: PlantArt(stage: stage, species: 'Cosmos'),
        ),
      arrow(),
      Expanded(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 20,
              bottom: 22,
              child: Container(
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4EDDA),
                  borderRadius: BorderRadius.circular(60),
                ),
              ),
            ),
            for (var i = 0; i < 5; i++)
              Positioned(
                left: i * 72.0,
                top: i.isEven ? 20 : 60,
                child: SizedBox(
                  width: 130,
                  height: 200,
                  child: PlantArt(
                    stage: GrowthStage.bloom,
                    species: ['Cosmos', 'Fern', 'Sunflower'][i % 3],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
Uint8List bitmap(Uint8List rgba, int width, int height) {
  final stride = ((width * 3 + 3) ~/ 4) * 4;
  final bytes = Uint8List(54 + stride * height);
  final header = ByteData.sublistView(bytes);
  bytes[0] = 66;
  bytes[1] = 77;
  header.setUint32(2, bytes.length, Endian.little);
  header.setUint32(10, 54, Endian.little);
  header.setUint32(14, 40, Endian.little);
  header.setInt32(18, width, Endian.little);
  header.setInt32(22, height, Endian.little);
  header.setUint16(26, 1, Endian.little);
  header.setUint16(28, 24, Endian.little);
  header.setUint32(34, stride * height, Endian.little);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final input = (y * width + x) * 4;
      final output = 54 + (height - 1 - y) * stride + x * 3;
      bytes[output] = rgba[input + 2];
      bytes[output + 1] = rgba[input + 1];
      bytes[output + 2] = rgba[input];
    }
  }
  return bytes;
}

void main() {
  testWidgets(
    'export original full-panel PlantArt illustrations, not screenshots',
    (tester) async {
      expect(
        Platform.environment['BLOOMSTEP_EXPORT_INSTALLER_ART'],
        'true',
        reason: 'Explicit authoring command only; never silently replace committed art.',
      );
      final manifest = <String, Object?>{
        'schemaVersion': 1,
        'kind': 'authored-illustrations-not-installer-screenshots',
        'sourceNormalization': 'UTF-8 text with LF line endings',
        'renderer': 'Flutter PlantArt, supported seed/sprout/sapling/budding/bloom; original vector recipe icons',
        'textEquivalents': 'Native wizard labels Anchor, Action and Celebrate name the three steps; no text baked into these illustrations.',
        'sources': <Object>[],
        'assets': <Object>[],
      };
      await tester.runAsync(() async {
        for (final path in [
          'tool/installer_art_export_test.dart',
          'lib/features/garden/plant_art.dart',
          'lib/app/theme.dart',
        ]) {
          (manifest['sources']! as List<Object>).add({
            'path': path,
            'sha256': sha256
                .convert(
                  utf8.encode(
                    (await File(path).readAsString()).replaceAll('\r\n', '\n'),
                  ),
                )
                .toString(),
          });
        }
      });
      for (final name in [
        'welcome-steps',
        'welcome-garden',
      ]) {
        final height = name == 'welcome-steps' ? 200 : 300;
        await tester.binding.setSurfaceSize(Size(1000, height.toDouble()));
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: BloomstepTheme.light(),
              home: Scaffold(backgroundColor: paper, body: illustration(name)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final raw = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final bytes = bitmap(raw!.buffer.asUint8List(), 1000, height);
          await File('packaging/assets/$name.bmp').writeAsBytes(bytes);
          (manifest['assets']! as List<Object>).add({
            'file': '$name.bmp',
            'width': 1000,
            'height': height,
            'sha256': sha256.convert(bytes).toString(),
          });
          image.dispose();
        });
      }
      await tester.runAsync(
        () => File('packaging/assets/education-art-provenance.json')
            .writeAsString(
              '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
            ),
      );
      await tester.binding.setSurfaceSize(null);
    },
  );
}
