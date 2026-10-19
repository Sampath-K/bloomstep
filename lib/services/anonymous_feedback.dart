import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class AnonymousFeedbackReceipt {
  const AnonymousFeedbackReceipt(this.requestId, this.receiptId, this.receivedAt);
  final String requestId;
  final String receiptId;
  final DateTime receivedAt;
}

enum AnonymousFeedbackFailureReason {
  configuration, notQueued, invalidPayload, offline, timeout, rejected, invalidReceipt,
}

/// Safe display category only: never includes raw responses, URLs or exceptions.
class AnonymousFeedbackFailure implements Exception {
  const AnonymousFeedbackFailure(this.reason, {this.httpStatus});
  final AnonymousFeedbackFailureReason reason;
  final int? httpStatus;

  @override
  String toString() => switch (reason) {
    AnonymousFeedbackFailureReason.configuration => 'Feedback API is not configured securely.',
    AnonymousFeedbackFailureReason.notQueued => 'This feedback is no longer queued.',
    AnonymousFeedbackFailureReason.invalidPayload => 'Queued feedback exceeds the submission size limit.',
    AnonymousFeedbackFailureReason.offline => 'Feedback delivery could not connect. Feedback remains queued.',
    AnonymousFeedbackFailureReason.timeout => 'Feedback delivery timed out. Feedback remains queued.',
    AnonymousFeedbackFailureReason.rejected => 'Feedback was not accepted. Feedback remains queued.',
    AnonymousFeedbackFailureReason.invalidReceipt => 'No valid delivery receipt was received. Feedback remains queued.',
  };
}

/// Account-independent opt-in outbox. Pass the configured API origin (including
/// `/api`) and an application-support directory, never an account/habit ID.
class AnonymousFeedback {
  AnonymousFeedback(
    String directory, {
    required this.origin,
    this.client,
    DateTime Function()? clock,
  }) : path = p.join(directory, 'anonymous-feedback.json'),
       _clock = clock ?? DateTime.now;

  final String path;
  final String origin;
  final http.Client? client;
  final DateTime Function() _clock;
  static const maxPending = 10;
  static const retention = Duration(days: 7);
  static const _uuid = Uuid();
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final _queues = <String, Future<void>>{};

  Future<T> _serial<T>(Future<T> Function() action) {
    final key = p.normalize(p.absolute(path));
    final result = (_queues[key] ?? Future<void>.value()).then((_) => action());
    final tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _queues[key] = tail;
    unawaited(tail.then((_) {
      if (identical(_queues[key], tail)) _queues.remove(key);
    }));
    return result;
  }

  static bool _keys(Map value, Set<String> allowed, Set<String> required) =>
      value.keys.every(allowed.contains) && required.every(value.containsKey);

  static bool _validContent(String? text, int? rating) =>
      (text == null ||
          (text.trim().isNotEmpty && text.runes.length <= 2000 &&
              !text.runes.any((rune) => rune >= 0xd800 && rune <= 0xdfff))) &&
      (rating == null || (rating >= 1 && rating <= 5)) &&
      (text != null || rating != null);

  Future<Map<String, dynamic>> _read() async {
    final file = File(path);
    if (!await file.exists()) {
      return {'version': 1, 'deviceId': _uuid.v4(), 'pending': <dynamic>[]};
    }
    if (await file.length() > 100000) {
      throw const FormatException('Feedback outbox is too large.');
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic> ||
        !_keys(value, {'version', 'deviceId', 'pending'}, {'version', 'deviceId', 'pending'}) ||
        value['version'] != 1 ||
        value['deviceId'] is! String ||
        !_uuidPattern.hasMatch(value['deviceId'] as String) ||
        value['pending'] is! List ||
        (value['pending'] as List).length > maxPending) {
      throw const FormatException('Invalid feedback outbox.');
    }
    final pending = value['pending'] as List;
    for (final entry in pending) {
      if (entry is! Map ||
          !_keys(entry, {'requestId', 'queuedAt', 'text', 'rating'}, {'requestId', 'queuedAt'}) ||
          entry['requestId'] is! String ||
          !_uuidPattern.hasMatch(entry['requestId'] as String) ||
          entry['queuedAt'] is! String ||
          DateTime.tryParse(entry['queuedAt'] as String) == null ||
          (entry.containsKey('text') && entry['text'] is! String) ||
          (entry.containsKey('rating') && entry['rating'] is! int) ||
          !_validContent(entry['text'] as String?, entry['rating'] as int?)) {
        throw const FormatException('Invalid feedback outbox entry.');
      }
    }
    final now = _clock().toUtc();
    pending.removeWhere((entry) {
      final queued = DateTime.parse(entry['queuedAt'] as String).toUtc();
      return now.difference(queued) >= retention || queued.isAfter(now);
    });
    return value;
  }

  Future<void> _save(Map<String, dynamic> state) async {
    await File(path).parent.create(recursive: true);
    final staged = File('$path.pending');
    await staged.writeAsString(jsonEncode(state), flush: true);
    await staged.rename(path);
  }

  /// Only call for an explicit user submit, with consent true. Returns an outbox
  /// key, NOT a delivery receipt; UI must say queued until submitNext succeeds.
  Future<String> enqueue({required bool consent, String? text, int? rating}) =>
      _serial(() async {
        if (!consent || !_validContent(text, rating)) {
          throw ArgumentError('Opt-in and feedback text (1–2000 characters) or rating (1–5) required.');
        }
        if (utf8.encode(jsonEncode({
          'consent': true, 'deviceId': _uuid.v4(), 'requestId': _uuid.v4(),
          'text': ?text, 'rating': ?rating,
        })).length > 8192) {
          throw ArgumentError('Encoded feedback exceeds 8192 bytes.');
        }
        final state = await _read();
        final pending = state['pending'] as List;
        if (pending.length >= maxPending) throw StateError('Feedback outbox is full.');
        final key = _uuid.v4();
        pending.add({
          'requestId': key,
          'queuedAt': _clock().toUtc().toIso8601String(),
          'text': ?text,
          'rating': ?rating,
        });
        await _save(state);
        return key;
      });

  Future<int> pendingCount() => _serial(() async {
    final state = await _read();
    await _save(state);
    return (state['pending'] as List).length;
  });

  /// Null means an empty queue only. Failures throw a bounded typed reason;
  /// unexpected/storage errors propagate. Neither acknowledges delivery.
  /// Pass the enqueue key to submit only that explicit opt-in, never an older one.
  Future<AnonymousFeedbackReceipt?> submitNext({String? requestId}) => _serial(() async {
    final state = await _read();
    await _save(state);
    final pending = state['pending'] as List;
    final index = requestId == null ? (pending.isEmpty ? -1 : 0) :
        pending.indexWhere((entry) => entry['requestId'] == requestId);
    if (index < 0) {
      if (requestId != null) {
        throw const AnonymousFeedbackFailure(AnonymousFeedbackFailureReason.notQueued);
      }
      return null;
    }
    final entry = pending[index] as Map;
    final base = Uri.tryParse(origin);
    if (base == null || base.scheme != 'https' || base.host.isEmpty ||
        base.userInfo.isNotEmpty || base.hasQuery || base.hasFragment) {
      throw const AnonymousFeedbackFailure(AnonymousFeedbackFailureReason.configuration);
    }
    final endpoint = base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/feedback/anonymous',
    );
    final transport = client ?? http.Client();
    try {
      final body = jsonEncode({
        'consent': true,
        'deviceId': state['deviceId'],
        'requestId': entry['requestId'],
        if (entry.containsKey('text')) 'text': entry['text'],
        if (entry.containsKey('rating')) 'rating': entry['rating'],
      });
      if (utf8.encode(body).length > 8192) {
        throw const AnonymousFeedbackFailure(AnonymousFeedbackFailureReason.invalidPayload);
      }
      final request = http.Request('POST', endpoint)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = body;
      Future<AnonymousFeedbackReceipt> send() async {
        final response = await transport.send(request);
        if (response.statusCode != 200 && response.statusCode != 201) {
          throw AnonymousFeedbackFailure(AnonymousFeedbackFailureReason.rejected,
            httpStatus: response.statusCode);
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 4096) {
            throw const AnonymousFeedbackFailure(AnonymousFeedbackFailureReason.invalidReceipt);
          }
          bytes.addAll(chunk);
        }
        final dynamic value;
        try {
          value = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          throw const AnonymousFeedbackFailure(AnonymousFeedbackFailureReason.invalidReceipt);
        }
        if (value is! Map ||
            !_keys(value, {'status', 'receiptId', 'receivedAt'}, {'status', 'receiptId', 'receivedAt'}) ||
            value['status'] != 'received' || value['receiptId'] is! String ||
            !_uuidPattern.hasMatch(value['receiptId'] as String) ||
            value['receivedAt'] is! String) {
          throw const AnonymousFeedbackFailure(AnonymousFeedbackFailureReason.invalidReceipt);
        }
        final receivedAt = DateTime.tryParse(value['receivedAt'] as String);
        if (receivedAt == null || !receivedAt.isUtc ||
            receivedAt.isAfter(_clock().toUtc().add(const Duration(minutes: 5))) ||
            receivedAt.isBefore(DateTime.parse(entry['queuedAt'] as String).subtract(const Duration(minutes: 5)))) {
          throw const AnonymousFeedbackFailure(AnonymousFeedbackFailureReason.invalidReceipt);
        }
        return AnonymousFeedbackReceipt(
          entry['requestId'] as String, value['receiptId'] as String, receivedAt,
        );
      }
      final receipt = await send().timeout(const Duration(seconds: 20));
      pending.removeAt(index);
      await _save(state);
      return receipt;
    } on http.ClientException {
      throw const AnonymousFeedbackFailure(AnonymousFeedbackFailureReason.offline);
    } on SocketException {
      throw const AnonymousFeedbackFailure(AnonymousFeedbackFailureReason.offline);
    } on TimeoutException {
      throw const AnonymousFeedbackFailure(AnonymousFeedbackFailureReason.timeout);
    } finally {
      if (client == null) transport.close();
    }
  });

  /// Withdraw queued content locally. Does not promise deletion of submissions
  /// already received by the server; those expire under server retention.
  Future<void> clearPending() => _serial(() async {
    final state = await _read();
    state['pending'] = <dynamic>[];
    await _save(state);
  });
}
