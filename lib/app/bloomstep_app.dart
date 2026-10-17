import 'dart:async';
import 'dart:io';

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
import '../services/analytics_sandbox.dart';
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
  AnalyticsSandbox? sandbox;
  bool busy = true;
  bool accountGarden = false;
  bool autoInviteFirstHabit = false;
  final Set<String> invitedGardens = {};
  bool pendingAuthCleanup = false;
  Future<void>? returningToGuest;
  String? error;
  String? notice;
  int deviceHabitCount = 0;
  int contentRevision = 0;

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
    } catch (_) {
      error = 'Couldn’t restore your account garden. Your saved garden wasn’t deleted.';
      try {
        await _showGarden(authenticated: false);
      } catch (_) {
        error =
            '$error Your device garden couldn’t be opened. Your saved garden wasn’t deleted.';
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
    AnalyticsSandbox? nextSandbox;
    try {
      if (authenticated) {
        final visibleDevice = !accountGarden ? store : null;
        final deviceExists =
            visibleDevice != null ||
            await File(
              p.join(
                p.dirname(next.storagePath),
                '${HabitHome.guestAccount}.sqlite',
              ),
            ).exists();
        deviceHabitCount = 0;
        if (deviceExists) {
          final device = visibleDevice ?? await _open(HabitHome.guestAccount);
          try {
            deviceHabitCount = (await device.habits()).length;
          } finally {
            // The visible guest store closes only after ownership changes.
            if (visibleDevice == null) await device.close();
          }
        }
        nextDiagnostics = SessionDiagnostics(next, onWriteError: _writeError);
        nextObservations = AuthObservations(next, onWriteError: _writeError);
        nextSandbox = analyticsSandboxEnabled
            ? AnalyticsSandbox(
                productConsent: () async =>
                    await next.setting('analytics') == 'true',
                onError: _writeError,
              )
            : null;
        await nextObservations.run(AuthStage.sessionEntry, () async {
          await nextDiagnostics!.start(authenticatedNow: authenticatedNow);
        });
      } else {
        await next.setSetting('analytics', 'false');
      }
    } catch (_) {
      nextObservations?.close();
      await nextSandbox?.close();
      await nextDiagnostics?.close();
      await next.close();
      rethrow;
    }
    if (!mounted) {
      nextObservations?.close();
      await nextSandbox?.close();
      await nextDiagnostics?.close();
      await next.close();
      return;
    }
    final previous = store;
    final previousDiagnostics = diagnostics;
    final previousObservations = observations;
    final previousSandbox = sandbox;
    // Dismiss guest dialogs before changing ownership; a draft cannot save into
    // a different account after a browser callback returns.
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      store = next;
      accountGarden = authenticated;
      autoInviteFirstHabit =
          !invitedGardens.contains(next.account) &&
          !(authenticated && deviceHabitCount > 0);
      diagnostics = nextDiagnostics;
      observations = nextObservations;
      sandbox = nextSandbox;
      identity.observations = nextObservations;
      notice = authenticated
          ? _accountGardenNotice()
          : 'Viewing your device garden.';
    });
    nextDiagnostics?.attach();
    nextSandbox?.attach();
    await WidgetsBinding.instance.endOfFrame;
    previousObservations?.close();
    await previousSandbox?.close();
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
      await _showGarden(authenticated: true, authenticatedNow: true);
    } catch (e) {
      error = e is AuthFailure
          ? 'Sign-in didn’t complete. Your device garden is unchanged.'
          : 'Couldn’t open your account garden. Your device garden is unchanged.';
      if (!accountGarden) {
        try {
          await identity.signOut();
        } catch (cleanupError) {
          pendingAuthCleanup = true;
          error =
              '$error Saved sign-in may remain on this device. Clear it before sharing this device.';
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _accountGardenNotice() =>
      'Device garden stays separate; switch any time.';

  Future<void> _switchGarden() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await _showGarden(authenticated: !accountGarden);
    } catch (e) {
      _writeError("Couldn't switch gardens. Try again.");
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _copyDeviceGarden() async {
    if (busy || !accountGarden || !identity.hasValidSession) return;
    final destination = store!;
    final owner = destination.account;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Copy to your account?'),
        content: Text(
          'Device habits, check-ins, and reflections copy to your account and '
          'may sync. Originals stay on this device; existing account habits '
          'are unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    GardenStore? device;
    try {
      device = await _open(HabitHome.guestAccount);
      final copied = await destination.copyDeviceGardenFrom(
        device,
        authorized: () =>
            mounted &&
            accountGarden &&
            identical(store, destination) &&
            identity.hasValidSession &&
            identity.account == owner,
      );
      if (mounted && identical(store, destination)) {
        setState(() {
          contentRevision++;
          notice =
              'Copied $copied ${copied == 1 ? 'habit' : 'habits'}. '
              'Originals stay on this device.';
        });
      }
    } catch (_) {
      _writeError("Couldn't copy device habits. No changes were saved.");
    } finally {
      try {
        await device?.close();
      } catch (_) {
        _writeError(
          "Couldn't close the device garden. Copies may already be saved; "
          "retrying won't create duplicates.",
        );
      }
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
      if (accountGarden || store == null) {
        await _showGarden(authenticated: false);
      }
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
    } catch (_) {
      error = 'Saved sign-in couldn’t be cleared. Keep this Windows account private until you can clear it.';
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
    } catch (_) {
      cleanupFailed = true;
      message =
          '$message Saved sign-in may remain on this device. Clear it before sharing this device.';
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
      await sandbox?.close();
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
    Widget buildProfileSection(
      Future<void> Function() signOut,
      VoidCallback manage, {
      bool compactSummary = false,
      bool detailsOnly = false,
    }) => ProfileSection(
      signedIn: accountGarden && identity.hasValidSession,
      profile: accountGarden ? identity.profile : null,
      configured: identity.configured,
      busy: busy,
      error: error ?? widget.measurementWarning,
      notice: notice,
      onSignIn: identity.hasValidSession ? _switchGarden : _signIn,
      onSignOut: signOut,
      onManage: manage,
      onClearSavedSignIn: pendingAuthCleanup ? _clearSavedSignIn : null,
      onCopyDeviceGarden: accountGarden && deviceHabitCount > 0
          ? _copyDeviceGarden
          : null,
      onSwitchGarden: accountGarden ? _switchGarden : null,
      returningToAccount: !accountGarden && identity.hasValidSession,
      compactSummary: compactSummary,
      detailsOnly: detailsOnly,
    );
    final garden = GardenScreen(
      key: ObjectKey(current),
      store: current,
      identity: accountGarden ? identity : null,
      deviceGuest: !accountGarden,
      autoInviteFirstHabit: autoInviteFirstHabit,
      firstHabitInvitationReady: !busy,
      contentRevision: contentRevision,
      onFirstHabitInvited: () => invitedGardens.add(current.account),
      testDisableServices: widget.testOpenStore != null,
      invitationInbox: accountGarden ? widget.invitationInbox : null,
      diagnostics: diagnostics,
      installerMeasurement: widget.measurement,
      analyticsSandbox: sandbox,
      onProfileShown: accountGarden || widget.measurement == null
          ? null
          : () => unawaited(_observeProfile()),
      onSignedOut: (warning) =>
          _signedOut(warning, authCleanupFailed: warning != null),
      profileBuilder: buildProfileSection,
      profileSummaryBuilder: (signOut, manage) =>
          buildProfileSection(signOut, manage, compactSummary: true),
      profileDetailsBuilder: (signOut, manage) =>
          buildProfileSection(signOut, manage, detailsOnly: true),
    );
    return identity.hasValidSession
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
