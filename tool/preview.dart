import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';

// Explicit CI-only profile preview. Never the release target or installer.
Future<void> main() async {
  if (kReleaseMode) {
    throw StateError('Synthetic preview is forbidden in release mode.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final temporary = await getTemporaryDirectory();
  final store = await GardenStore.open(
    p.join(temporary.path, 'bloomstep-synthetic-preview.sqlite'),
    'synthetic-preview-only',
  );
  if ((await store.habits()).isEmpty) {
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
          now: DateTime.now().subtract(Duration(days: day + 1)),
        );
      }
    }
  }
  runApp(_SyntheticPreview(store));
}

class _SyntheticPreview extends StatefulWidget {
  const _SyntheticPreview(this.store);
  final GardenStore store;
  @override
  State<_SyntheticPreview> createState() => _SyntheticPreviewState();
}

class _SyntheticPreviewState extends State<_SyntheticPreview> {
  final boundary = GlobalKey();
  final semantics = WidgetsBinding.instance.ensureSemantics();
  String? captureError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(seconds: 3));
      await _capture();
    });
  }

  Future<void> _capture() async {
    final folder = Platform.environment['BLOOMSTEP_PREVIEW_ARTIFACTS'];
    if (!mounted || folder == null) return;
    try {
      await WidgetsBinding.instance.endOfFrame;
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final content = bytes!.buffer.asUint8List();
        final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
          ':',
          '-',
        );
        await Directory(folder).create(recursive: true);
        await File(p.join(folder, 'native-synthetic-$timestamp.png'))
            .writeAsBytes(content);
        await File(p.join(folder, 'native-synthetic-garden.png'))
            .writeAsBytes(content);
      } finally {
        image.dispose();
      }
    } catch (e) {
      if (mounted) {
        setState(() => captureError = 'Preview screenshot failed: $e');
      }
    }
  }

  @override
  void dispose() {
    semantics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bloomstep - isolated synthetic preview',
    theme: BloomstepTheme.light(),
    darkTheme: BloomstepTheme.dark(),
    debugShowCheckedModeBanner: false,
    home: CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): () =>
            unawaited(_capture()),
      },
      child: Focus(
        autofocus: true,
        child: RepaintBoundary(
          key: boundary,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: BloomstepTheme.light().colorScheme.tertiaryContainer,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        captureError ?? 'ISOLATED SYNTHETIC PREVIEW - no account, no cloud, not a release. Ctrl+Shift+S captures this app only.',
                        style: TextStyle(
                          color: BloomstepTheme.light()
                              .colorScheme
                              .onTertiaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: GardenScreen(store: widget.store)),
            ],
          ),
        ),
      ),
    ),
  );
}
