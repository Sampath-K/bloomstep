import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class InvitationIntent {
  InvitationIntent(this.code, this.channel) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(code) ||
        base64Url
                .encode(base64Url.decode(base64Url.normalize(code)))
                .replaceAll('=', '') !=
            code ||
        !channels.contains(channel)) {
      throw const FormatException('The invitation code or channel is invalid.');
    }
  }
  static const channels = {'link', 'email', 'qr', 'native'};
  final String code;
  final String channel;

  static InvitationIntent _query(Uri uri, String key) {
    if (uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.queryParametersAll.keys.any(
          (name) => name != key && name != 'channel',
        ) ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      throw const FormatException(
        'The invitation contains unsupported parameters.',
      );
    }
    return InvitationIntent(
      uri.queryParameters[key] ?? '',
      uri.queryParameters['channel'] ?? 'link',
    );
  }

  static InvitationIntent parseNative(Uri uri) {
    if (uri.scheme != 'bloomstep' ||
        uri.host != 'invite' ||
        uri.hasPort ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'This is not a supported Bloomstep invitation.',
      );
    }
    return _query(uri, 'code');
  }

  static InvitationIntent parseWeb(Uri uri, Uri approvedOrigin) {
    if (uri.scheme != 'https' ||
        uri.origin != approvedOrigin.origin ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'The invitation is not from the approved website.',
      );
    }
    return _query(uri, 'invite');
  }

  Uri get nativeUri => Uri(
    scheme: 'bloomstep',
    host: 'invite',
    queryParameters: {'code': code, 'channel': channel},
  );
}

class InvitationInbox extends ChangeNotifier {
  InvitationInbox(this.directory, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final String directory;
  final DateTime Function() now;
  Future<void> _tail = Future<void>.value();
  String get _path => p.join(directory, 'pending-invitation.json');

  Future<void> _serialize(Future<void> Function() operation) async {
    final previous = _tail;
    final completed = Completer<void>();
    _tail = completed.future;
    try {
      await previous;
      await operation();
    } finally {
      completed.complete();
    }
  }

  Future<void> save(InvitationIntent intent) => _serialize(() async {
    await Directory(directory).create(recursive: true);
    final next = File('$_path.next');
    await next.writeAsString(
      jsonEncode({
        'version': 1,
        'code': intent.code,
        'channel': intent.channel,
        'savedAt': now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await next.rename(_path);
    notifyListeners();
  });

  Future<InvitationIntent?> read() async {
    final file = File(_path);
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic> ||
        value.length != 4 ||
        value['version'] != 1 ||
        value['code'] is! String ||
        value['channel'] is! String ||
        value['savedAt'] is! String) {
      throw const FormatException('The saved invitation is damaged.');
    }
    final age = now().toUtc().difference(
      DateTime.parse(value['savedAt'] as String),
    );
    if (age >= const Duration(days: 7) || age < const Duration(minutes: -5)) {
      await clear();
      throw StateError(
        'The saved invitation expired. Open the original link again.',
      );
    }
    return InvitationIntent(
      value['code'] as String,
      value['channel'] as String,
    );
  }

  Future<void> clear() => _serialize(() async {
    final file = File(_path);
    if (await file.exists()) await file.delete();
    notifyListeners();
  });
}
