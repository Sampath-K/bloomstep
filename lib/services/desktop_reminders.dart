import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

import '../core/garden_store.dart';
import '../core/models.dart';
import '../core/rules.dart';
import 'remote_config.dart';

class ReminderRequest {
  const ReminderRequest({
    required this.id,
    required this.notificationId,
    required this.account,
    required this.habitId,
    required this.day,
    required this.title,
    required this.body,
    required this.actions,
  });
  final int id;
  final String notificationId, account, habitId, day, title, body;
  final Map<String, String> actions;

  String payloadFor(String action) => jsonEncode({
    'account': account,
    'habitId': habitId,
    'day': day,
    'notificationId': notificationId,
    'action': action,
  });
}

abstract interface class ReminderGateway {
  Future<void> initialize(Future<void> Function(String) action);
  Future<void> show(ReminderRequest request);
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<void> showAndFocus();
  Future<void> shutdown();
}

class WindowsReminderGateway implements ReminderGateway {
  final notifications = FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize(Future<void> Function(String) action) async {
    final initialized = await notifications.initialize(
      settings: const InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: 'Bloomstep',
          appUserModelId: 'Bloomstep.Garden',
          guid: 'dc9b4d34-b0de-4df7-aead-690d8a5304a2',
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final arguments = response.actionId;
        unawaited(
          action(
            arguments != null && arguments.isNotEmpty
                ? arguments
                : response.payload ?? '',
          ),
        );
      },
    );
    if (initialized != true) {
      throw StateError('Windows notifications could not be initialized.');
    }
    await windowManager.ensureInitialized();
  }

  @override
  Future<void> show(ReminderRequest request) => notifications.show(
    id: request.id,
    title: request.title,
    body: request.body,
    payload: request.payloadFor('open'),
    notificationDetails: NotificationDetails(
      windows: WindowsNotificationDetails(
        actions: [
          for (final action in request.actions.entries)
            WindowsAction(
              content: action.value,
              arguments: request.payloadFor(action.key),
            ),
        ],
      ),
    ),
  );

  @override
  Future<void> cancel(int id) => notifications.cancel(id: id);
  @override
  Future<void> cancelAll() => notifications.cancelAll();
  @override
  Future<void> showAndFocus() async {
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  @override
  Future<void> shutdown() async {
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
  }
}

class DesktopReminders with TrayListener, WindowListener {
  DesktopReminders(
    this.store,
    this.changed,
    this.reportError, {
    ReminderGateway? gateway,
    DateTime Function()? clock,
  }) : gateway = gateway ?? WindowsReminderGateway(),
       clock = clock ?? DateTime.now,
       _native = gateway == null {
    _account = store.account;
    _generation = store.syncGeneration;
  }
  final GardenStore store;
  final Future<void> Function() changed;
  final void Function(String) reportError;
  final ReminderGateway gateway;
  final DateTime Function() clock;
  final bool _native;
  String? _account;
  int? _generation;
  Timer? timer;
  bool enabled = false;
  bool ticking = false;
  Future<void> _actions = Future.value();
  RemoteConfig config = RemoteConfig.defaults;
  static const reconnectId = 1;
  static const _uuid = Uuid();

  static int notificationId(String account, String habitId) {
    final hash = sha256.convert(utf8.encode(jsonEncode([account, habitId])));
    final value =
        ((hash.bytes[0] << 24) |
            (hash.bytes[1] << 16) |
            (hash.bytes[2] << 8) |
            hash.bytes[3]) &
        0x7fffffff;
    return value < 2 ? value + 2 : value;
  }

  bool get _sameAccount =>
      _account == store.account && _generation == store.syncGeneration;

  void _requireAccount() {
    if (!_sameAccount) {
      throw StateError('Reminder belongs to a different garden.');
    }
  }

  Future<void> _save(String key, String value) {
    _requireAccount();
    return store.setSetting(key, value);
  }

  Future<void> _track(String name, {Map<String, Object?>? properties}) {
    _requireAccount();
    return store.track(name, properties: properties);
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _actions.then((_) => operation());
    _actions = next.catchError((Object _) {});
    return next;
  }

  Future<void> initialize() async {
    if (_native && !Platform.isWindows) return;
    if (_native) {
      launchAtStartup.setup(
        appName: 'Bloomstep',
        appPath: Platform.resolvedExecutable,
      );
    }
    if (await store.setting('reminders') == 'true') await enable();
  }

  Future<void> enable() async {
    if (enabled) return;
    if (_native && !Platform.isWindows) {
      throw UnsupportedError(
        'This preview supports reminders on Windows only.',
      );
    }
    _account = store.account;
    _generation = store.syncGeneration;
    await gateway.initialize((payload) async {
      try {
        await handleAction(payload);
      } catch (e) {
        reportError('Reminder action failed: $e');
      }
    });
    if (_native) {
      await trayManager.setIcon(
        p.join(
          p.dirname(Platform.resolvedExecutable),
          'data',
          'flutter_assets',
          'windows',
          'runner',
          'resources',
          'app_icon.ico',
        ),
      );
      await trayManager.setToolTip('Bloomstep - a little is enough');
      trayManager.addListener(this);
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
    }
    if (!_sameAccount) {
      throw StateError('Garden changed while enabling reminders.');
    }
    await _save('reminders', 'true');
    enabled = true;
    if (_native) {
      await _menu();
      timer = Timer.periodic(const Duration(seconds: 30), (_) {
        tick().catchError(
          (Object e) => reportError('Reminder request failed: $e'),
        );
      });
    }
  }

  Future<void> disable() async {
    await _stop(showWindow: true, saveOptOut: true);
  }

  Future<void> dispose() async {
    await _stop(showWindow: false, saveOptOut: false);
  }

  Future<void> _stop({
    required bool showWindow,
    required bool saveOptOut,
  }) async {
    timer?.cancel();
    final wasEnabled = enabled;
    enabled = false;
    while (ticking) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (saveOptOut && _sameAccount) {
      await _save('reminders', 'false');
      await _track(
        'notif_disabled',
        properties: {
          'platform': GardenStore.telemetryPlatform,
          'localDay': localDate(clock()),
        },
      );
    }
    if (wasEnabled) {
      // Preserve access to the app before destroying its only hidden-window tray.
      if (showWindow) await gateway.showAndFocus();
      await gateway.cancelAll();
      if (_native) {
        trayManager.removeListener(this);
        windowManager.removeListener(this);
      }
      await gateway.shutdown();
    }
  }

  Future<void> _open() async {
    if (!_sameAccount) {
      throw StateError('Reminder belongs to a different garden.');
    }
    final now = clock();
    final last = DateTime.tryParse(
      await store.setting('lastInteraction') ?? '',
    );
    await gateway.showAndFocus();
    _requireAccount();
    await store.recordInteraction(
      now: now,
      positiveReturn:
          last != null &&
          now.toUtc().difference(last) >= const Duration(days: 3),
    );
    await changed();
  }

  Future<void> handleAction(String payload) =>
      _enqueue(() => _handleAction(payload));

  Future<void> _handleAction(String payload) async {
    if (!enabled) return;
    if (!_sameAccount) {
      throw StateError('Reminder belongs to a different garden.');
    }
    Map<String, dynamic> data;
    try {
      final raw = jsonDecode(payload);
      if (raw is! Map) throw const FormatException();
      data = Map<String, dynamic>.from(raw);
    } on FormatException {
      // Unattributed legacy requests cannot reset another account's absence.
      await gateway.showAndFocus();
      return;
    }
    if (data['account'] != store.account) {
      throw StateError('Reminder belongs to a different garden.');
    }
    final habitId = data['habitId'];
    final action = data['action'];
    final notification = data['notificationId'];
    final log = await _log();
    final matches = log
        .where(
          (r) =>
              r['notificationId'] == notification &&
              r['habitId'] == habitId &&
              r['day'] == data['day'],
        )
        .toList();
    if (matches.isEmpty || habitId is! String || action is! String) return;
    if (habitId != '_reconnect' &&
        !(await store.habits()).any((h) => h.id == habitId)) {
      throw StateError('Reminder belongs to a different garden.');
    }
    final row = matches.single;
    final handled = List<String>.from(row['handled'] as List? ?? []);
    if (handled.contains(action)) return;
    if (!['did', 'rest', 'snooze', 'fewer', 'off', 'open'].contains(action)) {
      return;
    }
    if (habitId == '_reconnect' && ['did', 'rest'].contains(action)) return;
    handled.add(action);
    row['handled'] = handled;
    await _save('reminderLog', jsonEncode(log));
    final properties = <String, Object?>{
      'notificationId': notification,
      'platform': GardenStore.telemetryPlatform,
    };
    if (action == 'open') {
      await _track('notif_opened', properties: properties);
    } else {
      // "Not today" is a real journal action, but not in the action enum.
      await _track(
        'notif_actioned',
        properties: {...properties, if (action != 'rest') 'action': action},
      );
    }
    if (habitId != '_reconnect') {
      await _save('ignored:$habitId', '0');
    }
    if (data['day'] != localDate(clock()) && ['did', 'rest'].contains(action)) {
      await _open();
      return;
    }
    switch (action) {
      case 'did':
      case 'rest':
        _requireAccount();
        await store.checkIn(
          habitId,
          action == 'did' ? CheckInResult.did : CheckInResult.notToday,
          now: clock(),
        );
        await practiced(habitId);
        await changed();
      case 'snooze':
        await snoozeHabit(habitId);
      case 'fewer':
        await _save('fewerReminders', 'true');
      case 'off':
        await disable();
      case 'open':
        if (habitId != '_reconnect') await practiced(habitId);
        await _open();
    }
  }

  Future<List<Map<String, dynamic>>> _log() async =>
      (jsonDecode(await store.setting('reminderLog') ?? '[]') as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

  Future<bool> _postponed(String habitId, DateTime now) async {
    final until = DateTime.tryParse(
      await store.setting('reminderLater:$habitId') ?? '',
    );
    return until != null && now.toUtc().isBefore(until);
  }

  Future<void> tick({DateTime? now}) => _enqueue(() => _tick(now: now));

  Future<void> _tick({DateTime? now}) async {
    if (!enabled || ticking || !_sameAccount) return;
    ticking = true;
    var refresh = false;
    try {
      final date = now ?? clock();
      final day = localDate(date);
      final minute = date.hour * 60 + date.minute;
      final quietStart = int.parse(await store.setting('quietStart') ?? '1290');
      final quietEnd = int.parse(await store.setting('quietEnd') ?? '450');
      final due = int.parse(await store.setting('reminderMinute') ?? '1080');
      final global = DateTime.tryParse(
        await store.setting('snoozeUntil') ?? '',
      );
      if (global != null && date.toUtc().isBefore(global)) return;
      final log = await _log();
      final habits = await store.habits(now: date);
      for (final habit in habits.where(
        (h) => h.status == 'active' && h.today == null,
      )) {
        if (!enabled || !_sameAccount) break;
        if (await _postponed(habit.id, date)) continue;
        final practice = await store.practiceMinutes(habit.id);
        final chosen = ReminderRules.timing(
          practice,
          due,
          quietStart: quietStart,
          quietEnd: quietEnd,
        );
        final ignored = int.parse(
          await store.setting('ignored:${habit.id}') ?? '0',
        );
        if (minute < chosen ||
            !ReminderRules.allowed(
              minute: minute,
              totalToday: log.where((r) => r['day'] == day).length,
              habitToday: log
                  .where((r) => r['day'] == day && r['habitId'] == habit.id)
                  .length,
              ignored: ignored,
              quietStart: quietStart,
              quietEnd: quietEnd,
            )) {
          continue;
        }
        if ((ignored >= 3 || await store.setting('fewerReminders') == 'true') &&
            date.day.isOdd) {
          continue;
        }
        await _request(
          log,
          date,
          habit.id,
          title: config.title(store.account),
          body:
              'Your garden is here whenever you are. Why: ${practice.length >= 5 ? "recent practice timing" : "your chosen check-in time"}, adjusted for quiet hours. Later withdraws this request; no second request today.',
          actions: const {
            'did': 'Did it',
            'rest': 'Not today',
            'snooze': 'Later (no repeat today)',
            'fewer': 'Fewer like this',
            'off': 'Turn off',
          },
        );
        await _save('ignored:${habit.id}', '${ignored + 1}');
        refresh = true;
      }
      final last = DateTime.tryParse(
        await store.setting('lastInteraction') ?? '',
      );
      if (last == null ||
          !enabled ||
          !_sameAccount ||
          habits.isEmpty ||
          await _postponed('_reconnect', date)) {
        return;
      }
      final absence = date.toUtc().difference(last).inDays;
      final sent = int.parse(await store.setting('reconnectCount') ?? '0');
      final chosen = ReminderRules.timing(
        [],
        due,
        quietStart: quietStart,
        quietEnd: quietEnd,
      );
      if (minute < chosen ||
          !reconnectDue(absence, sent) ||
          (await store.setting('fewerReminders') == 'true' && date.day.isOdd) ||
          !ReminderRules.allowed(
            minute: minute,
            totalToday: log.where((r) => r['day'] == day).length,
            habitToday: log
                .where((r) => r['day'] == day && r['habitId'] == '_reconnect')
                .length,
            ignored: 0,
            quietStart: quietStart,
            quietEnd: quietEnd,
          )) {
        return;
      }
      await _request(
        log,
        date,
        '_reconnect',
        title: 'Your garden kept its growth',
        body:
            'Returning is a win. Why: reminders are enabled and no activity was recorded for $absence days. At most two requests per absence. Later withdraws this request; no repeat today.',
        actions: const {
          'open': 'Open garden',
          'snooze': 'Later (no repeat today)',
          'fewer': 'Fewer like this',
          'off': 'Turn off',
        },
      );
      await _save('reconnectCount', '${sent + 1}');
    } finally {
      ticking = false;
      if (refresh && _sameAccount) await changed();
    }
  }

  Future<void> _request(
    List<Map<String, dynamic>> log,
    DateTime date,
    String habitId, {
    required String title,
    required String body,
    required Map<String, String> actions,
  }) async {
    final request = ReminderRequest(
      id: habitId == '_reconnect'
          ? reconnectId
          : notificationId(store.account, habitId),
      notificationId: _uuid.v4(),
      account: store.account,
      habitId: habitId,
      day: localDate(date),
      title: title,
      body: body,
      actions: actions,
    );
    final reservation = <String, dynamic>{
      'habitId': habitId,
      'day': request.day,
      'notificationId': request.notificationId,
      'handled': <String>[],
    };
    log.add(reservation);
    // Retain today's records regardless of clock changes; pruning must not
    // discard caps when a device temporarily travels backwards in time.
    if (log.length > 126) {
      log.removeWhere(
        (r) =>
            (r['day'] as String).compareTo(
              localDate(date.subtract(const Duration(days: 42))),
            ) <
            0,
      );
    }
    // Reserve caps before the plugin call. An interrupted call stays reserved;
    // only a proven failure can release it, preventing duplicate requests.
    await _save('reminderLog', jsonEncode(log));
    try {
      _requireAccount();
      await gateway.show(request);
    } catch (_) {
      if (_sameAccount) {
        log.remove(reservation);
        await _save('reminderLog', jsonEncode(log));
      }
      rethrow;
    }
    if (!_sameAccount) {
      await gateway.cancel(request.id);
      throw StateError('Garden changed during reminder request.');
    }
    await _track(
      'notif_sent',
      properties: {
        'notificationId': request.notificationId,
        if (habitId != '_reconnect') 'habitId': habitId,
        'localDay': request.day,
        'platform': GardenStore.telemetryPlatform,
      },
    );
  }

  Future<void> practiced(String habitId) async {
    await _save('ignored:$habitId', '0');
    if (enabled && _sameAccount) {
      await gateway.cancel(notificationId(store.account, habitId));
    }
  }

  Future<void> resumeHabit(String habitId) async {
    if (!(await store.habits()).any((h) => h.id == habitId)) {
      throw StateError('Recipe belongs to a different garden.');
    }
    await _save('ignored:$habitId', '0');
    await changed();
  }

  /// Before a request, postpone this recipe by one hour. After a request,
  /// withdraw it and wait until the next local day; never erase a daily cap.
  Future<void> snoozeHabit(String habitId) async {
    if (!_sameAccount) {
      throw StateError('Reminder belongs to a different garden.');
    }
    if (habitId != '_reconnect' &&
        !(await store.habits()).any((h) => h.id == habitId)) {
      throw StateError('Recipe belongs to a different garden.');
    }
    final now = clock();
    final sent = (await _log()).any(
      (r) => r['habitId'] == habitId && r['day'] == localDate(now),
    );
    final later = sent
        ? DateTime(now.year, now.month, now.day + 1, now.hour, now.minute)
        : now.add(const Duration(hours: 1));
    await _save('reminderLater:$habitId', later.toUtc().toIso8601String());
    if (enabled && _sameAccount) {
      await gateway.cancel(
        habitId == '_reconnect'
            ? reconnectId
            : notificationId(store.account, habitId),
      );
    }
  }

  Future<void> snooze() => _save(
    'snoozeUntil',
    clock().add(const Duration(hours: 1)).toUtc().toIso8601String(),
  );

  Future<void> _menu() async {
    final habits = await store.habits(now: clock());
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: 'Open your garden'),
          for (final h in habits.where((h) => h.status == 'active').take(3))
            MenuItem(key: 'did:${h.id}', label: 'Did it: ${h.aspiration}'),
          MenuItem.separator(),
          MenuItem(
            key: 'snooze',
            label: 'Quiet for one hour (unsent reminders)',
          ),
          MenuItem(key: 'fewer', label: 'Fewer reminders'),
          MenuItem(key: 'off', label: 'Turn reminders off'),
          MenuItem(key: 'exit', label: 'Exit Bloomstep'),
        ],
      ),
    );
  }

  @override
  void onWindowClose() {
    if (enabled) unawaited(windowManager.hide());
  }

  @override
  void onTrayIconMouseDown() {
    _report(handleTrayAction('open'));
  }

  @override
  void onTrayIconRightMouseDown() {
    _report(_menu().then((_) => trayManager.popUpContextMenu()));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    _report(handleTrayAction(menuItem.key ?? ''));
  }

  void _report(Future<void> action) {
    action.catchError((Object e) => reportError('Tray action failed: $e'));
  }

  Future<void> handleTrayAction(String key) =>
      _enqueue(() => _handleTrayAction(key));

  Future<void> _handleTrayAction(String key) async {
    if (!_sameAccount) throw StateError('Tray belongs to a different garden.');
    if (key.startsWith('did:')) {
      final habitId = key.substring(4);
      await store.checkIn(habitId, CheckInResult.did, now: clock());
      await practiced(habitId);
      await changed();
      await gateway.showAndFocus();
    } else if (key == 'snooze') {
      await snooze();
    } else if (key == 'off') {
      await disable();
    } else if (key == 'fewer') {
      await _save('fewerReminders', 'true');
    } else if (key == 'exit') {
      await dispose();
      if (_native) await windowManager.destroy();
    } else {
      await _open();
    }
  }
}
