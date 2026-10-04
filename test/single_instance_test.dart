import 'dart:convert';
import 'dart:io';

import 'package:bloomstep/services/single_instance.dart';
import 'package:bloomstep/services/invitation_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'second launch forwards only a validated opaque invitation to the owner',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'bloomstep-instance-invite-',
      );
      addTearDown(() => folder.delete(recursive: true));
      InvitationIntent? received;
      final first = SingleInstance(
        folder.path,
        () async {},
        (_) {},
        onInvitation: (intent) async {
          received = intent;
        },
      );
      final second = SingleInstance(folder.path, () async {}, (_) {});
      addTearDown(first.close);
      addTearDown(second.close);
      await first.start();
      final code = List.filled(43, 'A').join();
      expect(
        await second.start(invitation: InvitationIntent(code, 'qr')),
        isFalse,
      );
      expect(received!.code, code);
      expect(received!.channel, 'qr');
    },
    skip: !Platform.isWindows,
  );
  test(
    'damaged descriptor cannot strand the owner lock during shutdown',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'bloomstep-instance-close-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final errors = <String>[];
      final owner = SingleInstance(folder.path, () async {}, errors.add);
      addTearDown(owner.close);
      expect(await owner.start(), isTrue);
      await File('${folder.path}${Platform.pathSeparator}instance.json')
          .writeAsString('{');
      await owner.close();
      expect(errors, isNotEmpty);
      final replacement = SingleInstance(folder.path, () async {}, errors.add);
      addTearDown(replacement.close);
      expect(await replacement.start(), isTrue);
    },
    skip: !Platform.isWindows,
  );

  test(
    'second launch activates one existing owner and releases the lock on exit',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'bloomstep-instance-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      var activations = 0;
      final first = SingleInstance(
        folder.path,
        () async => activations++,
        (_) {},
      );
      final second = SingleInstance(folder.path, () async {}, (_) {});
      addTearDown(first.close);
      addTearDown(second.close);
      expect(await first.start(), isTrue);
      expect(await second.start(), isFalse);
      expect(activations, 1);
      await first.close();
      final replacement = SingleInstance(folder.path, () async {}, (_) {});
      addTearDown(replacement.close);
      expect(await replacement.start(), isTrue);
    },
    skip: !Platform.isWindows,
  );

  test('local activation requires the private descriptor token', () async {
    final folder = await Directory.systemTemp.createTemp(
      'bloomstep-instance-auth-',
    );
    addTearDown(() => folder.delete(recursive: true));
    var activations = 0;
    final errors = <String>[];
    final instance = SingleInstance(
      folder.path,
      () async => activations++,
      errors.add,
    );
    addTearDown(instance.close);
    await instance.start();
    final descriptor = jsonDecode(
      await File('${folder.path}${Platform.pathSeparator}instance.json')
          .readAsString(),
    ) as Map;
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      descriptor['port'] as int,
    );
    socket.writeln(jsonEncode({'command': 'activate', 'token': 'invalid'}));
    final response = await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    expect(jsonDecode(response), contains('error'));
    expect(activations, 0);
    expect(errors, isNotEmpty);
    socket.destroy();
  }, skip: !Platform.isWindows);
}
