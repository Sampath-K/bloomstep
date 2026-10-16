import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> captureVisual(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  await tester.pump();
  expect(tester.takeException(), isNull);
  final output = Platform.environment['BLOOMSTEP_SCREENSHOTS'];
  if (output == null) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output\\$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> loadVisualFonts(WidgetTester tester) async {
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
