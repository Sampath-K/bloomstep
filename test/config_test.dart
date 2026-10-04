import 'package:bloomstep/services/remote_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'remote experiment is disabled by default and bounded at 50 percent',
    () {
      expect(RemoteConfig.defaults.enabled, isFalse);
      final config = RemoteConfig.parse({
        'schemaVersion': 1,
        'version': 2,
        'experiment': {
          'id': 'gentle-reminder-copy-v1',
          'enabled': true,
          'treatmentPercent': 25,
          'control': 'A tiny step is enough',
          'treatment': 'Your next tiny step is here',
        },
      });
      expect(config.title('stable-account'), config.title('stable-account'));
      expect(
        () => RemoteConfig.parse({
          'schemaVersion': 1,
          'version': 2,
          'experiment': {'enabled': true, 'treatmentPercent': 99},
        }),
        throwsFormatException,
      );
      expect(
        () => RemoteConfig.parse({'schemaVersion': 9}),
        throwsFormatException,
      );
    },
  );
}
