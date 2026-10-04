import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/bloomstep_app.dart';
import 'services/single_instance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    try {
      final directory = await getApplicationSupportDirectory();
      final instance = SingleInstance(
        p.join(directory.path, 'instance'),
        () async {
          await windowManager.ensureInitialized();
          await windowManager.show();
          await windowManager.focus();
        },
        (message) => debugPrint(message),
      );
      if (!await instance.start()) exit(0);
    } catch (_) {
      runApp(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: SelectableText(
                  'Bloomstep could not safely open its single app window. Close an existing Bloomstep window and retry. No new garden or session was opened.',
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }
  }
  runApp(const BloomstepApp());
}
