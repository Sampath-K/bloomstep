import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/garden_store.dart';
import 'session_events.dart';

class SessionDiagnostics {
  SessionDiagnostics(this.store, {required this.onWriteError})
    : _account = store.account,
      _generation = store.syncGeneration;
  final GardenStore store;
  final void Function(String) onWriteError;
  final String _account;
  final int _generation;
  final String sessionId = const Uuid().v4();
  bool _closed = false;
  bool _observed = false;
  bool _attached = false;
  int _errors = 0;
  Future<void> _pending = Future<void>.value();
  FlutterExceptionHandler? _previousFramework;
  bool Function(Object, StackTrace)? _previousUnhandled;
  FlutterExceptionHandler? _frameworkHandler;
  bool Function(Object, StackTrace)? _unhandledHandler;

  bool get _active =>
      !_closed &&
      store.account == _account &&
      store.syncGeneration == _generation;

  Future<void> start({bool authenticatedNow = false}) async {
    if (!_active || await store.setting('analytics') != 'true') return;
    if (!_active || _observed) return;
    await SessionEvents.entered(
      store,
      authenticatedNow: authenticatedNow,
      sessionId: sessionId,
    );
    _observed = true;
  }

  Future<void> consentChanged() async {
    if (!_active) return;
    if (await store.setting('analytics') != 'true') {
      _observed = false;
      return;
    }
    await start();
  }

  Future<void> record(Object error, {required String source}) {
    if (!['flutter_framework', 'dart_unhandled'].contains(source)) {
      throw ArgumentError.value(source, 'source');
    }
    final next = _pending.then((_) async {
      if (!_active || await store.setting('analytics') != 'true') return;
      if (!_active || _errors >= 10) return;
      await start();
      if (!_active) return;
      _errors++;
      await store.track(
        'crash',
        properties: {
          'sessionId': sessionId,
          'platform': GardenStore.telemetryPlatform,
          'errorKind': error is SocketException || error is TimeoutException
              ? 'network'
              : error is FormatException
              ? 'validation'
              : 'unknown',
          'diagnosticSource': source,
        },
      );
    });
    _pending = next.catchError((Object _) {
      onWriteError(
        'Optional diagnostic could not be saved. No error text or stack was collected.',
      );
    });
    return next;
  }

  void attach() {
    if (_attached || _closed) {
      throw StateError('Diagnostic scope is unavailable.');
    }
    _attached = true;
    _previousFramework = FlutterError.onError;
    _previousUnhandled = PlatformDispatcher.instance.onError;
    _frameworkHandler = (details) {
      record(details.exception, source: 'flutter_framework');
      final previous = _previousFramework;
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    _unhandledHandler = (error, stack) {
      record(error, source: 'dart_unhandled');
      return _previousUnhandled?.call(error, stack) ?? false;
    };
    FlutterError.onError = _frameworkHandler;
    PlatformDispatcher.instance.onError = _unhandledHandler;
  }

  Future<void> flush() => _pending;

  Future<void> close() async {
    _closed = true;
    if (_attached) {
      if (FlutterError.onError == _frameworkHandler) {
        FlutterError.onError = _previousFramework;
      }
      if (PlatformDispatcher.instance.onError == _unhandledHandler) {
        PlatformDispatcher.instance.onError = _previousUnhandled;
      }
      _attached = false;
    }
    await _pending;
  }
}
