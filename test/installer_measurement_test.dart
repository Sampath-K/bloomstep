import 'dart:convert';
import 'dart:io';

import 'package:bloomstep/services/installer_measurement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late InstallerMeasurement collector;
  late DateTime now;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'bloomstep-receipt-test-',
    );
    now = DateTime.utc(2026, 10, 5, 12);
    collector = InstallerMeasurement(
      directory.path,
      clock: () => now,
      ownerId: '00000000-0000-4000-8000-000000000001',
    );
  });
  tearDown(() => directory.delete(recursive: true));
  Future<void> seed({
    bool completed = true,
    String source = 'installer',
  }) async {
    await File(collector.path).writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'source': source,
        'consentedAt': now
            .subtract(const Duration(minutes: 2))
            .toIso8601String(),
        'events': [
          {
            'id': '00000000-0000-4000-8000-000000000001',
            'name': source == 'website' ? 'landing_view' : 'installer_started',
            'ts': now.subtract(const Duration(minutes: 2)).toIso8601String(),
          },
          if (completed && source == 'installer')
            {
              'id': '00000000-0000-4000-8000-000000000002',
              'name': 'install_completed',
              'ts': now.subtract(const Duration(minutes: 1)).toIso8601String(),
            },
        ],
      }),
    );
  }

  test(
    'no receipt means no observation and no manufactured install history',
    () async {
      expect(await collector.observe('first_launch'), false);
      expect(await collector.observe('signin_view'), false);
      expect(await directory.list().toList(), isEmpty);
    },
  );
  test(
    'observes actual first launch and shown sign-in once, with original times',
    () async {
      await seed();
      expect(await collector.observe('first_launch'), true);
      now = now.add(const Duration(seconds: 2));
      expect(await collector.observe('signin_view'), true);
      expect(await collector.observe('first_launch'), false);
      expect(await collector.observe('signin_view'), false);
      final receipt = await collector.read();
      expect(receipt!.events.map((e) => e.name), [
        'installer_started',
        'install_completed',
        'first_launch',
        'signin_view',
      ]);
      expect(receipt.events.last.at, now);
      await collector.clear();
      expect(await directory.list().toList(), isEmpty);
    },
  );
  test('incomplete, foreign-source and expired receipts cannot imply a successful install', () async {
    await seed(completed: false);
    expect(await collector.observe('first_launch'), false);
    await seed(source: 'website');
    await expectLater(collector.read(), throwsFormatException);
    await seed();
    now = now.add(const Duration(days: 7));
    expect(await collector.read(), null);
    expect(await directory.list().toList(), isEmpty);
  });
  test(
    'malformed and failed local writes are surfaced, no replacement history',
    () async {
      await File(collector.path).writeAsString('private invalid JSON');
      await expectLater(
        collector.observe('first_launch'),
        throwsFormatException,
      );
      expect(await File(collector.path).readAsString(), 'private invalid JSON');
      await File(collector.path).delete();
      await seed();
      await Directory('${collector.path}.pending').create();
      await expectLater(
        collector.observe('first_launch'),
        throwsA(isA<FileSystemException>()),
      );
      expect((await collector.read())!.events, hasLength(2));
    },
  );
  test(
    'portable or different installs cannot attribute another installer receipt',
    () async {
      await seed();
      final portable = InstallerMeasurement(directory.path, clock: () => now);
      expect(await portable.observe('first_launch'), false);
      final different = InstallerMeasurement(
        directory.path,
        clock: () => now,
        ownerId: '00000000-0000-4000-8000-000000000099',
      );
      expect(await different.observe('first_launch'), false);
      expect((await collector.read())!.events, hasLength(2));
    },
  );
}
