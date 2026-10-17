import 'package:flutter_test/flutter_test.dart';

void expectConciseDialogCopy(String body) {
  expect(RegExp(r'\b\w+\b').allMatches(body).length, lessThanOrEqualTo(24));
  expect(
    RegExp(
      r'\b(?:ID-only|sync marker|event record)\b|\$\w+',
      caseSensitive: false,
    ).hasMatch(body),
    isFalse,
  );
}
