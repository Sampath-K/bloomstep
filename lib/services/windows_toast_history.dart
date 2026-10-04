import 'dart:convert';

import 'package:flutter/services.dart';

class WindowsToastHistory {
  static const _channel = MethodChannel('bloomstep/toast_history');

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
    throw StateError(
      setting == 3
          ? 'Windows notifications are blocked by device policy. Reminders remain off; contact your device administrator.'
          : 'Windows notifications are disabled (setting $setting). Reminders cannot be requested. Review Windows Settings > System > Notifications.',
    );
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
