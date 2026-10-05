import 'dart:async';
import 'dart:convert';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/services/desktop_reminders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeReminderGateway implements ReminderGateway {
  final requests = <ReminderRequest>[];
  final operations = <String>[];
  bool failShow = false;
  Future<void> Function(ReminderRequest)? beforeShow;
  @override
  Future<void> initialize(Future<void> Function(String) action) async {}
  @override
  Future<void> show(ReminderRequest request) async {
    await beforeShow?.call(request);
    if (failShow) throw StateError('request failed');
    requests.add(request);
    operations.add('request');
  }

  @override
  Future<void> cancel(int id) async => operations.add('cancel:$id');
  @override
  Future<void> cancelAll() async => operations.add('cancelAll');
  @override
  Future<void> showAndFocus() async => operations.add('showAndFocus');
  @override
  Future<void> shutdown() async => operations.add('shutdown');
}

Future<Habit> plantReminder(GardenStore store) => store.plant(
  aspiration: 'Calm',
  anchor: 'coffee',
  behavior: 'breathe',
  celebration: 'smile',
  species: 'Fern',
);

void main() {
  late GardenStore store;
  late FakeReminderGateway gateway;
  late DesktopReminders reminders;
  late DateTime now;
  setUp(() async {
    store = await GardenStore.open(':memory:', 'account-a');
    gateway = FakeReminderGateway();
    now = DateTime(2026, 10, 4, 18);
    reminders = DesktopReminders(
      store,
      () async {},
      (_) {},
      gateway: gateway,
      clock: () => now,
    );
    await reminders.enable();
  });
  tearDown(() async {
    await reminders.dispose();
    await store.close();
  });

  test(
    'stable account+habit IDs avoid tiny bucket and reserved reconnect ID',
    () {
      final ids = {
        for (var i = 0; i < 1000; i++)
          DesktopReminders.notificationId('account-a', 'habit-$i'),
      };
      expect(ids, hasLength(1000));
      expect(ids.every((id) => id > 1 && id <= 0x7fffffff), isTrue);
      expect(
        DesktopReminders.notificationId('a', 'h'),
        DesktopReminders.notificationId('a', 'h'),
      );

      expect(
        DesktopReminders.notificationId('a', 'h'),
        isNot(DesktopReminders.notificationId('b', 'h')),
      );
    },
  );

  test('deletion withdraws only removed recipe notifications, without changing preference or daily caps', () async {
    final a = await plantReminder(store);
    final b = await plantReminder(store);
    await reminders.tick();
    final log = await store.setting('reminderLog');
    gateway.operations.clear();
    await store.deleteRecord('habits', a.id);
    await reminders.removeDeletedRecipes();
    expect(gateway.operations, [
      'cancel:${DesktopReminders.notificationId(store.account, a.id)}',
    ]);
    expect(await store.setting('reminders'), 'true');
    expect(await store.setting('reminderLog'), log);
    expect((await store.habits()).single.id, b.id);
    await reminders.removeDeletedRecipes();
    expect(gateway.operations, hasLength(1));
    await reminders.disable();
    gateway.operations.clear();
    await reminders.removeDeletedRecipes();
    expect(gateway.operations, isEmpty);
    expect(await store.setting('reminders'), 'false');
  });

  test('recipe deleted during a toast request is withdrawn before telemetry and later actions', () async {
    final h = await plantReminder(store);
    await store.setSetting('analytics', 'true');
    gateway.beforeShow = (_) => store.deleteRecord('habits', h.id);
    await reminders.tick();
    expect(
      gateway.operations,
      contains(
        'cancel:${DesktopReminders.notificationId(store.account, h.id)}',
      ),
    );
    final events = (await store.syncPayload())['events'] as List;
    expect(events.where((row) => row['name'] == 'notif_sent'), isEmpty);
    await expectLater(
      reminders.handleAction(gateway.requests.single.payloadFor('did')),
      throwsStateError,
    );
    expect((await store.export())['checkins'], isEmpty);
  });
  test(
    'unsent targeted Later postpones only that habit and survives restart',
    () async {
      final a = await plantReminder(store);
      final b = await plantReminder(store);
      await reminders.snoozeHabit(a.id);
      await reminders.tick();
      expect(gateway.requests.map((r) => r.habitId), [b.id]);
      await reminders.dispose();
      reminders = DesktopReminders(
        store,
        () async {},
        (_) {},
        gateway: gateway,
        clock: () => now,
      );
      await reminders.enable();
      now = now.add(const Duration(hours: 1));
      await reminders.tick();
      expect(gateway.requests.map((r) => r.habitId), [b.id, a.id]);
      await reminders.tick();
      expect(gateway.requests, hasLength(2));
    },
  );

  test(
    'sent Later withdraws request, never redelivers that day or bypasses caps',
    () async {
      final h = await plantReminder(store);
      await reminders.tick();
      final request = gateway.requests.single;
      await reminders.handleAction(request.payloadFor('snooze'));
      expect(await store.setting('ignored:${h.id}'), '0');
      expect(gateway.operations, contains('cancel:${request.id}'));
      expect(await store.setting('snoozeUntil'), isNull);
      now = now.add(const Duration(hours: 2));
      await reminders.tick();
      expect(gateway.requests, hasLength(1));
      now = DateTime(2026, 10, 5, 19);
      await reminders.tick();
      expect(gateway.requests, hasLength(2));
      expect(gateway.requests.last.habitId, h.id);
    },
  );

  test(
    'quiet hours, daily total cap, fewer backoff and seven request pause',
    () async {
      for (var i = 0; i < 4; i++) {
        await plantReminder(store);
      }
      now = DateTime(2026, 10, 4, 22);
      await reminders.tick();
      expect(gateway.requests, isEmpty);
      now = DateTime(2026, 10, 4, 18);
      await reminders.tick();
      expect(gateway.requests, hasLength(3));
      await reminders.tick();
      expect(gateway.requests, hasLength(3));
      final h = (await store.habits()).first;
      await store.setSetting('ignored:${h.id}', '3');
      now = DateTime(2026, 10, 5, 18);
      await reminders.tick();
      expect(gateway.requests.where((r) => r.habitId == h.id), hasLength(1));
      await store.setSetting('ignored:${h.id}', '7');
      for (final other in await store.habits()) {
        if (other.id != h.id) {
          await store.setSetting('ignored:${other.id}', '7');
        }
      }
      now = DateTime(2026, 10, 6, 18);
      await reminders.tick();
      expect(gateway.requests.where((r) => r.habitId == h.id), hasLength(1));
      await reminders.resumeHabit(h.id);
      await reminders.tick();
      expect(gateway.requests.where((r) => r.habitId == h.id), hasLength(2));
    },
  );

  test(
    'each reconnect includes fewer; explicit open resets absence and focuses',
    () async {
      final h = await plantReminder(store);
      await store.setSetting('ignored:${h.id}', '7');
      await store.recordInteraction(now: now.subtract(const Duration(days: 8)));
      await reminders.tick();
      final request = gateway.requests.single;
      expect(request.habitId, '_reconnect');
      expect(request.actions.keys, contains('fewer'));
      await reminders.handleAction(request.payloadFor('fewer'));
      expect(await store.setting('fewerReminders'), 'true');
      await reminders.handleAction(request.payloadFor('open'));
      expect(await store.setting('reconnectCount'), '0');
      expect(
        await store.setting('lastInteraction'),
        now.toUtc().toIso8601String(),
      );
      expect(gateway.operations.last, 'showAndFocus');
    },
  );

  test(
    'off shows hidden window before removing tray; tray open records return',
    () async {
      await reminders.handleTrayAction('open');
      expect(
        await store.setting('lastInteraction'),
        now.toUtc().toIso8601String(),
      );
      gateway.operations.clear();
      await reminders.handleTrayAction('off');
      expect(
        gateway.operations.indexOf('showAndFocus'),
        lessThan(gateway.operations.indexOf('shutdown')),
      );
      expect(await store.setting('reminders'), 'false');
    },
  );

  test(
    'stale notification cannot act on another account or a previous date',
    () async {
      final h = await plantReminder(store);
      await reminders.tick();
      final payload = gateway.requests.single.payloadFor('did');
      await store.switchAccount('account-b');
      await expectLater(reminders.handleAction(payload), throwsStateError);
      expect(await store.habits(), isEmpty);
      await store.switchAccount('account-a');
      await reminders.dispose();
      await reminders.enable();
      now = now.add(const Duration(days: 1));
      await reminders.handleAction(payload);
      expect((await store.habits()).single.practiceCount, 0);
      expect((await store.habits()).single.id, h.id);
      expect(gateway.operations.last, 'showAndFocus');
    },
  );

  test('personalized timing is local opt-in and changes timing without consent or cap changes', () async {
    final h = await plantReminder(store);
    for (var day = 25; day <= 29; day++) {
      await store.checkIn(
        h.id,
        CheckInResult.did,
        now: DateTime(2026, 9, day, 14),
      );
    }
    now = DateTime(2026, 10, 4, 14);
    await reminders.tick();
    expect(gateway.requests, isEmpty);
    await store.setSetting('personalizedTiming', 'true');
    await reminders.tick(now: now.toUtc());
    expect(gateway.requests.single.habitId, h.id);
    expect(gateway.requests.single.body, contains('recent practice timing'));
    await store.setSetting('personalizedTiming', 'false');
    now = DateTime(2026, 10, 4, 18);
    await reminders.tick();
    expect(gateway.requests.where((r) => r.habitId == h.id), hasLength(1));
    expect(await store.setting('analytics'), isNull);
    expect(
      ((await store.syncPayload())['settings'] as List).where(
        (r) => r['key'] == 'personalizedTiming',
      ),
      isEmpty,
    );
    await store.switchAccount('other-timing');
    expect(await store.setting('personalizedTiming'), isNull);
  });

  test(
    'UTC clock inputs reevaluate local quiet hours and local date caps',
    () async {
      final h = await plantReminder(store);
      await reminders.tick(now: DateTime(2026, 10, 4, 22).toUtc());
      expect(gateway.requests, isEmpty);
      await reminders.tick(now: DateTime(2026, 10, 5, 18).toUtc());
      expect(gateway.requests.single.day, '2026-10-05');
      expect(gateway.requests.single.habitId, h.id);
      await reminders.tick(now: DateTime(2026, 10, 5, 19).toUtc());
      expect(gateway.requests, hasLength(1));
    },
  );

  test(
    'only request and explicit observed action telemetry; none delivered',
    () async {
      await store.setSetting('analytics', 'true');
      final h = await plantReminder(store);
      await reminders.tick();
      final request = gateway.requests.single;
      await reminders.handleAction(request.payloadFor('did'));
      await reminders.handleAction(request.payloadFor('did'));
      final events = (await store.syncPayload())['events'] as List;
      final sent = events.singleWhere((r) => r['name'] == 'notif_sent');
      final action = events.singleWhere((r) => r['name'] == 'notif_actioned');
      expect(
        sent['properties']['notificationId'],
        action['properties']['notificationId'],
      );
      expect(sent['properties']['habitId'], h.id);
      expect(
        events.where(
          (r) => [
            'notif_delivered',
            'notif_dismissed',
            'experiment_exposure',
          ].contains(r['name']),
        ),
        isEmpty,
      );
      expect((await store.habits()).single.practiceCount, 1);
      expect(await store.setting('ignored:${h.id}'), '0');
    },
  );

  test(
    'failed plugin request is not counted or telemetered as success',
    () async {
      await store.setSetting('analytics', 'true');
      final h = await plantReminder(store);
      gateway.failShow = true;
      await expectLater(reminders.tick(), throwsStateError);
      expect(await store.setting('ignored:${h.id}'), isNull);
      expect(jsonDecode(await store.setting('reminderLog') ?? '[]'), isEmpty);
      expect(
        ((await store.syncPayload())['events'] as List).where(
          (r) => r['name'] == 'notif_sent',
        ),
        isEmpty,
      );
    },
  );

  test(
    'Fewer callback answers the request without releasing its daily cap',
    () async {
      final h = await plantReminder(store);
      await reminders.tick();
      await reminders.handleAction(gateway.requests.single.payloadFor('fewer'));
      expect(await store.setting('ignored:${h.id}'), '0');
      expect(await store.setting('fewerReminders'), 'true');
      await reminders.tick();
      expect(gateway.requests, hasLength(1));
    },
  );

  test(
    'practice with reminders off never calls an uninitialized plugin',
    () async {
      final h = await plantReminder(store);
      await reminders.disable();
      gateway.operations.clear();
      await reminders.practiced(h.id);
      expect(await store.setting('ignored:${h.id}'), '0');
      expect(gateway.operations, isEmpty);
    },
  );

  test('legacy cap logs survive restart and unattributed callbacks cannot reset absence', () async {
    final h = await plantReminder(store);
    await store.setSetting(
      'reminderLog',
      jsonEncode([
        {'habitId': h.id, 'day': '2026-10-04'},
      ]),
    );
    final interaction = await store.setting('lastInteraction');
    await reminders.dispose();
    await reminders.initialize();
    await reminders.tick();
    expect(gateway.requests, isEmpty);
    await reminders.handleAction('did:${h.id}');
    expect((await store.habits()).single.practiceCount, 0);
    expect(await store.setting('lastInteraction'), interaction);
    expect(gateway.operations.last, 'showAndFocus');
  });

  test('targeted unsent Later respects quiet hours across midnight', () async {
    final h = await plantReminder(store);
    now = DateTime(2026, 10, 4, 20, 45);
    await reminders.snoozeHabit(h.id);
    now = now.add(const Duration(hours: 1));
    await reminders.tick();
    expect(gateway.requests, isEmpty);
    now = DateTime(2026, 10, 5, 7);
    await reminders.tick();
    expect(gateway.requests, isEmpty);
    now = DateTime(2026, 10, 5, 18);
    await reminders.tick();
    expect(gateway.requests.single.habitId, h.id);
  });

  test('manual pause reset never releases the same-day request cap', () async {
    final h = await plantReminder(store);
    await reminders.tick();
    await store.setSetting('ignored:${h.id}', '7');
    await reminders.resumeHabit(h.id);
    await reminders.tick();
    expect(await store.setting('ignored:${h.id}'), '0');
    expect(gateway.requests, hasLength(1));
  });

  test(
    'reservations persist before show and concurrent actions retain all caps',
    () async {
      await store.setSetting('analytics', 'true');
      await plantReminder(store);
      await plantReminder(store);
      final entered = Completer<ReminderRequest>();
      final release = Completer<void>();
      gateway.beforeShow = (request) async {
        if (!entered.isCompleted) {
          entered.complete(request);
          await release.future;
        }
      };
      final ticking = reminders.tick();
      final request = await entered.future;
      expect(
        jsonDecode(await store.setting('reminderLog') ?? '[]'),
        hasLength(1),
      );
      final action = reminders.handleAction(request.payloadFor('did'));
      release.complete();
      await ticking;
      await action;
      final log =
          jsonDecode(await store.setting('reminderLog') ?? '[]') as List;
      expect(log, hasLength(2));
      expect(log.first['handled'], contains('did'));
      await reminders.tick();
      expect(gateway.requests, hasLength(2));
      expect(await store.setting('ignored:${request.habitId}'), '0');
    },
  );

  test(
    'seven actual unanswered requests pause with alternate-day backoff',
    () async {
      final h = await plantReminder(store);
      for (var day = 4; day <= 20; day++) {
        now = DateTime(2026, 10, day, 18);
        await reminders.tick();
      }
      final requests = gateway.requests.where((r) => r.habitId == h.id);
      expect(requests, hasLength(7));
      expect(
        gateway.requests.where((r) => r.habitId == '_reconnect'),
        hasLength(2),
      );
      expect(await store.setting('ignored:${h.id}'), '7');
      expect(requests.map((r) => r.day), [
        '2026-10-04',
        '2026-10-05',
        '2026-10-06',
        '2026-10-08',
        '2026-10-10',
        '2026-10-12',
        '2026-10-14',
      ]);
    },
  );

  test(
    'account switch during plugin request cannot acknowledge new account',
    () async {
      final h = await plantReminder(store);
      gateway.beforeShow = (_) => store.switchAccount('account-b');
      await expectLater(reminders.tick(), throwsStateError);
      expect(await store.setting('reminderLog'), isNull);
      expect(await store.setting('ignored:${h.id}'), isNull);
      expect(
        gateway.operations,
        contains('cancel:${gateway.requests.single.id}'),
      );
      await reminders.tick();
      expect(gateway.requests, hasLength(1));
    },
  );

  test(
    'turning off waits for request then cancels and restores access',
    () async {
      await plantReminder(store);
      final entered = Completer<void>();
      final release = Completer<void>();
      gateway.beforeShow = (_) async {
        entered.complete();
        await release.future;
      };
      final ticking = reminders.tick();
      await entered.future;
      final disabling = reminders.disable();
      release.complete();
      await ticking;
      await disabling;
      expect(reminders.enabled, isFalse);
      expect(gateway.operations, [
        'request',
        'showAndFocus',
        'cancelAll',
        'shutdown',
      ]);
      await reminders.tick();
      expect(gateway.requests, hasLength(1));
    },
  );

  test(
    'actual database reopen retains caps and targeted unsent postponement',
    () async {
      final path =
          'reminder-reopen-${DateTime.now().microsecondsSinceEpoch}.db';
      var disk = await GardenStore.open(path, 'durable');
      final fake = FakeReminderGateway();
      var scheduler = DesktopReminders(
        disk,
        () async {},
        (_) {},
        gateway: fake,
        clock: () => now,
      );
      try {
        await scheduler.enable();
        final a = await plantReminder(disk);
        final b = await plantReminder(disk);
        await scheduler.snoozeHabit(b.id);
        await scheduler.tick();
        expect(fake.requests.single.habitId, a.id);
        await scheduler.dispose();
        await disk.close();
        disk = await GardenStore.open(path, 'durable');
        scheduler = DesktopReminders(
          disk,
          () async {},
          (_) {},
          gateway: fake,
          clock: () => now,
        );
        await scheduler.initialize();
        now = now.add(const Duration(hours: 1));
        await scheduler.tick();
        expect(fake.requests.map((r) => r.habitId), [a.id, b.id]);
      } finally {
        await scheduler.dispose();
        await disk.close();
        await databaseFactoryFfi.deleteDatabase(path);
      }
    },
  );
}
