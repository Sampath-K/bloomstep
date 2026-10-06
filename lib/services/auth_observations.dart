import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../core/garden_store.dart';

enum AuthStage {
  sessionEntry('session_entry'),
  apiToken('api_token');

  const AuthStage(this.value);
  final String value;
}

enum AuthStep {
  discovery(
    'Identity discovery failed. Check the configured identity service and connection.',
  ),
  browser(
    'The system browser could not be opened. Check your default browser.',
  ),
  callback(
    'No valid browser callback arrived before the sign-in deadline. Try again; cancellation is not established.',
  ),
  exchange(
    'The identity callback could not be exchanged. Restart sign-in; check the configured callback if it persists.',
  ),
  validation('Identity token validation failed. Sign-in was not saved.'),
  save(
    'Authentication could not be saved securely. Check local storage access and try again.',
  ),
  apiToken(
    'An API token could not be obtained. Check your connection or sign in again.',
  );

  const AuthStep(this.message);
  final String message;
}

Future<T> guardAuthStep<T>(
  AuthStep step,
  Future<T> Function() operation,
) async {
  try {
    return await operation();
  } on AuthFailure {
    rethrow;
  } catch (error) {
    throw AuthFailure(AuthObservations.errorKind(error), step.message);
  }
}

class AuthFailure implements Exception {
  const AuthFailure(this.kind, this.message);
  final String kind;
  final String message;
  @override
  String toString() => message;
}

class AuthObservations {
  AuthObservations(
    this.store, {
    required this.onWriteError,
    Duration Function()? monotonicNow,
  }) : _owner = store.account,
       _generation = store.syncGeneration,
       _monotonicNow = monotonicNow ?? _clock();

  final GardenStore store;
  final void Function(String) onWriteError;
  final String _owner;
  final int _generation;
  final Duration Function() _monotonicNow;
  static Duration Function() _clock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsed;
  }

  bool _closed = false;
  int _attempts = 0;

  void close() => _closed = true;

  bool get _active =>
      !_closed &&
      store.account == _owner &&
      store.syncGeneration == _generation;

  static String errorKind(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (error is SocketException) return 'network';
    if (error is FormatException) return 'validation';
    if (error is AuthFailure &&
        [
          'timeout',
          'network',
          'validation',
          'unavailable',
          'unknown',
        ].contains(error.kind)) {
      return error.kind;
    }
    return 'unknown';
  }

  Future<T> run<T>(AuthStage stage, Future<T> Function() operation) async {
    final consentGeneration = store.analyticsGeneration;
    final id = const Uuid().v4();
    final startedAt = _monotonicNow();
    int elapsed() => (_monotonicNow() - startedAt).inMilliseconds;
    Future<bool> save(String outcome, String kind) async {
      if (!_active ||
          store.analyticsGeneration != consentGeneration ||
          elapsed() < 0 ||
          elapsed() > 180000) {
        return false;
      }
      try {
        return await store.trackAuthObservation(
          {
            'attemptId': id,
            'authStage': stage.value,
            'outcome': outcome,
            'authErrorKind': kind,
            'authSource': 'external_unattributed',
            'elapsedMs': outcome == 'started' ? 0 : elapsed(),
            'platform': 'windows',
          },
          owner: _owner,
          generation: _generation,
          consentGeneration: consentGeneration,
        );
      } catch (_) {
        onWriteError(
          'Optional authentication observation could not be saved. '
          'No credentials or error text were collected.',
        );
        return false;
      }
    }

    final eligible = _active && _attempts < 10;
    if (eligible) _attempts++;
    final capture = eligible && await save('started', 'none');
    try {
      final result = await operation();
      if (capture) await save('succeeded', 'none');
      return result;
    } catch (error) {
      if (capture) await save('failed', errorKind(error));
      rethrow;
    }
  }
}
