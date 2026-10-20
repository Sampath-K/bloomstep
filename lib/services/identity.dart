import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:openid_client/openid_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'auth_observations.dart';
import 'microsoft_photo.dart';
import 'microsoft_photo_auth.dart';

class IdentityProfile {
  const IdentityProfile({
    this.displayName,
    this.photoUrl,
    this.photoBytes,
    this.signInProvider,
  });
  final String? displayName;
  final String? photoUrl;
  final Uint8List? photoBytes;
  /// Current sign-in method when attested by ID-token claims, not a list of
  /// linked accounts or proof that linking/unlinking is supported.
  final String? signInProvider;

  /// Formats validated ID-token claims, optionally enriched by authenticated
  /// issuer userinfo for the same subject. Account fallbacks are display-only.
  factory IdentityProfile.fromClaims(
    Map<String, dynamic> claims, {
    Map<String, dynamic>? userInfo,
  }) {
    String? text(dynamic value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    String? nameText(dynamic value) {
      final result = text(value);
      return result?.toLowerCase() == 'unknown' ? null : result;
    }

    final boundInfo = _subjectBoundUserInfo(claims, userInfo);
    String? nameClaim(String key) =>
        nameText(claims[key]) ?? nameText(boundInfo[key]);
    String? firstEmail(dynamic value) {
      if (value is! List) return null;
      for (final email in value) {
        final result = nameText(email);
        if (result != null) return result;
      }
      return null;
    }

    final picture = text(claims['picture']) ?? text(boundInfo['picture']);
    final pictureUri = picture == null ? null : Uri.tryParse(picture);
    final parts = [
      nameClaim('given_name'),
      nameClaim('family_name'),
    ].whereType<String>().join(' ');
    return IdentityProfile(
      signInProvider: _signInProvider(claims),
      displayName:
          nameClaim('name') ??
          (parts.isEmpty ? null : parts) ??
          nameClaim('preferred_username') ??
          nameClaim('email') ??
          firstEmail(claims['emails']) ??
          firstEmail(boundInfo['emails']),
      photoUrl:
          pictureUri != null &&
              pictureUri.scheme == 'https' &&
              pictureUri.hasAuthority &&
              pictureUri.host.isNotEmpty &&
              pictureUri.userInfo.isEmpty
          ? pictureUri.toString()
          : null,
    );
  }

  static String? _signInProvider(Map<String, dynamic> claims) {
    final idp = claims['idp'];
    if (idp != null) {
      return switch (idp) {
        'google.com' || 'https://accounts.google.com' => 'Google',
        'live.com' || 'https://login.live.com' => 'Microsoft',
        _ => null,
      };
    }
    if (claims['iss'] == 'https://accounts.google.com' ||
        claims['iss'] == 'accounts.google.com') {
      return 'Google';
    }
    return _directMicrosoftIdentity(claims) &&
            claims['tid'] == MicrosoftPhotoIdentity.consumerTenant
        ? 'Microsoft'
        : null;
  }

  static bool _directMicrosoftIdentity(Map<String, dynamic> claims) {
    final tenant = claims['tid'];
    return tenant is String &&
        RegExp(
          r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-'
          r'[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
        ).hasMatch(tenant) &&
        claims['iss'] == 'https://login.microsoftonline.com/$tenant/v2.0';
  }

  /// Uses only an existing, explicitly Graph-authorized token response after
  /// ID-token validation. Never decodes access-token claims or requests consent.
  static Future<Map<String, dynamic>> microsoftGraphUserInfo({
    required Map<String, dynamic> verifiedClaims,
    required Map<String, dynamic> tokenResponse,
    required http.Client client,
  }) async {
    final objectId = verifiedClaims['oid'];
    final subject = verifiedClaims['sub'];
    final token = tokenResponse['access_token'];
    final scope = tokenResponse['scope'];
    if (!_directMicrosoftIdentity(verifiedClaims) ||
        objectId is! String ||
        objectId.isEmpty ||
        subject is! String ||
        subject.isEmpty ||
        token is! String ||
        token.isEmpty ||
        tokenResponse['token_type'] is! String ||
        (tokenResponse['token_type'] as String).toLowerCase() != 'bearer' ||
        scope is! String ||
        !scope.split(RegExp(r'\s+')).contains(
          'https://graph.microsoft.com/User.Read',
        )) {
      return const {};
    }
    final abort = Completer<void>();
    final deadline = Timer(const Duration(seconds: 5), () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final request = http.AbortableRequest(
        'GET',
        Uri.parse(
          'https://graph.microsoft.com/v1.0/me'
          '?\$select=id,displayName,givenName,surname',
        ),
        abortTrigger: abort.future,
      )
        ..followRedirects = false
        ..headers['Authorization'] = 'Bearer $token';
      return await (() async {
        final response = await client.send(request);
        const maxBytes = 64 * 1024;
        if (response.statusCode != 200 ||
            (response.contentLength ?? 0) > maxBytes) {
          return <String, dynamic>{};
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxBytes) {
            return <String, dynamic>{};
          }
          bytes.add(chunk);
        }
        final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
        if (decoded is! Map || decoded['id'] != objectId) {
          return <String, dynamic>{};
        }
        return <String, dynamic>{
          'sub': subject,
          'name': decoded['displayName'],
          'given_name': decoded['givenName'],
          'family_name': decoded['surname'],
        };
      })().timeout(const Duration(seconds: 5));
    } catch (_) {
      return const {};
    } finally {
      deadline.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  static Map<String, dynamic> _subjectBoundUserInfo(
    Map<String, dynamic> claims,
    Map<String, dynamic>? userInfo,
  ) {
    final subject = claims['sub'];
    if (subject is! String ||
        subject.isEmpty ||
        userInfo == null ||
        userInfo['sub'] != subject) {
      return const {};
    }
    return {
      for (final key in [
        'sub',
        'name',
        'given_name',
        'family_name',
        'preferred_username',
        'email',
        'emails',
        'picture',
      ])
        if (userInfo.containsKey(key)) key: userInfo[key],
    };
  }
}

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
  Map<String, dynamic> _userInfo = const {};
  final _microsoftPhoto = MicrosoftPhotoConnection(
    authenticate: const MicrosoftPhotoAuthenticator().authenticate,
    client: http.Client(),
  );
  String? _photoAttemptedAccount;
  DateTime? _validatedAt;
  DateTime? _lastObservedAt;
  Future<void> _storageTail = Future<void>.value();
  String? account;
  IdentityProfile? get profile {
    if (!hasValidSession) return null;
    final claimed = IdentityProfile.fromClaims(
      _credential!.idToken.claims.toJson(),
      userInfo: _userInfo,
    );
    return IdentityProfile(
      displayName: claimed.displayName,
      photoUrl: claimed.photoUrl,
      photoBytes: _microsoftPhoto.bytesFor(account),
      signInProvider: claimed.signInProvider,
    );
  }

  // Current CIAM tokens do not prove the upstream MSA tenant/oid. Keep the
  // direct connection disabled until a trusted, non-user-editable projection
  // is implemented and verified; never infer it from email or CIAM sub/oid.
  MicrosoftPhotoIdentity? get microsoftPhotoIdentity => null;

  Future<MicrosoftPhotoStatus> loadMicrosoftPhoto() async {
    if (!hasValidSession) {
      _microsoftPhoto.clear();
      return MicrosoftPhotoStatus.unlinked;
    }
    if (_photoAttemptedAccount == account) {
      return _microsoftPhoto.bytesFor(account) == null
          ? MicrosoftPhotoStatus.unavailable
          : MicrosoftPhotoStatus.loaded;
    }
    _photoAttemptedAccount = account;
    final proof = microsoftPhotoIdentity;
    if (proof == null || proof.budlarkAccount != account) {
      _microsoftPhoto.clear();
      return MicrosoftPhotoStatus.unlinked;
    }
    return _microsoftPhoto.connect(proof);
  }

  void clearMicrosoftPhoto() {
    _photoAttemptedAccount = null;
    _microsoftPhoto.clear();
  }

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
    final raw = await _storage.read(key: 'budlark-session');
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
    _userInfo = IdentityProfile._subjectBoundUserInfo(
      claims,
      record['userInfo'] is Map
          ? (record['userInfo'] as Map).cast<String, dynamic>()
          : null,
    );
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
        'Sign-in timed out. Return to Budlark and try again. '
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
    clearMicrosoftPhoto();
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
          'Budlark sign-in response is invalid. Return to Budlark and start sign-in again.',
        );
      } else {
        request.response.write(
          'Return to Budlark. You may close this browser tab.',
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
      final userInfo = await _loadUserInfo(credential, claims);
      final graphClient = http.Client();
      final Map<String, dynamic> graphInfo;
      try {
        graphInfo = await IdentityProfile.microsoftGraphUserInfo(
          verifiedClaims: claims,
          tokenResponse: credential.response ?? const {},
          client: graphClient,
        );
      } finally {
        graphClient.close();
      }
      // Usable standard userinfo wins; blank fields must not erase Graph names.
      final enrichedInfo = {...userInfo};
      for (final entry in graphInfo.entries) {
        final current = enrichedInfo[entry.key];
        if (current is! String ||
            current.trim().isEmpty ||
            current.trim().toLowerCase() == 'unknown') {
          enrichedInfo[entry.key] = entry.value;
        }
      }
      final previousCredential = _credential;
      final previousUserInfo = _userInfo;
      final previousAccount = account;
      final previousValidated = _validatedAt;
      final previousObserved = _lastObservedAt;
      _credential = credential;
      _userInfo = enrichedInfo;
      account = sha256
          .convert(utf8.encode('${claims['iss']}|${claims['sub']}'))
          .toString();
      try {
        await guardAuthStep(
          AuthStep.save,
          () => _save(DateTime.now().toUtc().toIso8601String()),
        );
      } catch (_) {
        _credential = previousCredential;
        _userInfo = previousUserInfo;
        account = previousAccount;
        _validatedAt = previousValidated;
        _lastObservedAt = previousObserved;
        rethrow;
      }
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _loadUserInfo(
    Credential credential,
    Map<String, dynamic> claims,
  ) async {
    final endpoint = credential.client.issuer.metadata.userinfoEndpoint;
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      return const {};
    }
    try {
      // Only the validated issuer's HTTPS endpoint may enrich this identity.
      // Userinfo is optional and must never turn successful sign-in into failure.
      final info = await credential.getUserInfo().timeout(
        const Duration(seconds: 5),
      );
      return IdentityProfile._subjectBoundUserInfo(claims, info.toJson());
    } catch (_) {
      return const {};
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
      key: 'budlark-session',
      value: jsonEncode({
        'issuer': issuerUrl,
        'clientId': clientId,
        'account': account,
        'validatedAt': validatedAt,
        'lastObservedAt': _lastObservedAt!.toIso8601String(),
        'credential': _credential!.toJson(),
        if (_userInfo.isNotEmpty) 'userInfo': _userInfo,
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
      final saved = await _storage.read(key: 'budlark-session');
      if (saved != null) {
        await _save((jsonDecode(saved) as Map)['validatedAt'] as String);
      }
    });
    return token.accessToken!;
  }

  Future<void> signOut() async {
    clearMicrosoftPhoto();
    _credential = null;
    _userInfo = const {};
    _validatedAt = null;
    _lastObservedAt = null;
    account = null;
    await _serialized(() => _storage.delete(key: 'budlark-session'));
  }
}
