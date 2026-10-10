import 'dart:async';
import 'dart:io';

import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:bloomstep/services/analytics_sandbox.dart';
import 'package:flutter_test/flutter_test.dart';

class _Headers implements HttpHeaders {
  final values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => const Stream<List<int>>.empty().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = false;
  Object? body;
  @override
  void write(Object? value) {
    body = value;
  }

  @override
  Future<HttpClientResponse> close() async => _Response();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  final endpoints = <Uri>[];
  final requests = <_Request>[];
  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    endpoints.add(url);
    final request = _Request();
    requests.add(request);
    return request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Overrides extends HttpOverrides {
  _Overrides(this.client);
  final _Client client;
  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'actual Aptabase SDK initializes and drains only a consented queue to EU',
    () async {
      final client = _Client();
      final previous = HttpOverrides.current;
      HttpOverrides.global = _Overrides(client);
      var allowed = false;
      final queue = ConsentMemoryQueue(() async => allowed);
      try {
        await queue.addEvent(
          'before',
          '{"eventName":"sandbox_session_started"}',
        );
        expect(await queue.getItems(25), isEmpty);
        expect(client.endpoints, isEmpty);
        allowed = true;
        await queue.addEvent(
          'consented',
          '{"eventName":"sandbox_session_started"}',
        );
        await Aptabase.init('A-EU-1234567890', const InitOptions(), queue);
        expect(
          client.endpoints.single.toString(),
          'https://eu.aptabase.com/api/v0/events',
        );
        expect(
          client.requests.single.headers.values['App-Key'],
          'A-EU-1234567890',
        );
        expect(client.requests.single.body, [
          '{"eventName":"sandbox_session_started"}',
        ]);
        allowed = false;
        await queue.addEvent(
          'after',
          '{"eventName":"sandbox_session_started"}',
        );
        expect(await queue.getItems(25), isEmpty);
        expect(client.endpoints, hasLength(1));
      } finally {
        allowed = false;
        queue.clear();
        HttpOverrides.global = previous;
      }
    },
  );
}
