import 'dart:convert';

import 'package:bloomstep/services/update_service.dart';
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
  'html_url': url ?? 'https://github.com/Sampath-K/bloomstep/releases/tag/$tag',
};

void main() {
  test(
    'selects newer published versions, respecting the current release channel',
    () async {
      final client = MockClient(
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
          client: MockClient((_) async => response),
        );
        await expectLater(
          service.check(currentVersion: '0.1.0'),
          throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
        );
      }
    },
  );
}
