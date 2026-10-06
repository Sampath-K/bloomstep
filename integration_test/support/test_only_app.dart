import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/services/identity.dart';

const _testBuild = bool.fromEnvironment('BLOOMSTEP_TEST_BUILD');
const _testIssuer = 'https://bloomstep.test';
const _testAudience = 'bloomstep-test-api';

class SyntheticTestSession extends IdentityService {
  SyntheticTestSession(String username, String secret)
    : _username = username,
      _secretBytes = utf8.encode(secret),
      _expiresAt = DateTime.now().toUtc().add(const Duration(hours: 1)) {
    account = sha256.convert(utf8.encode('$_testIssuer|$username')).toString();
  }

  final String _username;
  String get username => _username;
  final List<int> _secretBytes;
  final DateTime _expiresAt;
  bool _active = true;

  @override
  bool get configured => _testBuild;

  @override
  bool get hasValidSession => _testBuild && _active;

  @override
  DateTime? get sessionExpiresAt => _expiresAt;

  @override
  Future<bool> restore() async => false;

  @override
  Future<void> signIn() async {
    throw StateError('Synthetic sessions require the test-only secret gate.');
  }

  @override
  Future<String> accessToken() async {
    if (!hasValidSession) throw StateError('Synthetic test session is closed.');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final header = _base64Url({'alg': 'HS256', 'typ': 'JWT'});
    final payload = _base64Url({
      'iss': _testIssuer,
      'sub': _username,
      'aud': _testAudience,
      'iat': now,
      'exp': now + 120,
      'scp': 'Garden.ReadWrite',
    });
    final input = '$header.$payload';
    final signature = Hmac(
      sha256,
      _secretBytes,
    ).convert(utf8.encode(input)).bytes;
    return '$input.${base64Url.encode(signature).replaceAll('=', '')}';
  }

  @override
  Future<void> checkpoint() async {
    if (!hasValidSession) throw StateError('Synthetic test session is closed.');
  }

  @override
  Future<void> signOut() async {
    _active = false;
    account = null;
    for (var i = 0; i < _secretBytes.length; i++) {
      _secretBytes[i] = 0;
    }
  }

  static String _base64Url(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
}

class TestOnlyAuthGate {
  const TestOnlyAuthGate._();

  static const usernameFieldKey = Key('test-auth-username');
  static const secretFieldKey = Key('test-auth-secret');

  static bool get enabled => _testBuild;

  static bool validTestSecret(String? secret) =>
      secret != null && RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(secret);

  static bool _constantTimeEquals(String expected, String actual) {
    final left = expected.codeUnits;
    final right = actual.codeUnits;
    var difference = left.length ^ right.length;
    final limit = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < limit; i++) {
      difference |=
          (i < left.length ? left[i] : 0) ^ (i < right.length ? right[i] : 0);
    }
    return difference == 0;
  }

  static SyntheticTestSession? authenticate({
    required String? expectedSecret,
    required String username,
    required String suppliedSecret,
  }) {
    if (!_testBuild ||
        !validTestSecret(expectedSecret) ||
        !_constantTimeEquals(expectedSecret!, suppliedSecret)) {
      return null;
    }
    final normalized = username.trim().toLowerCase();
    if (!RegExp(r'^synthetic-[a-z0-9][a-z0-9_-]{0,23}$').hasMatch(normalized)) {
      return null;
    }
    return SyntheticTestSession(normalized, suppliedSecret);
  }
}

class TestOnlyBloomstepApp extends StatefulWidget {
  const TestOnlyBloomstepApp({
    super.key,
    required this.runRoot,
    required this.expectedSecret,
    this.clock,
    this.onAdvanceClock,
    this.onAuthenticated,
    this.onSessionClosed,
  });

  final Directory runRoot;
  final String? expectedSecret;
  final DateTime Function()? clock;
  final VoidCallback? onAdvanceClock;
  final void Function(SyntheticTestSession session, GardenStore store)?
  onAuthenticated;
  final void Function(SyntheticTestSession session, GardenStore store)?
  onSessionClosed;

  @override
  State<TestOnlyBloomstepApp> createState() => _TestOnlyBloomstepAppState();
}

class _TestOnlyBloomstepAppState extends State<TestOnlyBloomstepApp> {
  final _username = TextEditingController();
  final _secret = TextEditingController();
  SyntheticTestSession? _session;
  GardenStore? _store;
  bool _working = false;
  String? _error;

  bool get _safeTestRoot {
    final root = p.normalize(p.absolute(widget.runRoot.path));
    final temp = p.normalize(p.absolute(Directory.systemTemp.path));
    return TestOnlyAuthGate.enabled &&
        p.isWithin(temp, root) &&
        p.basename(root).startsWith('bloomstep-it-') &&
        Directory(root).existsSync();
  }

  String _databasePath(String username) =>
      p.join(widget.runRoot.path, '$username.sqlite');

  @override
  void dispose() {
    _username.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_safeTestRoot || _working || _store != null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final session = TestOnlyAuthGate.authenticate(
      expectedSecret: widget.expectedSecret,
      username: _username.text,
      suppliedSecret: _secret.text,
    );
    _secret.clear();
    if (session == null) {
      final invalidName = !_validUsername(_username.text);
      if (mounted) {
        setState(() {
          _error = invalidName
              ? 'Use a synthetic username, not an email address.'
              : 'Test sign-in failed. No garden was opened.';
          _working = false;
        });
      }
      return;
    }
    try {
      final path = _databasePath(session.username);
      final store = await GardenStore.open(
        path,
        session.account!,
        clock: widget.clock,
      );
      if (!mounted) {
        await store.close();
        await session.signOut();
        return;
      }
      setState(() {
        _session = session;
        _store = store;
        _working = false;
      });
      widget.onAuthenticated?.call(session, store);
    } catch (_) {
      await session.signOut();
      if (mounted) {
        setState(() {
          _error = 'The disposable test garden could not be opened.';
          _working = false;
        });
      }
    }
  }

  bool _validUsername(String username) =>
      RegExp(r'^synthetic-[a-z0-9][a-z0-9_-]{0,23}$')
          .hasMatch(username.trim().toLowerCase());

  Future<void> _closeSession() async {
    final store = _store;
    final session = _session;
    if (store == null || session == null || _working) return;
    setState(() {
      _working = true;
      _store = null;
      _session = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    try {
      await store.close();
    } finally {
      await session.signOut();
      widget.onSessionClosed?.call(session, store);
    }
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final session = _session;
    if (!_safeTestRoot) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Test build is locked. No garden was opened.'),
          ),
        ),
      );
    }
    if (store != null && session != null) {
      return MaterialApp(
        title: 'Bloomstep isolated test build',
        home: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Row(
                    children: [
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'TEST ONLY - synthetic profile - no customer account or cloud',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _working ? null : _closeSession,
                        child: const Text('Close test profile'),
                      ),
                      if (widget.onAdvanceClock != null)
                        TextButton(
                          key: const Key('test-advance-clock'),
                          onPressed: _working
                              ? null
                              : () {
                                  widget.onAdvanceClock!();
                                  setState(() {});
                                },
                          child: const Text('Advance synthetic clock'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: GardenScreen(
                    key: ValueKey(widget.clock?.call()),
                    store: store,
                    clock: widget.clock,
                    testExportPathSelector: () async {
                      final target = File(
                        p.join(
                          widget.runRoot.path,
                          '${session.username}-export.json',
                        ),
                      );
                      if (await target.exists()) {
                        throw StateError(
                          'The owned test export already exists; refusing overwrite.',
                        );
                      }
                      return target.path;
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final secretAvailable = TestOnlyAuthGate.validTestSecret(
      widget.expectedSecret,
    );
    return MaterialApp(
      title: 'Bloomstep isolated test sign-in',
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('TEST ONLY - disposable Bloomstep profile'),
                  TextField(
                    key: TestOnlyAuthGate.usernameFieldKey,
                    controller: _username,
                    decoration: const InputDecoration(
                      labelText: 'Synthetic username',
                    ),
                    autocorrect: false,
                  ),
                  TextField(
                    key: TestOnlyAuthGate.secretFieldKey,
                    controller: _secret,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Ephemeral test key',
                    ),
                    onSubmitted: (_) => _continue(),
                  ),
                  if (!secretAvailable)
                    const Text('Test sign-in is unavailable.'),
                  if (_error != null) Text(_error!),
                  FilledButton(
                    onPressed: _working || !secretAvailable ? null : _continue,
                    child: const Text('Continue to test garden'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
