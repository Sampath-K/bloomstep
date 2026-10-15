import 'dart:convert';
import 'dart:io';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GardenStore guest;
  late GardenStore account;
  setUp(() async {
    guest = await GardenStore.open(':memory:', 'device-guest');
    account = await GardenStore.open(':memory:', 'account-a');
  });
  tearDown(() async {
    await guest.close();
    await account.close();
  });

  Future<Habit> plant(GardenStore store, String label) => store.plant(
    aspiration: label,
    anchor: 'pour coffee',
    behavior: 'breathe',
    celebration: 'smile',
    species: 'Cosmos',
  );

  test(
    'copy preserves originals and history, never consent or feedback',
    () async {
      final habit = await plant(guest, 'Device habit');
      await guest.checkIn(
        habit.id,
        CheckInResult.did,
        now: DateTime(2026, 10, 14),
      );
      await guest.reflect(habit.id, [3, 3, 3, 3], now: DateTime(2026, 10, 14));
      await guest.setSetting('analytics', 'true');
      await guest.setSetting('reminders', 'true');
      await guest.submitVoice('Question', 'Local private feedback');
      final original = await guest.export();
      expect(
        await account.copyDeviceGardenFrom(guest, authorized: () => true),
        1,
      );
      expect(await guest.export(), original);
      final copy = (await account.habits(now: DateTime(2026, 10, 14))).single;
      expect(copy.id, isNot(habit.id));
      expect(copy.aspiration, habit.aspiration);
      expect(copy.practiceCount, 1);
      final data = await account.export();
      expect(data['checkins'], hasLength(1));
      expect(data['reflections'], hasLength(1));
      expect(data['events'], isEmpty);
      expect(data['voice'], isEmpty);
      expect(await account.setting('analytics'), isNull);
      expect(await account.setting('reminders'), isNull);
      final payload = await account.syncPayload();
      expect(payload['habits'], hasLength(1));
      final contract = Uri.file(
        '${Directory.current.path}${Platform.pathSeparator}api'
        '${Platform.pathSeparator}src${Platform.pathSeparator}contracts.mjs',
      );
      final validation = await Process.run('node', [
        '--input-type=module',
        '-e',
        'const {syncSchema} = await import(process.argv[1]); '
            'syncSchema.parse(JSON.parse(process.argv[2]));',
        contract.toString(),
        jsonEncode(payload),
      ]);
      expect(validation.exitCode, 0, reason: '${validation.stderr}');
    },
  );

  test(
    'retries and concurrent copies are idempotent and preserve account edits',
    () async {
      await plant(guest, 'Device habit');
      expect(
        await account.copyDeviceGardenFrom(guest, authorized: () => true),
        1,
      );
      final copy = (await account.habits()).single;
      await account.edit(
        copy,
        anchor: 'Account edit',
        behavior: 'breathe',
        celebration: 'smile',
      );
      expect(
        await Future.wait([
          account.copyDeviceGardenFrom(guest, authorized: () => true),
          account.copyDeviceGardenFrom(guest, authorized: () => true),
        ]),
        [0, 0],
      );
      expect((await account.habits()).single.anchor, 'Account edit');
      await account.deleteRecord('habits', copy.id);
      expect(
        await account.copyDeviceGardenFrom(guest, authorized: () => true),
        0,
      );
      expect(await account.habits(), isEmpty);
    },
  );

  test(
    'copy is isolated per destination and rejects account-to-account input',
    () async {
      await plant(guest, 'Device habit');
      final other = await GardenStore.open(':memory:', 'account-b');
      try {
        await account.copyDeviceGardenFrom(guest, authorized: () => true);
        expect(await other.habits(), isEmpty);
        await expectLater(
          other.copyDeviceGardenFrom(account, authorized: () => true),
          throwsStateError,
        );
        await other.copyDeviceGardenFrom(guest, authorized: () => true);
        expect(
          (await other.habits()).single.id,
          isNot((await account.habits()).single.id),
        );
      } finally {
        await other.close();
      }
    },
  );

  test('authorization lost before commit rolls back the entire copy', () async {
    await plant(guest, 'First');
    await plant(guest, 'Second');
    var checks = 0;
    await expectLater(
      account.copyDeviceGardenFrom(guest, authorized: () => ++checks < 3),
      throwsStateError,
    );
    expect(await account.habits(), isEmpty);
    expect(await guest.habits(), hasLength(2));
    expect(
      await account.copyDeviceGardenFrom(guest, authorized: () => true),
      2,
    );
  });

  test('cancelled consent makes no account writes', () async {
    await plant(guest, 'Device habit');
    await expectLater(
      account.copyDeviceGardenFrom(guest, authorized: () => false),
      throwsStateError,
    );
    expect(await account.habits(), isEmpty);
    expect(await guest.habits(), hasLength(1));
  });

  test(
    'copy retry remains idempotent after closing and reopening the account',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bloomstep-copy-',
      );
      final file = '${directory.path}${Platform.pathSeparator}account.sqlite';
      var destination = await GardenStore.open(file, 'account-a');
      try {
        await plant(guest, 'Persistent device habit');
        expect(
          await destination.copyDeviceGardenFrom(guest, authorized: () => true),
          1,
        );
        final id = (await destination.habits()).single.id;
        await destination.close();
        destination = await GardenStore.open(file, 'account-a');
        expect(
          await destination.copyDeviceGardenFrom(guest, authorized: () => true),
          0,
        );
        expect((await destination.habits()).single.id, id);
      } finally {
        await destination.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
