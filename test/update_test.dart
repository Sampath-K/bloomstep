import 'dart:convert';

import 'package:budlark/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> release(
  String tag, {
  bool preview = false,
  String? url,
}) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': preview,
  'html_url': url ?? 'https://github.com/Sampath-K/budlark/releases/tag/$tag',
};

MockClient releaseClient(Future<http.Response> Function(http.Request) response) =>
    MockClient((request) async {
      if (request.url.path == '/repositories/1404357574') {
        return http.Response(jsonEncode({
          'id': 1404357574,
          'html_url': 'https://github.com/Sampath-K/budlark',
        }), 200);
      }
      expect(request.url.path, '/repositories/1404357574/releases');
      return response(request);
    });

void main() {
  test('unverified repository metadata is never used as an update source', () async {
    for (final metadata in [
      {'id': 42, 'html_url': 'https://github.com/Sampath-K/budlark'},
      {'id': 1404357574, 'html_url': 'https://example.org/redirect'},
      {'id': 1404357574, 'html_url': 'https://github.com/unrelated/project'},
    ]) {
      var calls = 0;
      final service = UpdateService(client: MockClient((_) async {
        calls++;
        return http.Response(jsonEncode(metadata), 200);
      }));
      await expectLater(service.check(), throwsFormatException);
      expect(calls, 1);
    }
  });
  test('repository renames cannot silently break update discovery', () async {
    final paths = <String>[];
    final service = UpdateService(client: MockClient((request) async {
      paths.add(request.url.path);
      return request.url.path == '/repositories/1404357574'
          ? http.Response(jsonEncode({
              'id': 1404357574,
              'html_url': 'https://github.com/Sampath-K/renamed-garden',
            }), 200)
          : http.Response(jsonEncode([
              release('v0.2.0', url: 'https://github.com/Sampath-K/renamed-garden/releases/tag/v0.2.0'),
            ]), 200);
    }));
    final update = await service.check(currentVersion: '0.1.0');
    expect(paths, ['/repositories/1404357574', '/repositories/1404357574/releases']);
    expect(update?.version, '0.2.0');
    expect(update?.releasePage.path, '/Sampath-K/renamed-garden/releases/tag/v0.2.0');
  });
  test(
    'selects newer published versions, respecting the current release channel',
    () async {
      final client = releaseClient(
        (_) async => http.Response(
          jsonEncode([
            release('v0.2.0-preview.1', preview: true),
            release('v0.1.1'),
            release('v0.1.0'),
          ]),
          200,
        ),
      );
      final service = UpdateService(client: client);
      expect((await service.check(currentVersion: '0.1.0'))!.version, '0.1.1');
      expect(
        (await service.check(currentVersion: '0.1.0-preview'))!.version,
        '0.2.0-preview.1',
      );
      expect(await service.check(currentVersion: '0.3.0'), isNull);
    },
  );
  test(
    'rejects errors, malformed versions and off-repository release links',
    () async {
      for (final response in [
        http.Response('Unavailable', 503),
        http.Response(jsonEncode([release('not-a-version')]), 200),
        http.Response(
          jsonEncode([release('v2.0.0', url: 'https://example.org/fake')]),
          200,
        ),
      ]) {
        final service = UpdateService(
          client: releaseClient((_) async => response),
        );
        await expectLater(
          service.check(currentVersion: '0.1.0'),
          throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
        );
      }
    },
  );
}
