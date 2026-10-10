import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/features/garden/profile_section.dart';
import 'package:bloomstep/services/identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets(
    'synthetic photo preserves avatar-only surface and evicts on sign-out',
    (tester) async {
      if (Platform.isWindows) {
        await tester.runAsync(() async {
          final font = await File(r'C:\Windows\Fonts\segoeui.ttf')
              .readAsBytes();
          await (FontLoader(
            'Segoe UI',
          )..addFont(Future.value(ByteData.sublistView(font)))).load();
          final icons = await File(
            p.join(
              File(Platform.resolvedExecutable).parent.parent.parent.path,
              'material_fonts',
              'MaterialIcons-Regular.otf',
            ),
          ).readAsBytes();
          await (FontLoader(
            'MaterialIcons',
          )..addFont(Future.value(ByteData.sublistView(icons)))).load();
        });
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 112, 112),
        Paint()..color = const Color(0xffc8e6c9),
      );
      canvas.drawCircle(
        const Offset(56, 42),
        22,
        Paint()..color = const Color(0xff388e3c),
      );
      canvas.drawOval(
        const Rect.fromLTWH(18, 67, 76, 65),
        Paint()..color = const Color(0xff388e3c),
      );
      final picture = recorder.endRecording();
      final image = await tester.runAsync(() => picture.toImage(112, 112));
      final data = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.png),
      );
      final bytes = data!.buffer.asUint8List();
      image!.dispose();
      picture.dispose();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: BloomstepTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 640,
                height: 112,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: ProfileSection(
                    signedIn: true,
                    configured: true,
                    busy: false,
                    profile: IdentityProfile(
                      displayName: 'Synthetic Photo',
                      photoBytes: bytes,
                    ),
                    onSignIn: () async {},
                    onSignOut: () async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Synthetic Photo'), findsNothing);
      expect(find.text('Signed in'), findsNothing);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['BLOOMSTEP_SCREENSHOTS'];
      if (output != null) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final capture = await boundary.toImage(pixelRatio: 2);
          final png = await capture.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(p.join(output, 'microsoft-photo-SYNTHETIC.png'))
              .writeAsBytes(png!.buffer.asUint8List());
          capture.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(PaintingBinding.instance.imageCache.currentSize, 0);
    },
  );
}
