import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/garden_store.dart';
import '../features/garden/garden_screen.dart';
import '../features/garden/profile_section.dart';
import '../services/auth_observations.dart';
import '../services/identity.dart';
import '../services/installer_measurement.dart';
import '../services/invitation_intent.dart';
import '../services/session_diagnostics.dart';
import 'session_boundary.dart';
import 'theme.dart';

const _testBuild = bool.fromEnvironment('BLOOMSTEP_TEST_BUILD');

class BloomstepApp extends StatelessWidget {
  const BloomstepApp({
    super.key,
    this.invitationInbox,
    this.measurement,
    this.measurementWarning,
  });
  final InvitationInbox? invitationInbox;
  final InstallerMeasurement? measurement;
  final String? measurementWarning;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bloomstep',
    debugShowCheckedModeBanner: false,
    theme: BloomstepTheme.light(),
    darkTheme: BloomstepTheme.dark(),
    home: HabitHome(
      invitationInbox: invitationInbox,
      measurement: measurement,
      measurementWarning: measurementWarning,
    ),
  );
}

class HabitHome extends StatefulWidget {
  const HabitHome({
    super.key,
    this.invitationInbox,
    this.measurement,
    this.measurementWarning,
    this.testIdentity,
    this.testOpenStore,
  });
  static const guestAccount = 'device-guest';
  final InvitationInbox? invitationInbox;
  final InstallerMeasurement? measurement;
  final String? measurementWarning;
  final IdentityService? testIdentity;
  final Future<GardenStore> Function(String account)? testOpenStore;
  @override
  State<HabitHome> createState() => _HabitHomeState();
}

class _HabitHomeState extends State<HabitHome> {
  IdentityService identity = IdentityService();
  GardenStore? store;
  SessionDiagnostics? diagnostics;
  AuthObservations? observations;
  bool busy = true;
  bool accountGarden = false;
  bool pendingAuthCleanup = false;
  Future<void>? returningToGuest;
  String? error;
  String? notice;

  @override
  void initState() {
    super.initState();
    if (!_testBuild &&
        (widget.testIdentity != null || widget.testOpenStore != null)) {
      throw StateError(
        'Profile test adapters are unavailable in release builds.',
      );
    }
    identity = widget.testIdentity ?? IdentityService();
    _restore();
  }

  Future<GardenStore> _open(String account) async {
    if (widget.testOpenStore != null) return widget.testOpenStore!(account);
    final directory = await getApplicationSupportDirectory();
    return GardenStore.open(p.join(directory.path, '$account.sqlite'), account);
  }

  void _writeError(String message) {
    debugPrint(message);
    if (mounted) setState(() => error = message);
  }

  Future<void> _observeProfile() async {
    try {
      await widget.measurement?.observe('signin_view');
    } catch (_) {
      _writeError(
        'Optional local sign-in-view observation failed. No server data was sent; planting and sign-in still work. Clear the installer receipt in profile Settings to stop observation.',
      );
    }
  }

  Future<void> _restore() async {
    try {
      final restored = await identity.restore();
      await _showGarden(authenticated: restored);
    } catch (e) {
      error =
          'Session could not be restored: $e. Your saved garden was not deleted.';
      try {
        await _showGarden(authenticated: false);
      } catch (storageError) {
        error = '$error\nYour device garden could not be opened: $storageError';
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _showGarden({
    required bool authenticated,
    bool authenticatedNow = false,
  }) async {
    if (authenticated && !identity.hasValidSession) {
      throw StateError('Your offline session has ended. Sign in again.');
    }
    final next = await _open(
      authenticated ? identity.account! : HabitHome.guestAccount,
    );
    SessionDiagnostics? nextDiagnostics;
    AuthObservations? nextObservations;
    try {
      if (authenticated) {
        nextDiagnostics = SessionDiagnostics(next, onWriteError: _writeError);
        nextObservations = AuthObservations(next, onWriteError: _writeError);
        await nextObservations.run(AuthStage.sessionEntry, () async {
          await nextDiagnostics!.start(authenticatedNow: authenticatedNow);
        });
      } else {
        await next.setSetting('analytics', 'false');
      }
    } catch (_) {
      nextObservations?.close();
      await nextDiagnostics?.close();
      await next.close();
      rethrow;
    }
    if (!mounted) {
      nextObservations?.close();
      await nextDiagnostics?.close();
      await next.close();
      return;
    }
    final previous = store;
    final previousDiagnostics = diagnostics;
    final previousObservations = observations;
    // Dismiss guest dialogs before changing ownership; a draft cannot save into
    // a different account after a browser callback returns.
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      store = next;
      accountGarden = authenticated;
      diagnostics = nextDiagnostics;
      observations = nextObservations;
      identity.observations = nextObservations;
    });
    nextDiagnostics?.attach();
    await WidgetsBinding.instance.endOfFrame;
    previousObservations?.close();
    await previousDiagnostics?.close();
    await previous?.close();
  }

  Future<void> _signIn() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await identity.signIn();
      pendingAuthCleanup = false;
      final count = (await store!.habits()).length;
      await _showGarden(authenticated: true, authenticatedNow: true);
      notice = count == 0
          ? null
          : 'Your $count device ${count == 1 ? 'habit is' : 'habits are'} kept separate. Nothing was transferred to your account.';
    } catch (e) {
      error = e is AuthFailure
          ? 'Sign-in did not complete: ${e.message} Your device garden is unchanged.'
          : 'Your account garden could not be opened: $e. Your device garden is unchanged.';
      if (!accountGarden) {
        try {
          await identity.signOut();
        } catch (cleanupError) {
          pendingAuthCleanup = true;
          error =
              '$error Saved authentication could not be cleared: $cleanupError';
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signedOut(String? warning, {bool authCleanupFailed = false}) {
    return returningToGuest ??= _returnToGuest(
      warning,
      authCleanupFailed: authCleanupFailed,
    ).whenComplete(() => returningToGuest = null);
  }

  Future<void> _returnToGuest(
    String? warning, {
    required bool authCleanupFailed,
  }) async {
    notice = null;
    error = warning;
    pendingAuthCleanup = authCleanupFailed;
    if (mounted) setState(() => busy = true);
    try {
      await _showGarden(authenticated: false);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _clearSavedSignIn() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await identity.signOut();
      pendingAuthCleanup = false;
      error = 'Saved sign-in cleared. Your device garden is unchanged.';
    } catch (e) {
      error =
          'Saved sign-in could not be cleared: $e. Do not share this OS account until cleanup succeeds.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _expire(String? reason) async {
    var cleanupFailed = false;
    var message =
        'Your offline session ended. Sign in again; your saved account garden was not deleted.';
    try {
      await identity.signOut();
    } catch (e) {
      cleanupFailed = true;
      message = '$message Saved authentication could not be cleared: $e';
    }
    if (reason != null) message = '$message\n$reason';
    await _signedOut(message, authCleanupFailed: cleanupFailed);
  }

  @override
  void dispose() {
    observations?.close();
    identity.observations = null;
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() async {
    try {
      await diagnostics?.close();
      await store?.close();
    } catch (e) {
      debugPrint('Garden cleanup failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = store;
    if (current == null) {
      return Scaffold(
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : SelectableText(error!),
        ),
      );
    }
    final garden = GardenScreen(
      key: ObjectKey(current),
      store: current,
      identity: accountGarden ? identity : null,
      deviceGuest: !accountGarden,
      testDisableServices: widget.testOpenStore != null,
      invitationInbox: accountGarden ? widget.invitationInbox : null,
      diagnostics: diagnostics,
      installerMeasurement: widget.measurement,
      onProfileShown: accountGarden || widget.measurement == null
          ? null
          : () => unawaited(_observeProfile()),
      onSignedOut: (warning) =>
          _signedOut(warning, authCleanupFailed: warning != null),
      profileBuilder: (signOut, manage) => ProfileSection(
        signedIn: accountGarden && identity.hasValidSession,
        profile: accountGarden ? identity.profile : null,
        configured: identity.configured,
        busy: busy,
        error: error ?? widget.measurementWarning,
        notice: notice,
        onSignIn: _signIn,
        onSignOut: signOut,
        onManage: manage,
        onClearSavedSignIn: pendingAuthCleanup ? _clearSavedSignIn : null,
      ),
    );
    return accountGarden
        ? SessionBoundary(
            key: ObjectKey(current),
            expiresAt: identity.sessionExpiresAt ?? DateTime.now(),
            isValid: () => identity.hasValidSession,
            onExpired: _expire,
            onCheckpoint: identity.checkpoint,
            child: garden,
          )
        : garden;
  }
}
