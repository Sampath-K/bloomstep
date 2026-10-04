import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openid_client/openid_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

class IdentityService {
  static const issuerUrl = String.fromEnvironment('OIDC_ISSUER');
  static const clientId = String.fromEnvironment('OIDC_CLIENT_ID');
  static const apiScope = String.fromEnvironment('OIDC_API_SCOPE');
  static const apiOrigin = String.fromEnvironment('API_ORIGIN');
  static const _storage = FlutterSecureStorage();
  Credential? _credential;
  String? account;
  bool get configured =>
      issuerUrl.startsWith('https://') &&
      clientId.isNotEmpty &&
      apiScope.isNotEmpty &&
      apiOrigin.startsWith('https://');

  Future<bool> restore() async {
    if (!configured) return false;
    final raw = await _storage.read(key: 'bloomstep-session');
    if (raw == null) return false;
    final record = (jsonDecode(raw) as Map).cast<String, dynamic>();
    if (record['issuer'] != issuerUrl || record['clientId'] != clientId) {
      return false;
    }
    if (DateTime.now()
            .toUtc()
            .difference(DateTime.parse(record['validatedAt'] as String))
            .inDays >
        30) {
      await signOut();
      return false;
    }
    _credential = Credential.fromJson(
      (record['credential'] as Map).cast<String, dynamic>(),
    );
    account = record['account'] as String;
    return true;
  }

  Future<void> signIn() async {
    if (!configured) {
      throw StateError(
        'Identity is not provisioned. No anonymous or simulated sign-in is available.',
      );
    }
    final issuer = await Issuer.discover(Uri.parse(issuerUrl))
        .timeout(const Duration(seconds: 30));
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
        request.response.write('Invalid authentication response.');
      } else {
        request.response.write(
          'Return to Bloomstep. You may close this browser tab.',
        );
        if (!response.isCompleted) response.complete(parameters);
      }
      await request.response.close();
    });
    try {
      if (!await launchUrl(
        flow.authenticationUri,
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('The system browser could not be opened.');
      }
      final parameters = await response.future.timeout(
        const Duration(minutes: 3),
      );
      final credential = await flow.callback(parameters);
      final violations = await credential.validateToken().toList();
      final claims = credential.idToken.claims.toJson();
      if (violations.isNotEmpty ||
          claims['nonce'] != nonce ||
          claims['sub'] is! String ||
          (claims['sub'] as String).isEmpty) {
        throw StateError(
          'Identity token validation failed. Sign-in was not saved.',
        );
      }
      _credential = credential;
      account = sha256
          .convert(utf8.encode('${claims['iss']}|${claims['sub']}'))
          .toString();
      await _save(DateTime.now().toUtc().toIso8601String());
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  Future<void> _save(String validatedAt) => _storage.write(
    key: 'bloomstep-session',
    value: jsonEncode({
      'issuer': issuerUrl,
      'clientId': clientId,
      'account': account,
      'validatedAt': validatedAt,
      'credential': _credential!.toJson(),
    }),
  );

  Future<String> accessToken() async {
    if (_credential == null) throw StateError('Sign in before syncing.');
    final token = await _credential!.getTokenResponse().timeout(
      const Duration(seconds: 30),
    );
    if (token.accessToken == null) {
      throw StateError(
        'The identity provider did not issue an API access token.',
      );
    }
    // Preserve the offline-session deadline; a refresh is not fresh user authentication.
    final saved = await _storage.read(key: 'bloomstep-session');
    if (saved != null) {
      await _save((jsonDecode(saved) as Map)['validatedAt'] as String);
    }
    return token.accessToken!;
  }

  Future<void> signOut() async {
    await _storage.delete(key: 'bloomstep-session');
    _credential = null;
    account = null;
  }
}
