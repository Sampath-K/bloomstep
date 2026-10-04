import 'dart:convert';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/measurement_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5, 12);
  final observed = now.subtract(const Duration(minutes: 5));
  Map<String, Object?> receipt({String source = 'website'}) => {
    'schemaVersion': 1,
    'source': source,
    'consentedAt': observed.toIso8601String(),
    'events': [
      {
        'id': '00000000-0000-4000-8000-000000000001',
        'name': source == 'website' ? 'landing_view' : 'installer_started',
        'ts': observed.toIso8601String(),
      },
      {
        'id': '00000000-0000-4000-8000-000000000002',
        'name': source == 'website' ? 'download_click' : 'install_completed',
        'ts': observed.add(const Duration(seconds: 1)).toIso8601String(),
      },
    ],
  };
  MeasurementReceipt parse(Map<String, Object?> data) =>
      MeasurementReceipt.parse(jsonEncode(data), now: now);

  test(
    'strict bounded receipts reject private fields and invented history',
    () {
      expect(parse(receipt()).events, hasLength(2));
      expect(
        () => parse({...receipt(), 'email': 'private'}),
        throwsFormatException,
      );
      final privateEvent = receipt();
      ((privateEvent['events'] as List).first as Map)['url'] = 'private';
      expect(() => parse(privateEvent), throwsFormatException);
      final wrongSource = receipt();
      ((wrongSource['events'] as List).first as Map)['name'] =
          'signin_succeeded';
      expect(() => parse(wrongSource), throwsFormatException);
      expect(
        () => parse({...receipt(), 'source': 'silent_install'}),
        throwsFormatException,
      );
      expect(
        () => parse({
          ...receipt(),
          'consentedAt': now.add(const Duration(minutes: 1)).toIso8601String(),
        }),
        throwsFormatException,
      );
      expect(
        () => parse({
          ...receipt(),
          'consentedAt': now
              .subtract(const Duration(days: 7))
              .toIso8601String(),
        }),
        throwsFormatException,
      );
      expect(
        () => parse({...receipt(), 'schemaVersion': 2}),
        throwsFormatException,
      );
      expect(
        () => parse({
          ...receipt(),
          'events': List.filled(33, (receipt()['events'] as List).first),
        }),
        throwsFormatException,
      );
      expect(
        () => MeasurementReceipt.parse('x' * 16385, now: now),
        throwsFormatException,
      );
      final duplicate = receipt();
      (duplicate['events'] as List).add((duplicate['events'] as List).first);
      expect(() => parse(duplicate), throwsFormatException);
      final reversed = receipt();
      reversed['events'] = (reversed['events'] as List).reversed.toList();
      expect(() => parse(reversed), throwsFormatException);
      final missingStart = receipt(source: 'installer');
      (missingStart['events'] as List).removeAt(0);
      expect(() => parse(missingStart), throwsFormatException);
    },
  );

  test(
    'import requires both source consent and explicit current-account consent',
    () async {
      final store = await GardenStore.open(':memory:', 'receipt-account-a');
      addTearDown(store.close);
      final data = parse(receipt());
      await expectLater(
        store.importMeasurementReceipt(data, now: now),
        throwsStateError,
      );
      await store.setSetting('analytics', 'true');
      final count = await store.importMeasurementReceipt(data, now: now);
      expect(count, 2);
      final events = (await store.export())['events'] as List;
      final imported =
          events.firstWhere((e) => (e as Map)['name'] == 'landing_view') as Map;
      expect(imported['ts'], observed.toIso8601String());
      expect(jsonDecode(imported['properties'] as String), {
        'platform': 'web',
        'channel': 'website',
        'measurementSource': 'website_receipt',
      });
      expect(await store.importMeasurementReceipt(data, now: now), 0);
      await expectLater(
        store.importMeasurementReceipt(
          data,
          now: now.add(const Duration(days: 7)),
        ),
        throwsFormatException,
      );
      await store.switchAccount('receipt-account-b');
      await store.setSetting('analytics', 'true');
      await expectLater(
        store.importMeasurementReceipt(data, now: now),
        throwsStateError,
      );
      expect(((await store.export())['events'] as List).length, 1);
      await store.switchAccount('receipt-account-a');
      await store.setSetting('analytics', 'false');
      expect((await store.export())['events'], isEmpty);
      expect((await store.syncPayload())['events'], isEmpty);
    },
  );

  test(
    'conflicting retries roll back the entire import, never overwrite history',
    () async {
      final store = await GardenStore.open(':memory:', 'receipt-conflict');
      addTearDown(store.close);
      await store.setSetting('analytics', 'true');
      await store.importMeasurementReceipt(parse(receipt()), now: now);
      final changed = receipt();
      final rows = changed['events'] as List;
      rows[0] = {
        'id': '00000000-0000-4000-8000-000000000003',
        'name': 'landing_view',
        'ts': observed.toIso8601String(),
      };
      (rows[1] as Map)['name'] = 'landing_view';
      await expectLater(
        store.importMeasurementReceipt(parse(changed), now: now),
        throwsStateError,
      );
      expect(((await store.export())['events'] as List).length, 3);
    },
  );
}
