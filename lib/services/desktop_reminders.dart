import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/garden_store.dart';
import '../core/models.dart';
import '../core/rules.dart';

class DesktopReminders with TrayListener, WindowListener {
  DesktopReminders(this.store, this.changed, this.reportError);
  final GardenStore store;
  final Future<void> Function() changed;
  final void Function(String) reportError;
  final notifications = FlutterLocalNotificationsPlugin();
  Timer? timer;
  bool enabled = false;
  bool ticking = false;

  Future<void> initialize() async {
    if (!Platform.isWindows) return;
    launchAtStartup.setup(
      appName: 'Bloomstep',
      appPath: Platform.resolvedExecutable,
    );
    enabled = await store.setting('reminders') == 'true';
    if (enabled) await enable();
  }

  Future<void> enable() async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'This preview supports reminders on Windows only.',
      );
    }
    final initialized = await notifications.initialize(
      settings: const InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: 'Bloomstep',
          appUserModelId: 'Bloomstep.Garden',
          guid: 'dc9b4d34-b0de-4df7-aead-690d8a5304a2',
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        _handleNotification(response).catchError(
          (Object error) => reportError('Reminder action failed: $error'),
        );
      },
    );
    if (initialized != true) {
      throw StateError('Windows notifications could not be initialized.');
    }
    await windowManager.ensureInitialized();
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
    await store.setSetting('reminders', 'true');
    enabled = true;
    await _menu();
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      tick().catchError(
        (Object error) => reportError('Reminder delivery failed: $error'),
      );
    });
  }

  Future<void> disable() async {
    timer?.cancel();
    enabled = false;
    await store.setSetting('reminders', 'false');
    if (Platform.isWindows) {
      await notifications.cancelAll();
      await windowManager.setPreventClose(false);
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      await trayManager.destroy();
    }
  }

  Future<void> dispose() async {
    timer?.cancel();
    if (enabled && Platform.isWindows) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      await trayManager.destroy();
      await windowManager.setPreventClose(false);
    }
  }

  Future<void> _handleNotification(NotificationResponse response) async {
    if (!enabled) return;
    final parts = (response.payload ?? '').split(':');
    if (parts.length != 2) {
      await windowManager.show();
      return;
    }
    final habitId = parts[0];
    if (!(await store.habits()).any((h) => h.id == habitId)) {
      throw StateError('Notification belongs to a different garden.');
    }
    switch (parts[1]) {
      case 'did':
        await store.checkIn(habitId, CheckInResult.did);
        await practiced(habitId);
        await changed();
      case 'rest':
        await store.checkIn(habitId, CheckInResult.notToday);
        await practiced(habitId);
        await changed();
      case 'snooze':
        await snooze();
      case 'fewer':
        await store.setSetting('fewerReminders', 'true');
      case 'off':
        await disable();
      default:
        await windowManager.show();
    }
  }

  Future<void> tick({DateTime? now}) async {
    if (!enabled || ticking) return;
    ticking = true;
    try {
      final date = now ?? DateTime.now();
      final day = localDate(date);
      final minute = date.hour * 60 + date.minute;
      final quietStart = int.parse(await store.setting('quietStart') ?? '1290');
      final quietEnd = int.parse(await store.setting('quietEnd') ?? '450');
      final due = int.parse(await store.setting('reminderMinute') ?? '1080');
      if (minute < due) return;
      final snooze = await store.setting('snoozeUntil');
      if (snooze != null && date.isBefore(DateTime.parse(snooze))) return;
      final raw = await store.setting('reminderLog') ?? '[]';
      final log = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final habits = await store.habits(now: date);
      for (final habit in habits.where(
        (h) => h.status == 'active' && h.today == null,
      )) {
        final prior = log.where((e) => e['habitId'] == habit.id).toList();
        final ignored = int.parse(
          await store.setting('ignored:${habit.id}') ?? '0',
        );
        if (!ReminderRules.allowed(
          minute: minute,
          totalToday: log.where((e) => e['day'] == day).length,
          habitToday: prior.where((e) => e['day'] == day).length,
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
        final id = experimentBucket(habit.id) + 100;
        await notifications.show(
          id: id,
          title: 'A tiny step is enough',
          body: 'Your garden is here whenever you are. Open Bloomstep to celebrate or rest. Why: your chosen check-in time.',
          payload: '${habit.id}:open',
          notificationDetails: NotificationDetails(
            windows: WindowsNotificationDetails(
              actions: [
                WindowsAction(content: 'Did it', arguments: '${habit.id}:did'),
                WindowsAction(
                  content: 'Not today',
                  arguments: '${habit.id}:rest',
                ),
                WindowsAction(
                  content: 'Later',
                  arguments: '${habit.id}:snooze',
                ),
                WindowsAction(
                  content: 'Fewer like this',
                  arguments: '${habit.id}:fewer',
                ),
                WindowsAction(
                  content: 'Turn off',
                  arguments: '${habit.id}:off',
                ),
              ],
            ),
          ),
        );
        log.add({'habitId': habit.id, 'day': day});
        await store.setSetting('ignored:${habit.id}', '${ignored + 1}');
        await store.track('reminder_sent');
        if (log.length > 42) log.removeRange(0, log.length - 42);
        await store.setSetting('reminderLog', jsonEncode(log));
      }
    } finally {
      ticking = false;
    }
  }

  Future<void> practiced(String habitId) async =>
      store.setSetting('ignored:$habitId', '0');

  Future<void> snooze() => store.setSetting(
    'snoozeUntil',
    DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
  );

  Future<void> _menu() async {
    final habits = await store.habits();
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: 'Open your garden'),
          for (final habit in habits.where((h) => h.status == 'active').take(3))
            MenuItem(
              key: 'did:${habit.id}',
              label: 'Did it: ${habit.aspiration}',
            ),
          MenuItem.separator(),
          MenuItem(key: 'snooze', label: 'Quiet for one hour'),
          MenuItem(key: 'fewer', label: 'Fewer reminders'),
          MenuItem(key: 'off', label: 'Turn reminders off'),
          MenuItem(key: 'exit', label: 'Exit Bloomstep'),
        ],
      ),
    );
  }

  @override
  void onWindowClose() {
    if (enabled) windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    _menu()
        .then((_) => trayManager.popUpContextMenu())
        .catchError((Object error) => reportError('Tray menu failed: $error'));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    _trayAction(
      menuItem.key ?? '',
    ).catchError((Object error) => reportError('Tray action failed: $error'));
  }

  Future<void> _trayAction(String key) async {
    if (key.startsWith('did:')) {
      await store.checkIn(key.substring(4), CheckInResult.did);
      await practiced(key.substring(4));
      await changed();
      await windowManager.show();
    } else if (key == 'snooze') {
      await snooze();
    } else if (key == 'off') {
      await disable();
    } else if (key == 'fewer') {
      await store.setSetting('fewerReminders', 'true');
    } else if (key == 'exit') {
      await dispose();
      await windowManager.destroy();
    } else {
      await windowManager.show();
    }
  }
}
