import 'dart:io';
import 'dart:convert';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/services/session_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

void main() {
  test(
    'diagnostics require current consent and never retain error text',
    () async {
      final store = await GardenStore.open(':memory:', 'synthetic-diagnostics');
      addTearDown(store.close);
      final errors = <String>[];
      final diagnostics = SessionDiagnostics(store, onWriteError: errors.add);
      addTearDown(diagnostics.close);
      await diagnostics.record(
        const SocketException('private bearer and habit text'),
        source: 'dart_unhandled',
      );
      expect((await store.export())['events'], isEmpty);
      await store.setSetting('analytics', 'true');
      await diagnostics.record(
        const SocketException('private bearer and habit text'),
        source: 'dart_unhandled',
      );
      final events = (await store.export())['events'] as List;
      expect(
        events.where((e) => (e as Map)['name'] == 'session_started'),
        hasLength(1),
      );
      final crash =
          events.singleWhere((e) => (e as Map)['name'] == 'crash') as Map;
      final properties = jsonDecode(crash['properties'] as String);
      expect(properties, containsPair('errorKind', 'network'));
      expect(properties, containsPair('diagnosticSource', 'dart_unhandled'));
      expect(events.toString(), isNot(contains('private bearer')));
      expect(errors, isEmpty);
    },
  );

  test(
    'actual global hooks preserve presentation and unhandled failure',
    () async {
      final store = await GardenStore.open(':memory:', 'synthetic-hook');
      await store.setSetting('analytics', 'true');
      final originalFramework = FlutterError.onError;
      final originalUnhandled = PlatformDispatcher.instance.onError;
      var presented = 0;
      void framework(FlutterErrorDetails details) {
        presented++;
      }

      bool unhandled(Object error, StackTrace stack) => false;
      FlutterError.onError = framework;
      PlatformDispatcher.instance.onError = unhandled;
      final diagnostics = SessionDiagnostics(store, onWriteError: (_) {});
      try {
        diagnostics.attach();
        FlutterError.onError!(
          FlutterErrorDetails(exception: StateError('private')),
        );
        expect(
          PlatformDispatcher.instance.onError!(
            StateError('private'),
            StackTrace.current,
          ),
          isFalse,
        );
        expect(presented, 1);
        await diagnostics.flush();
        await diagnostics.close();
        expect(FlutterError.onError, framework);
        expect(PlatformDispatcher.instance.onError, unhandled);
        final events = (await store.export())['events'] as List;
        expect(
          events.where((e) => (e as Map)['name'] == 'crash'),
          hasLength(2),
        );
      } finally {
        await diagnostics.close();
        FlutterError.onError = originalFramework;
        PlatformDispatcher.instance.onError = originalUnhandled;
        await store.close();
      }
    },
  );

  test('failed writes surface a fixed warning and caller failure', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-write-failure');
    final errors = <String>[];
    final diagnostics = SessionDiagnostics(store, onWriteError: errors.add);
    await store.close();
    await expectLater(
      diagnostics.record(StateError('private'), source: 'dart_unhandled'),
      throwsA(isA<Exception>()),
    );
    await diagnostics.close();
    expect(errors.single, contains('could not be saved'));
    expect(errors.single, isNot(contains('private')));
  });

  test(
    'opt-out and disposed/account-changed scope cannot emit diagnostics',
    () async {
      final store = await GardenStore.open(':memory:', 'synthetic-a');
      addTearDown(store.close);
      final diagnostics = SessionDiagnostics(store, onWriteError: (_) {});
      await store.setSetting('analytics', 'true');
      await diagnostics.record(
        StateError('private'),
        source: 'flutter_framework',
      );
      await store.setSetting('analytics', 'false');
      await diagnostics.record(
        StateError('private'),
        source: 'flutter_framework',
      );
      expect((await store.export())['events'], isEmpty);
      await store.switchAccount('synthetic-b');
      await store.setSetting('analytics', 'true');
      await diagnostics.record(
        StateError('private'),
        source: 'flutter_framework',
      );
      expect(((await store.export())['events'] as List).length, 1);
      await diagnostics.close();
      await diagnostics.record(
        StateError('private'),
        source: 'flutter_framework',
      );
      expect(((await store.export())['events'] as List).length, 1);
    },
  );

  test('observed errors are bounded, not a complete crash census', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-cap');
    addTearDown(store.close);
    await store.setSetting('analytics', 'true');
    final diagnostics = SessionDiagnostics(store, onWriteError: (_) {});
    addTearDown(diagnostics.close);
    for (var i = 0; i < 15; i++) {
      await diagnostics.record(
        StateError('private$i'),
        source: 'flutter_framework',
      );
    }
    final events = (await store.export())['events'] as List;
    expect(events.where((e) => (e as Map)['name'] == 'crash'), hasLength(10));
  });
}
