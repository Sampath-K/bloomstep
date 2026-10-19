import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/windows_keyboard.dart';

void main() {
  testWidgets('hosted feedback keys preserve the complete editing sequence', (
    tester,
  ) async {
    var clipboard = 'abcd';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        if (call.method == 'Clipboard.hasStrings') {
          return {'value': clipboard.isNotEmpty};
        }
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.showKeyboard(field);
    await tester.pumpAndSettle();
    Future<void> keys(
      List<int> codes, {
      bool control = false,
      bool shift = false,
    }) async {
      await hostedArm64FeedbackKeys(
        tester,
        field,
        codes,
        control: control,
        shift: shift,
      );
      await tester.pumpAndSettle();
      expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
    }

    await keys([0x56], control: true);
    expect(controller.text, 'abcd');
    await keys([0x08]);
    expect(controller.text, 'abc');
    await keys([0x24, 0x2e]);
    expect(controller.text, 'bc');
    await keys([0x23, 0x25, 0x08]);
    expect(controller.text, 'c');
    await keys([0x24, 0x27]);
    expect(controller.selection, const TextSelection.collapsed(offset: 1));
    await keys([0x41], control: true);
    expect(controller.selection.textInside(controller.text), 'c');
    await keys([0x43], control: true);
    expect(clipboard, 'c');
    await keys([0x58], control: true);
    expect(controller.text, isEmpty);
    await keys([0x56], control: true);
    expect(controller.text, 'c');
    await keys([0x24], shift: true);
    expect(controller.selection.textInside(controller.text), 'c');
    await keys([0x5a]);
    expect(controller.text.toLowerCase(), 'z');
    await expectLater(
      hostedArm64FeedbackKeys(tester, field, [0]),
      throwsArgumentError,
    );
    expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
