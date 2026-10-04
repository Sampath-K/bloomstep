import 'dart:io';

import 'package:bloomstep/services/invitation_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final code = List.filled(43, 'A').join();
  test('concurrent protocol arrivals are serialized with the latest valid intent retained', () async {
    final folder = await Directory.systemTemp.createTemp(
      'bloomstep-invite-race-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final inbox = InvitationInbox(folder.path);
    await Future.wait([
      inbox.save(InvitationIntent(code, 'link')),
      inbox.save(InvitationIntent('${List.filled(42, 'B').join()}A', 'native')),
    ]);
    expect((await inbox.read())!.channel, 'native');
  });
  test(
    'opaque invitation links validate both native and approved web boundaries',
    () {
      final intent = InvitationIntent.parseNative(
        Uri.parse('bloomstep://invite?code=$code&channel=qr'),
      );
      expect(intent.code, code);
      expect(intent.channel, 'qr');
      expect(
        InvitationIntent.parseWeb(
          Uri.parse('https://example.test/?invite=$code&channel=email'),
          Uri.parse('https://example.test'),
        ).channel,
        'email',
      );
      for (final uri in [
        'bloomstep://user@invite?code=$code',
        'bloomstep://invite/path?code=$code',
        'bloomstep://invite?code=$code&code=$code',
        'bloomstep://invite?code=$code&private=secret',
        'bloomstep://invite?code=invalid',
        'bloomstep://invite?code=$code&channel=unknown',
      ]) {
        expect(
          () => InvitationIntent.parseNative(Uri.parse(uri)),
          throwsFormatException,
        );
      }
      expect(
        () => InvitationIntent.parseWeb(
          Uri.parse('https://evil.test/?invite=$code'),
          Uri.parse('https://example.test'),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'intent survives restart and sign-in delay without private identity data',
    () async {
      final folder = await Directory.systemTemp.createTemp('bloomstep-invite-');
      addTearDown(() => folder.delete(recursive: true));
      final now = DateTime.utc(2026, 10, 4);
      final inbox = InvitationInbox(folder.path, now: () => now);
      await inbox.save(InvitationIntent(code, 'link'));
      final restored = InvitationInbox(
        folder.path,
        now: () => now.add(const Duration(days: 1)),
      );
      expect((await restored.read())!.code, code);
      await restored.clear();
      expect(await restored.read(), isNull);
      await inbox.save(InvitationIntent(code, 'link'));
      final expired = InvitationInbox(
        folder.path,
        now: () => now.add(const Duration(days: 7)),
      );
      await expectLater(expired.read(), throwsStateError);
    },
  );
}
