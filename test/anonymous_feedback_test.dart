import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:budlark/services/anonymous_feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory('test/.anonymous-feedback-test').create(recursive: true);
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  AnonymousFeedback service(http.Client client, {String origin = 'https://approved.example/api'}) =>
      AnonymousFeedback(directory.path, origin: origin, client: client);

  test('opt-in and bounded exact payload, with random anonymous identifiers and no credentials', () async {
    final api = service(MockClient((request) async {
      expect(request.url.toString(), 'https://approved.example/api/feedback/anonymous');
      expect(request.headers.keys.any((k) => k.toLowerCase().contains('authorization')), false);
      final body = jsonDecode(request.body) as Map;
      expect(body.keys.toSet(), {'consent', 'deviceId', 'requestId', 'text', 'rating'});
      expect(body['deviceId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      return http.Response(jsonEncode({
        'status': 'received', 'receiptId': 'a34cbcd0-93cc-4ae7-84d1-540bef923ec1',
        'receivedAt': DateTime.now().toUtc().toIso8601String(),
      }), 201);
    }));
    await expectLater(api.enqueue(consent: false, text: 'No'), throwsArgumentError);
    await expectLater(api.enqueue(consent: true), throwsArgumentError);
    await expectLater(api.enqueue(consent: true, text: 'x' * 2001), throwsArgumentError);
    await expectLater(api.enqueue(consent: true, text: '\u0001' * 2000), throwsArgumentError);
    await expectLater(api.enqueue(consent: true, rating: 6), throwsArgumentError);
    final key = await api.enqueue(consent: true, text: 'Calmer', rating: 5);
    final receipt = await api.submitNext();
    expect(receipt?.requestId, key);
    expect(receipt?.receiptId, 'a34cbcd0-93cc-4ae7-84d1-540bef923ec1');
    expect(await api.pendingCount(), 0);
  });

  test('offline and invalid receipt stay durably queued across restart with same idempotency key', () async {
    var mode = 0;
    final keys = <String>[];
    final client = MockClient((request) async {
      keys.add((jsonDecode(request.body) as Map)['requestId'] as String);
      if (mode == 0) throw http.ClientException('private');
      if (mode == 1) return http.Response('{}', 200);
      if (mode == 2) return http.Response('{"status":"received","receiptId":"fake","receivedAt":"today"}', 201);
      return http.Response(jsonEncode({
        'status': 'received', 'receiptId': 'a34cbcd0-93cc-4ae7-84d1-540bef923ec1',
        'receivedAt': DateTime.now().toUtc().toIso8601String(),
      }), 200);
    });
    final key = await service(client).enqueue(consent: true, rating: 4);
    for (mode = 0; mode < 3; mode++) {
      await expectLater(service(client).submitNext(), throwsA(
        isA<AnonymousFeedbackFailure>().having((e) => e.reason, 'reason',
          mode == 0 ? AnonymousFeedbackFailureReason.offline : AnonymousFeedbackFailureReason.invalidReceipt),
      ));
      expect(await service(client).pendingCount(), 1);
    }
    expect((await service(client).submitNext())?.requestId, key);
    expect(keys.toSet(), {key});
  });

  test('non-HTTPS and redirects do not send or acknowledge; local queue is bounded', () async {
    var calls = 0;
    final client = MockClient((_) async { calls++; return http.Response('{}', 302); });
    final api = service(client, origin: 'http://localhost/api');
    for (var i = 0; i < 10; i++) {
      await api.enqueue(consent: true, rating: 3);
    }
    await expectLater(api.enqueue(consent: true, rating: 3), throwsStateError);
    await expectLater(api.submitNext(), throwsA(isA<AnonymousFeedbackFailure>()
      .having((e) => e.reason, 'reason', AnonymousFeedbackFailureReason.configuration)));
    expect(calls, 0);
    await expectLater(service(client).submitNext(), throwsA(isA<AnonymousFeedbackFailure>()
      .having((e) => e.reason, 'reason', AnonymousFeedbackFailureReason.rejected)
      .having((e) => e.httpStatus, 'httpStatus', 302)));
    expect(await api.pendingCount(), 10);
  });

  test('explicit request ID routes only that opt-in, missing ID never sends another entry', () async {
    final sent = <String>[];
    final api = service(MockClient((request) async {
      sent.add((jsonDecode(request.body) as Map)['requestId'] as String);
      return http.Response(jsonEncode({
        'status': 'received', 'receiptId': 'a34cbcd0-93cc-4ae7-84d1-540bef923ec1',
        'receivedAt': DateTime.now().toUtc().toIso8601String(),
      }), 201);
    }));
    final older = await api.enqueue(consent: true, text: 'Older');
    final newest = await api.enqueue(consent: true, text: 'Newest');
    expect((await api.submitNext(requestId: newest))?.requestId, newest);
    expect(sent, [newest]);
    expect(await api.pendingCount(), 1);
    await expectLater(api.submitNext(requestId: newest), throwsA(
      isA<AnonymousFeedbackFailure>().having((e) => e.reason, 'reason', AnonymousFeedbackFailureReason.notQueued)));
    expect(sent, [newest]);
    expect((await api.submitNext())?.requestId, older);
    expect(await api.submitNext(), null);
    await expectLater(api.submitNext(requestId: older), throwsA(isA<AnonymousFeedbackFailure>()));
  });

  test('bounded failure reasons preserve queued content and never expose response details', () async {
    var mode = 0;
    final api = service(MockClient((_) async {
      if (mode == 0) return http.Response('private backend detail', 429);
      if (mode == 1) return http.Response('{private invalid json', 201);
      if (mode == 2) return http.Response('x' * 4097, 200);
      if (mode == 3) throw TimeoutException('private timeout');
      throw StateError('unexpected programming failure');
    }));
    await api.enqueue(consent: true, rating: 5);
    for (mode = 0; mode < 4; mode++) {
      await expectLater(api.submitNext(), throwsA(isA<AnonymousFeedbackFailure>()
        .having((e) => e.reason, 'reason', [
          AnonymousFeedbackFailureReason.rejected,
          AnonymousFeedbackFailureReason.invalidReceipt,
          AnonymousFeedbackFailureReason.invalidReceipt,
          AnonymousFeedbackFailureReason.timeout,
        ][mode]).having((e) => e.toString(), 'safe text', isNot(contains('private')))));
      expect(await api.pendingCount(), 1);
    }
    await expectLater(api.submitNext(), throwsStateError);
    expect(await api.pendingCount(), 1);
  });

  test('local retention removes expired content, keeps installation ID and supports withdrawal', () async {
    var now = DateTime.utc(2026, 10, 19);
    final api = AnonymousFeedback(directory.path,
      origin: 'https://approved.example/api', clock: () => now,
    );
    final expiredKey = await api.enqueue(consent: true, text: 'Private local draft');
    final before = jsonDecode(await File(api.path).readAsString()) as Map;
    now = now.add(const Duration(days: 7));
    await expectLater(api.submitNext(requestId: expiredKey), throwsA(
      isA<AnonymousFeedbackFailure>().having((e) => e.reason, 'reason', AnonymousFeedbackFailureReason.notQueued)));
    expect(await api.pendingCount(), 0);
    final after = jsonDecode(await File(api.path).readAsString()) as Map;
    expect(after['deviceId'], before['deviceId']);
    expect(await File(api.path).readAsString(), isNot(contains('Private local draft')));
    await api.enqueue(consent: true, rating: 4);
    await api.clearPending();
    expect(await api.pendingCount(), 0);
  });
}
