import 'package:bloomstep/services/native_share.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bloomstep/native_share');
  test(
    'native share opens the OS surface without claiming a completed send',
    () async {
      MethodCall? request;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            request = call;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await NativeShare.share(
        Uri.parse('https://example.test/?invite=synthetic'),
      );
      expect(request!.method, 'share');
      expect((request!.arguments as Map)['title'], 'A little is enough');
      expect((request!.arguments as Map).containsKey('habit'), isFalse);
    },
  );
  test('unsafe share URI is rejected before invoking the OS', () async {
    for (final value in [
      'file:///private',
      'http://example.test',
      'https://user@example.test',
    ]) {
      await expectLater(
        NativeShare.share(Uri.parse(value)),
        throwsFormatException,
      );
    }
  });
  test('OS errors remain visible to the caller', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'share_unavailable'),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await expectLater(
      NativeShare.share(Uri.parse('https://example.test')),
      throwsA(isA<PlatformException>()),
    );
  });
}
