import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:openid_client/openid_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'microsoft_photo.dart';

/// Bounded, redirect-free transport for OIDC metadata, keys and token exchange.
class MicrosoftPhotoAuthClient extends http.BaseClient {
  MicrosoftPhotoAuthClient(this.inner);
  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    if (uri.scheme != 'https' ||
        uri.host != 'login.microsoftonline.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty) {
      throw const MicrosoftPhotoFailure();
    }
    request.followRedirects = false;
    return (() async {
      final response = await inner.send(request);
      if (response.statusCode >= 300 ||
          (response.contentLength ?? 0) > MicrosoftPhotoConnection.maxBytes) {
        throw const MicrosoftPhotoFailure();
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > MicrosoftPhotoConnection.maxBytes) {
          throw const MicrosoftPhotoFailure();
        }
        bytes.add(chunk);
      }
      return http.StreamedResponse(
        Stream.value(bytes.takeBytes()),
        response.statusCode,
        headers: response.headers,
      );
    })().timeout(const Duration(seconds: 30));
  }

  @override
  void close() => inner.close();
}

class MicrosoftPhotoAuthenticator {
  const MicrosoftPhotoAuthenticator();
  static const clientId = String.fromEnvironment('MICROSOFT_PHOTO_CLIENT_ID');
  static final redirectUri = Uri.parse('http://127.0.0.1:43822/photo-callback');
  static final issuerUri = Uri.parse(
    'https://login.microsoftonline.com/'
    '${MicrosoftPhotoIdentity.consumerTenant}/v2.0',
  );

  Future<MicrosoftPhotoSession> authenticate(Future<void> cancelled) async {
    if (clientId.isEmpty) throw const MicrosoftPhotoFailure();
    suppressOidcResponseLogging();
    final client = MicrosoftPhotoAuthClient(http.Client());
    var wasCancelled = false;
    unawaited(
      cancelled.then((_) {
        wasCancelled = true;
        client.close();
      }),
    );
    HttpServer? server;
    StreamSubscription<HttpRequest>? subscription;
    var retained = false;
    try {
      final issuer = await Issuer.discover(issuerUri, httpClient: client);
      if (wasCancelled) throw const MicrosoftPhotoFailure();
      final nonce = const Uuid().v4();
      final flow = Flow.authorizationCodeWithPKCE(
        Client(issuer, clientId, httpClient: client),
        scopes: ['openid', 'https://graph.microsoft.com/User.Read'],
        additionalParameters: {'nonce': nonce},
      );
      const graphScope = 'https://graph.microsoft.com/User.Read';
      if (!flow.scopes.contains(graphScope)) flow.scopes.add(graphScope);
      flow.redirectUri = redirectUri;
      final authorization = flow.authenticationUri;
      if (authorization.scheme != 'https' ||
          authorization.host != 'login.microsoftonline.com' ||
          authorization.port != 443 ||
          authorization.userInfo.isNotEmpty) {
        throw const MicrosoftPhotoFailure();
      }
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 43822);
      if (wasCancelled) throw const MicrosoftPhotoFailure();
      final response = Completer<Map<String, String>>();
      subscription = server.listen((request) async {
        final valid = validCallback(request.method, request.uri, flow.state);
        request.response.headers
          ..set('Cache-Control', 'no-store')
          ..set('Referrer-Policy', 'no-referrer')
          ..set('Content-Security-Policy', "default-src 'none'");
        request.response.statusCode = valid
            ? HttpStatus.ok
            : HttpStatus.badRequest;
        request.response.write('Return to Bloomstep. You may close this tab.');
        if (valid && !response.isCompleted) {
          response.complete(request.uri.queryParameters);
        }
        await request.response.close();
      });
      if (!await launchUrl(
        authorization,
        mode: LaunchMode.externalApplication,
      )) {
        throw const MicrosoftPhotoFailure();
      }
      final parameters = await Future.any([
        response.future,
        cancelled.then<Map<String, String>>(
          (_) => throw const MicrosoftPhotoFailure(),
        ),
      ]).timeout(const Duration(minutes: 3));
      if (parameters.containsKey('error')) throw const MicrosoftPhotoFailure();
      final credential = await flow.callback(parameters);
      final violations = await credential.validateToken().toList().timeout(
        const Duration(seconds: 30),
      );
      final claims = credential.idToken.claims.toJson();
      if (wasCancelled ||
          violations.isNotEmpty ||
          claims['nonce'] != nonce ||
          claims['iss'] != issuerUri.toString() ||
          claims['aud'] != clientId ||
          claims['tid'] != MicrosoftPhotoIdentity.consumerTenant ||
          claims['oid'] is! String ||
          !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(claims['oid'] as String)) {
        throw const MicrosoftPhotoFailure();
      }
      retained = true;
      return _PhotoSession(credential, client, claims['oid'] as String);
    } finally {
      await subscription?.cancel();
      await server?.close(force: true);
      if (!retained) client.close();
    }
  }

  // openid_client logs full token response bodies at FINE. Disable its logger
  // explicitly even if a future diagnostic listener enables root logging.
  static void suppressOidcResponseLogging() {
    hierarchicalLoggingEnabled = true;
    Logger('openid_client').level = Level.OFF;
  }

  static bool validCallback(String method, Uri uri, String state) {
    if (uri.toString().length > 8192) return false;
    final Map<String, List<String>> parameters;
    try {
      parameters = uri.queryParametersAll;
    } on FormatException {
      return false;
    }
    return method == 'GET' &&
        uri.path == redirectUri.path &&
        uri.fragment.isEmpty &&
        parameters.keys.every(
          const {
            'state',
            'code',
            'error',
            'error_description',
            'error_uri',
            'session_state',
          }.contains,
        ) &&
        parameters.values.every((values) => values.length == 1) &&
        parameters['state']?.single == state &&
        ((parameters['code']?.single.isNotEmpty ?? false) !=
            (parameters['error']?.single.isNotEmpty ?? false));
  }
}

class _PhotoSession implements MicrosoftPhotoSession {
  _PhotoSession(this._credential, this._client, this.objectId);
  Credential? _credential;
  final http.Client _client;
  @override
  final String objectId;
  @override
  String get tenantId => MicrosoftPhotoIdentity.consumerTenant;
  @override
  Future<String> accessToken() async {
    MicrosoftPhotoAuthenticator.suppressOidcResponseLogging();
    final credential = _credential;
    if (credential == null) throw const MicrosoftPhotoFailure();
    final token = await credential.getTokenResponse();
    if (_credential == null || token.accessToken == null) {
      throw const MicrosoftPhotoFailure();
    }
    return token.accessToken!;
  }

  @override
  void close() {
    _credential = null;
    _client.close();
  }
}
