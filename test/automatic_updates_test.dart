import 'dart:async';
import 'dart:io';

import 'package:bloomstep/services/automatic_updates.dart';
import 'package:bloomstep/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

class Discovery extends UpdateService {
  int calls = 0;
  Object? failure;
  Completer<UpdateInfo?>? pending;
  @override
  Future<UpdateInfo?> check({
    String currentVersion = UpdateService.bundledVersion,
  }) async {
    calls++;
    if (failure != null) throw failure!;
    return pending?.future;
  }
}

void main() {
  late Directory directory;
  late Discovery discovery;
  late AutomaticUpdates updates;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bloomstep-update-test-');
    discovery = Discovery();
    updates = AutomaticUpdates(
      preferences: File('${directory.path}\\preferences.json'),
      discovery: discovery,
      interval: const Duration(milliseconds: 20),
    );
  });
  tearDown(() async {
    updates.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'checks automatically at startup and while running; durable opt out',
    () async {
      await updates.start();
      expect(discovery.calls, 1);
      expect(updates.status, contains('manual updates'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(discovery.calls, greaterThan(1));
      await updates.setEnabled(false);
      final count = discovery.calls;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(discovery.calls, count);
      final restarted = AutomaticUpdates(
        preferences: updates.preferences,
        discovery: discovery,
      );
      await restarted.start();
      expect(restarted.enabled, isFalse);
      expect(discovery.calls, count);
      restarted.dispose();
    },
  );

  test('overlap is idempotent and disable prevents stale success', () async {
    discovery.pending = Completer<UpdateInfo?>();
    final checking = updates.check();
    await updates.check();
    expect(discovery.calls, 1);
    await updates.setEnabled(false);
    discovery.pending!.complete(
      UpdateInfo(
        '0.2.0',
        Uri.parse('https://github.com/Sampath-K/bloomstep/releases/tag/v0.2.0'),
        false,
      ),
    );
    await checking;
    expect(updates.status, contains('disabled'));
    expect(updates.checking, isFalse);
  });

  test('offline/auth failure and invalid preferences stay visible', () async {
    discovery.failure = const SocketException('offline');
    await updates.start();
    expect(updates.status, contains('failed'));
    expect(updates.status, contains('nothing was installed'));
    await updates.preferences.writeAsString('corrupt');
    final restarted = AutomaticUpdates(
      preferences: updates.preferences,
      discovery: discovery,
    );
    await restarted.start();
    expect(restarted.enabled, isFalse);
    expect(restarted.status, contains('could not start'));
    restarted.dispose();
  });
}
