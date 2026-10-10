import 'dart:async';
import 'dart:typed_data';

import 'package:bloomstep/services/microsoft_photo.dart';
import 'package:bloomstep/services/microsoft_photo_auth.dart';
import 'package:bloomstep/services/identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

const proof = MicrosoftPhotoIdentity(
  bloomstepAccount: 'garden-a',
  tenantId: MicrosoftPhotoIdentity.consumerTenant,
  objectId: '00000000-0000-0000-0000-000000000001',
);

class FakeSession implements MicrosoftPhotoSession {
  FakeSession({this.objectId = '00000000-0000-0000-0000-000000000001'});
  @override
  final String objectId;
  @override
  String get tenantId => proof.tenantId;
  Completer<String>? pendingToken;
  bool disposed = false;
  @override
  Future<String> accessToken() async =>
      await pendingToken?.future ?? 'graph-only';
  @override
  void close() => disposed = true;
}

void main() {
  test(
    'OIDC token bodies cannot reach an enabled root diagnostic listener',
    () {
      final oldRoot = Logger.root.level;
      final oldHierarchy = hierarchicalLoggingEnabled;
      final oldLevel = Logger('openid_client').level;
      addTearDown(() {
        Logger('openid_client').level = oldLevel;
        Logger.root.level = oldRoot;
        hierarchicalLoggingEnabled = oldHierarchy;
      });
      Logger.root.level = Level.ALL;
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      MicrosoftPhotoAuthenticator.suppressOidcResponseLogging();
      Logger('openid_client').fine('synthetic-token-response');
      expect(records, isEmpty);
    },
  );

  test('current CIAM identity has no supported MSA linkage projection', () {
    expect(IdentityService().microsoftPhotoIdentity, isNull);
  });

  test(
    'callback rejects duplicate values, wrong state/path and token delivery',
    () {
      bool valid(String uri, {String method = 'GET'}) =>
          MicrosoftPhotoAuthenticator.validCallback(
            method,
            Uri.parse(uri),
            'expected',
          );
      expect(valid('/photo-callback?state=expected&code=one'), isTrue);
      expect(
        valid('/photo-callback?state=expected&error=access_denied'),
        isTrue,
      );
      for (final uri in [
        '/callback?state=expected&code=one',
        '/photo-callback?state=wrong&code=one',
        '/photo-callback?state=expected&state=expected&code=one',
        '/photo-callback?state=expected&code=one&code=two',
        '/photo-callback?state=expected&code=one&error=access_denied',
        '/photo-callback?state=expected&access_token=not-accepted',
        '/photo-callback?state=expected&code=one&access_token=not-accepted',
        '/photo-callback?state=expected&code=one#access_token=not-accepted',
      ]) {
        expect(valid(uri), isFalse);
      }
      expect(
        valid('/photo-callback?state=expected&code=one', method: 'POST'),
        isFalse,
      );
    },
  );

  test(
    'OIDC transport refuses other hosts, HTTP, ports and redirects',
    () async {
      var requests = 0;
      final client = MicrosoftPhotoAuthClient(
        MockClient((request) async {
          requests++;
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://other.invalid'},
          );
        }),
      );
      for (final uri in [
        'https://other.invalid/token',
        'http://login.microsoftonline.com/token',
        'https://login.microsoftonline.com:444/token',
        'https://user@login.microsoftonline.com/token',
      ]) {
        await expectLater(
          client.get(Uri.parse(uri)),
          throwsA(isA<MicrosoftPhotoFailure>()),
        );
      }
      expect(requests, 0);
      await expectLater(
        client.get(MicrosoftPhotoAuthenticator.issuerUri),
        throwsA(isA<MicrosoftPhotoFailure>()),
      );
      expect(requests, 1);
      client.close();
    },
  );

  test('no immutable proof means no browser and no Graph call', () async {
    var calls = 0;
    final connection = MicrosoftPhotoConnection(
      authenticate: (_) async {
        calls++;
        return FakeSession();
      },
      client: MockClient((_) async {
        calls++;
        return http.Response('', 200);
      }),
    );
    expect(await connection.connect(null), MicrosoftPhotoStatus.unlinked);
    expect(calls, 0);
    expect(connection.bytesFor('garden-a'), isNull);
  });

  test(
    'a different MSA is refused before its token or photo is read',
    () async {
      final session = FakeSession(objectId: 'another-object');
      final connection = MicrosoftPhotoConnection(
        authenticate: (_) async => session,
        client: MockClient((_) async => throw StateError('must not fetch')),
      );
      expect(await connection.connect(proof), MicrosoftPhotoStatus.mismatch);
      expect(session.disposed, isTrue);
      expect(connection.bytesFor('garden-a'), isNull);
    },
  );

  test(
    'photo is memory-only, account-scoped, and cleared on sign-out',
    () async {
      final session = FakeSession();
      final connection = MicrosoftPhotoConnection(
        authenticate: (_) async => session,
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://graph.microsoft.com/v1.0/me/photo/\$value',
          );
          expect(request.headers['authorization'], 'Bearer graph-only');
          expect(request.followRedirects, isFalse);
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      expect(await connection.connect(proof), MicrosoftPhotoStatus.loaded);
      expect(connection.bytesFor('garden-b'), isNull);
      final bytes = connection.bytesFor('garden-a')!;
      expect(bytes, [1, 2, 3]);
      bytes[0] = 9;
      expect(connection.bytesFor('garden-a'), [1, 2, 3]);
      connection.clear();
      expect(connection.bytesFor('garden-a'), isNull);
      expect(session.disposed, isTrue);
    },
  );

  test(
    'sign-out during authentication cannot repopulate the connection',
    () async {
      final pending = Completer<MicrosoftPhotoSession>();
      final session = FakeSession();
      final connection = MicrosoftPhotoConnection(
        authenticate: (_) => pending.future,
        client: MockClient((_) async => throw StateError('must not fetch')),
      );
      final result = connection.connect(proof);
      connection.clear();
      pending.complete(session);
      expect(await result, MicrosoftPhotoStatus.cancelled);
      expect(session.disposed, isTrue);
    },
  );

  test(
    'sign-out during token refresh or photo fetch discards late data',
    () async {
      for (final duringToken in [true, false]) {
        final token = Completer<String>();
        final response = Completer<http.Response>();
        final started = Completer<void>();
        final session = FakeSession()
          ..pendingToken = duringToken ? token : null;
        final connection = MicrosoftPhotoConnection(
          authenticate: (_) async => session,
          client: MockClient((_) {
            started.complete();
            return response.future;
          }),
        );
        final loading = connection.connect(proof);
        if (duringToken) {
          await Future<void>.delayed(Duration.zero);
        } else {
          await started.future;
        }
        connection.clear();
        token.complete('late-token');
        response.complete(
          http.Response.bytes([1], 200, headers: {'content-type': 'image/png'}),
        );
        expect(await loading, MicrosoftPhotoStatus.cancelled);
        expect(connection.bytesFor('garden-a'), isNull);
      }
    },
  );

  test(
    'a late older connection cannot overwrite a newer account photo',
    () async {
      final old = Completer<MicrosoftPhotoSession>();
      var attempts = 0;
      final connection = MicrosoftPhotoConnection(
        authenticate: (_) async =>
            attempts++ == 0 ? await old.future : FakeSession(),
        client: MockClient(
          (_) async => http.Response.bytes(
            [2],
            200,
            headers: {'content-type': 'image/png'},
          ),
        ),
      );
      final older = connection.connect(proof);
      expect(await connection.connect(proof), MicrosoftPhotoStatus.loaded);
      final discarded = FakeSession();
      old.complete(discarded);
      expect(await older, MicrosoftPhotoStatus.cancelled);
      expect(discarded.disposed, isTrue);
      expect(connection.bytesFor('garden-a'), [2]);
      connection.clear();
    },
  );

  testWidgets('download total deadline does not wait forever for headers', (
    tester,
  ) async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final connection = MicrosoftPhotoConnection(
      authenticate: (_) async => FakeSession(),
      client: MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
    final result = connection.connect(proof);
    await tester.pump();
    expect(started.isCompleted, isTrue);
    await tester.pump(const Duration(seconds: 16));
    expect(await result, MicrosoftPhotoStatus.unavailable);
    response.complete(
      http.Response.bytes([1], 200, headers: {'content-type': 'image/png'}),
    );
    await tester.pump();
    expect(connection.bytesFor('garden-a'), isNull);
  });

  test(
    'redirect, missing photo, bad content and oversized photo fall back',
    () async {
      for (final response in [
        http.Response(
          '',
          302,
          headers: {'location': 'https://elsewhere.invalid'},
        ),
        http.Response('', 404),
        http.Response('not an image', 200),
        http.Response.bytes(
          Uint8List(MicrosoftPhotoConnection.maxBytes + 1),
          200,
          headers: {'content-type': 'image/png'},
        ),
      ]) {
        final connection = MicrosoftPhotoConnection(
          authenticate: (_) async => FakeSession(),
          client: MockClient((_) async => response),
        );
        expect(
          await connection.connect(proof),
          MicrosoftPhotoStatus.unavailable,
        );
        expect(connection.bytesFor('garden-a'), isNull);
      }
    },
  );

  test(
    'declined consent uses a privacy-safe status, not provider errors',
    () async {
      final connection = MicrosoftPhotoConnection(
        authenticate: (_) async => throw const MicrosoftPhotoFailure(),
        client: MockClient((_) async => throw StateError('must not fetch')),
      );
      expect(await connection.connect(proof), MicrosoftPhotoStatus.unavailable);
    },
  );
}
