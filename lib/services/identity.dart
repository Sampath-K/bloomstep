import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openid_client/openid_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'auth_observations.dart';

class IdentityService {
  AuthObservations? observations;
  static const issuerUrl = String.fromEnvironment('OIDC_ISSUER');
  static const clientId = String.fromEnvironment('OIDC_CLIENT_ID');
  static const apiScope = String.fromEnvironment('OIDC_API_SCOPE');
  static const apiOrigin = String.fromEnvironment('API_ORIGIN');
  // All published previews use Windows v4 DPAPI JSON. Its obsolete pre-v4
  // migration uses executable metadata and must not open a second namespace.
  static const _storage = FlutterSecureStorage(
    wOptions: WindowsOptions(useBackwardCompatibility: false),
  );
  Credential? _credential;
  DateTime? _validatedAt;
  DateTime? _lastObservedAt;
  Future<void> _storageTail = Future<void>.value();
  String? account;
  DateTime? get sessionExpiresAt => _validatedAt?.add(const Duration(days: 30));
  bool get hasValidSession {
    final now = DateTime.now().toUtc();
    if (_credential == null ||
        account == null ||
        _validatedAt == null ||
        !offlineSessionValid(
          _validatedAt!,
          now: now,
          lastObservedAt: _lastObservedAt,
        )) {
      return false;
    }
    if (_lastObservedAt == null || now.isAfter(_lastObservedAt!)) {
      _lastObservedAt = now;
    }
    return true;
  }

  bool get configured =>
      issuerUrl.startsWith('https://') &&
      clientId.isNotEmpty &&
      apiScope.isNotEmpty &&
      apiOrigin.startsWith('https://');

  static bool offlineSessionValid(
    DateTime validatedAt, {
    DateTime? now,
    DateTime? lastObservedAt,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    final age = current.difference(validatedAt.toUtc());
    return age >= const Duration(minutes: -5) &&
        age < const Duration(days: 30) &&
        (lastObservedAt == null ||
            current.difference(lastObservedAt.toUtc()) >=
                const Duration(minutes: -5));
  }

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _storageTail;
    final completed = Completer<void>();
    _storageTail = completed.future;
    try {
      await previous;
      return await operation();
    } finally {
      completed.complete();
    }
  }

  Future<void> checkpoint() async {
    if (!hasValidSession) throw StateError('The offline session has ended.');
    await _save(_validatedAt!.toIso8601String());
  }

  Future<bool> restore() async {
    if (!configured) return false;
    final raw = await _storage.read(key: 'bloomstep-session');
    if (raw == null) return false;
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw StateError(
        'The saved session could not be decoded. Sign in again.',
      );
    }
    if (decoded is! Map ||
        decoded['issuer'] is! String ||
        decoded['clientId'] is! String ||
        decoded['account'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(decoded['account'] as String) ||
        decoded['validatedAt'] is! String ||
        decoded['credential'] is! Map) {
      throw StateError('The saved session is incomplete. Sign in again.');
    }
    final record = decoded.cast<String, dynamic>();
    if (record['issuer'] != issuerUrl || record['clientId'] != clientId) {
      await signOut();
      return false;
    }
    if (record['lastObservedAt'] != null &&
        record['lastObservedAt'] is! String) {
      throw StateError(
        'The saved session clock record is invalid. Sign in again.',
      );
    }
    final observed = DateTime.parse(
      (record['lastObservedAt'] ?? record['validatedAt']) as String,
    ).toUtc();
    if (!offlineSessionValid(
      DateTime.parse(record['validatedAt'] as String),
      lastObservedAt: observed,
    )) {
      await signOut();
      return false;
    }
    final credential = Credential.fromJson(
      (record['credential'] as Map).cast<String, dynamic>(),
    );
    final claims = credential.idToken.claims.toJson();
    if (claims['iss'] is! String ||
        claims['sub'] is! String ||
        (claims['sub'] as String).isEmpty ||
        sha256
                .convert(utf8.encode('${claims['iss']}|${claims['sub']}'))
                .toString() !=
            record['account']) {
      throw StateError(
        'The saved identity does not match this garden. Sign in again.',
      );
    }
    _credential = credential;
    _validatedAt = DateTime.parse(record['validatedAt'] as String).toUtc();
    _lastObservedAt = observed;
    account = record['account'] as String;
    return true;
  }

  Future<void> signIn() async {
    try {
      await _signIn();
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'timeout',
        'Sign-in timed out. Return to Bloomstep and try again. '
            'This does not establish cancellation.',
      );
    } on SocketException {
      throw const AuthFailure(
        'network',
        'Sign-in could not reach the identity service. Check your connection and try again.',
      );
    } catch (_) {
      throw const AuthFailure(
        'unknown',
        'The identity response could not be completed or saved. '
            'Try sign-in again; if it persists, check the configured identity flow.',
      );
    }
  }

  Future<void> _signIn() async {
    if (!configured) {
      throw const AuthFailure(
        'unavailable',
        'Identity is not provisioned. No anonymous or simulated sign-in is available.',
      );
    }
    final issuer = await guardAuthStep(
      AuthStep.discovery,
      () =>
          Issuer.discover(Uri.parse(issuerUrl))
              .timeout(const Duration(seconds: 30)),
    );
    final nonce = const Uuid().v4();
    final flow = Flow.authorizationCodeWithPKCE(
      Client(issuer, clientId),
      scopes: ['openid', 'profile', 'email', 'offline_access', apiScope],
      additionalParameters: {'nonce': nonce},
    );
    // Entra discovery lists OIDC scopes, not custom API scopes.
    if (!flow.scopes.contains(apiScope)) flow.scopes.add(apiScope);
    // The package's IO Authenticator binds all interfaces; use loopback only.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 43821);
    flow.redirectUri = Uri.parse('http://127.0.0.1:43821/callback');
    final response = Completer<Map<String, String>>();
    final subscription = server.listen((request) async {
      final parameters = request.uri.queryParameters;
      if (request.uri.path != '/callback' ||
          parameters['state'] != flow.state) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(
          'Bloomstep sign-in response is invalid. Return to Bloomstep and start sign-in again.',
        );
      } else {
        request.response.write(
          'Return to Bloomstep. You may close this browser tab.',
        );
        if (!response.isCompleted) response.complete(parameters);
      }
      await request.response.close();
    });
    try {
      if (!await guardAuthStep(
        AuthStep.browser,
        () => launchUrl(
          flow.authenticationUri,
          mode: LaunchMode.externalApplication,
        ),
      )) {
        throw const AuthFailure(
          'unavailable',
          'The system browser could not be opened. Check your default browser and try again.',
        );
      }
      final parameters = await guardAuthStep(
        AuthStep.callback,
        () => response.future.timeout(const Duration(minutes: 3)),
      );
      final credential = await guardAuthStep(
        AuthStep.exchange,
        () => flow.callback(parameters).timeout(const Duration(seconds: 30)),
      );
      final violations = await guardAuthStep(
        AuthStep.validation,
        () => credential.validateToken().toList().timeout(
          const Duration(seconds: 30),
        ),
      );
      final claims = credential.idToken.claims.toJson();
      if (violations.isNotEmpty ||
          claims['nonce'] != nonce ||
          claims['sub'] is! String ||
          (claims['sub'] as String).isEmpty) {
        throw const AuthFailure(
          'validation',
          'Identity token validation failed. Sign-in was not saved.',
        );
      }
      _credential = credential;
      account = sha256
          .convert(utf8.encode('${claims['iss']}|${claims['sub']}'))
          .toString();
      await guardAuthStep(
        AuthStep.save,
        () => _save(DateTime.now().toUtc().toIso8601String()),
      );
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  Future<void> _save(String validatedAt) => _serialized(() async {
    if (_credential == null || account == null) {
      throw StateError('A signed-out session cannot be saved.');
    }
    final now = DateTime.now().toUtc();
    if (_lastObservedAt == null || now.isAfter(_lastObservedAt!)) {
      _lastObservedAt = now;
    }
    await _storage.write(
      key: 'bloomstep-session',
      value: jsonEncode({
        'issuer': issuerUrl,
        'clientId': clientId,
        'account': account,
        'validatedAt': validatedAt,
        'lastObservedAt': _lastObservedAt!.toIso8601String(),
        'credential': _credential!.toJson(),
      }),
    );
    _validatedAt = DateTime.parse(validatedAt).toUtc();
  });

  Future<String> accessToken() {
    final observer = observations;
    return observer != null && observer.store.account == account
        ? observer.run(AuthStage.apiToken, _accessToken)
        : _accessToken();
  }

  Future<String> _accessToken() async {
    if (!hasValidSession) {
      throw const AuthFailure(
        'unavailable',
        'Your offline session has ended. Sign in again before syncing.',
      );
    }
    final token = await guardAuthStep(
      AuthStep.apiToken,
      () =>
          _credential!.getTokenResponse().timeout(const Duration(seconds: 30)),
    );
    if (!hasValidSession) {
      throw const AuthFailure(
        'unavailable',
        'Your offline session ended during token refresh. Sign in again.',
      );
    }
    if (token.accessToken == null) {
      throw const AuthFailure(
        'validation',
        'The identity provider did not issue an API access token.',
      );
    }
    // Preserve the offline-session deadline; a refresh is not fresh user authentication.
    await guardAuthStep(AuthStep.save, () async {
      final saved = await _storage.read(key: 'bloomstep-session');
      if (saved != null) {
        await _save((jsonDecode(saved) as Map)['validatedAt'] as String);
      }
    });
    return token.accessToken!;
  }

  Future<void> signOut() async {
    _credential = null;
    _validatedAt = null;
    _lastObservedAt = null;
    account = null;
    await _serialized(() => _storage.delete(key: 'bloomstep-session'));
  }
}
