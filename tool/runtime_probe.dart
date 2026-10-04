import 'dart:convert';
import 'dart:io';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/services/desktop_reminders.dart';
import 'package:bloomstep/services/native_share.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  if (kReleaseMode || !Platform.isWindows) {
    throw StateError('This synthetic Windows probe cannot be a release app.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: RuntimeProbe()));
}

class RuntimeProbe extends StatefulWidget {
  const RuntimeProbe({super.key});
  @override
  State<RuntimeProbe> createState() => _RuntimeProbeState();
}

class _RuntimeProbeState extends State<RuntimeProbe> {
  String status =
      'Synthetic local Windows checks are starting. No account or cloud.';
  final report = <String, Object?>{
    'synthetic': true,
    'authentication': 'not tested',
    'popupDelivery': 'not inferred from show acknowledgment or history',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    Directory? folder;
    GardenStore? store;
    DesktopReminders? reminders;
    var cleanupComplete = true;
    try {
      folder = await Directory.systemTemp.createTemp(
        'bloomstep-runtime-probe-',
      );
      store = await GardenStore.open(
        '${folder.path}${Platform.pathSeparator}synthetic.sqlite',
        'synthetic-runtime-probe',
      );
      final now = DateTime.now();
      final minute = now.hour * 60 + now.minute;
      await store.setSetting('quietStart', '${(minute + 30) % 1440}');
      await store.setSetting('quietEnd', '${(minute + 31) % 1440}');
      await store.setSetting('reminderMinute', '$minute');
      await store.plant(
        aspiration: 'Calm',
        anchor: 'finish this synthetic test',
        behavior: 'take one breath',
        celebration: 'smile',
        species: 'Fern',
      );
      final errors = <String>[];
      reminders = DesktopReminders(store, () async {}, errors.add);
      await reminders.enable();
      final bounds = await trayManager.getBounds();
      report['trayBoundsAvailable'] = bounds != null;
      await windowManager.hide();
      report['hiddenBeforeDelivery'] = !await windowManager.isVisible();
      await reminders.tick();
      if (errors.isNotEmpty) throw StateError(errors.join('; '));
      final gateway = reminders.gateway as WindowsReminderGateway;
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      var active = await gateway.notifications.getActiveNotifications();
      while (active.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        active = await gateway.notifications.getActiveNotifications();
      }
      report['ownOsNotificationHistoryCount'] = active.length;
      if (active.isEmpty) {
        throw StateError(
          'Windows did not expose the requested notification in this app history.',
        );
      }
      await reminders.tick();
      final repeated = await gateway.notifications.getActiveNotifications();
      report['capPreservedInOsHistory'] = repeated.length == active.length;
      if (repeated.length != active.length) {
        throw StateError('A repeated tick created another OS notification.');
      }
      await reminders.disable();
      report['offRestoredVisibleWindow'] = await windowManager.isVisible();
      report['ownHistoryCleared'] =
          (await gateway.notifications.getActiveNotifications()).isEmpty;
      if (report['offRestoredVisibleWindow'] != true ||
          report['ownHistoryCleared'] != true) {
        throw StateError(
          'Turning reminders off did not restore the window and clear its history.',
        );
      }
      if (Platform.environment['BLOOMSTEP_RUNTIME_SHARE'] == '1') {
        await NativeShare.share(
          Uri.parse('https://example.com/bloomstep-synthetic-share-probe'),
        );
        report['shareSurfaceRequested'] = true;
        report['shareSurfaceObserved'] = 'Requires independent OS observation';
        report['shareTransmission'] = 'Not requested or inferred';
      }
      report['passed'] = true;
      if (mounted) {
        setState(
          () => status = 'Windows history, tray, hidden tick, caps and Off lifecycle observed. Popup delivery is not inferred.',
        );
      }
    } catch (error) {
      report['passed'] = false;
      report['error'] = error.toString();
      if (mounted) {
        setState(() => status = 'Synthetic Windows check failed: $error');
      }
    } finally {
      try {
        await reminders?.dispose();
        await store?.close();
        await folder?.delete(recursive: true);
      } catch (error) {
        cleanupComplete = false;
        report['passed'] = false;
        report['cleanupError'] = error.toString();
        if (mounted) {
          setState(() => status = 'Synthetic Windows cleanup failed: $error');
        }
      }
      report['cleanupComplete'] = cleanupComplete;
      report['capturedAt'] = DateTime.now().toUtc().toIso8601String();
      final output = Platform.environment['BLOOMSTEP_RUNTIME_REPORT'];
      if (output == null) {
        debugPrint(jsonEncode(report));
      } else {
        await File(output).writeAsString(jsonEncode(report), flush: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('SYNTHETIC WINDOWS RUNTIME PROBE - NOT A RELEASE'),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: SelectableText(status),
      ),
    ),
  );
}
