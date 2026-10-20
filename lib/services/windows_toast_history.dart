import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class WindowsToastHistory {
  static const _channel = MethodChannel('budlark/toast_history');

  static Future<void> registerApp() => _channel.invokeMethod<void>('registerApp');

  static Future<void> openNotificationSettings({
    Future<bool> Function(Uri uri, LaunchMode mode)? launcher,
  }) async {
    final uri = Uri.parse('ms-settings:notifications');
    final opened = await (launcher != null
        ? launcher(uri, LaunchMode.externalApplication)
        : launchUrl(uri, mode: LaunchMode.externalApplication));
    if (!opened) {
      throw StateError(
        'Windows notification settings could not be opened. '
        'Open Windows Settings > System > Notifications manually.',
      );
    }
  }

  static Future<int> notificationSetting() async {
    final value = await _channel.invokeMethod<Object?>('getSetting');
    if (value is! int || value < 0 || value > 4) {
      throw const FormatException(
        'Windows returned invalid notification settings.',
      );
    }
    return value;
  }

  static Future<void> requireEnabled() async {
    final setting = await notificationSetting();
    if (setting == 0) return;
    throw StateError(switch (setting) {
      1 => 'Notifications are disabled for Budlark. Reminders remain inactive. '
          'Open Windows Settings > System > Notifications and review Budlark.',
      2 => 'Notifications are disabled for this Windows user. Reminders remain '
          'inactive. Open Windows Settings > System > Notifications.',
      3 => 'Windows notifications are blocked by device policy. Reminders remain '
          'inactive; contact your device administrator.',
      _ => 'Windows rejected the Budlark notification registration. Reminders '
          'remain inactive. Repair or reinstall Budlark, then retry.',
    });
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
    required Map<String, String> actions,
  }) async {
    _validateId(id);
    if (title.length > 160 ||
        body.length > 1000 ||
        payload.length > 1500 ||
        actions.length > 5 ||
        actions.entries.any(
          (entry) =>
              entry.key.isEmpty ||
              entry.key.length > 120 ||
              entry.value.length > 1500,
        )) {
      throw const FormatException('The notification exceeds safe limits.');
    }
    await requireEnabled();
    const escape = HtmlEscape(HtmlEscapeMode.attribute);
    final xml =
        '<toast launch="${escape.convert(payload)}">'
        '<visual><binding template="ToastGeneric">'
        '<text>${escape.convert(title)}</text><text>${escape.convert(body)}</text>'
        '</binding></visual><actions>'
        '${actions.entries.map((entry) => '<action content="${escape.convert(entry.key)}" arguments="${escape.convert(entry.value)}" activationType="foreground"/>').join()}'
        '</actions></toast>';
    await _channel.invokeMethod<void>('show', {'id': id, 'xml': xml});
  }

  static Future<List<String>> activeTags() async {
    final raw = await _channel.invokeMethod<Object?>('getHistory');
    if (raw is! List ||
        raw.any((tag) => tag is! String || tag.isEmpty || tag.length > 16)) {
      throw const FormatException(
        'Windows returned invalid notification tags.',
      );
    }
    return raw.cast<String>();
  }

  static Future<void> cancel(int id) async {
    _validateId(id);
    await _channel.invokeMethod<void>('cancel', {'id': id});
  }

  static void _validateId(int id) {
    if (id < 1 || id > 0x7fffffff) {
      throw RangeError.range(id, 1, 0x7fffffff, 'id');
    }
  }
}
