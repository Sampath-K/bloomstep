import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/garden_store.dart';
import '../features/garden/garden_screen.dart';
import '../services/identity.dart';
import '../services/invitation_intent.dart';
import '../services/session_diagnostics.dart';
import '../services/installer_measurement.dart';
import 'theme.dart';
import 'session_boundary.dart';

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
    home: SignInScreen(
      invitationInbox: invitationInbox,
      measurement: measurement,
      measurementWarning: measurementWarning,
    ),
  );
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    this.invitationInbox,
    this.measurement,
    this.measurementWarning,
  });
  final InvitationInbox? invitationInbox;
  final InstallerMeasurement? measurement;
  final String? measurementWarning;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final identity = IdentityService();
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    _restore();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      try {
        await widget.measurement?.observe('signin_view');
      } catch (_) {
        if (mounted) {
          setState(
            () => error = 'Optional local sign-in-view observation failed. No server data was sent; sign-in still works. Clear the installer receipt below to stop observation.',
          );
        }
      }
    });
  }

  Future<void> _restore() async {
    try {
      if (await identity.restore()) await _enter();
    } catch (e) {
      if (mounted) setState(() => error = 'Session could not be restored: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _enter({bool authenticatedNow = false}) async {
    if (!identity.hasValidSession) {
      throw StateError('Your offline session has ended. Sign in again.');
    }
    final directory = await getApplicationSupportDirectory();
    final store = await GardenStore.open(
      p.join(directory.path, '${identity.account!}.sqlite'),
      identity.account!,
    );
    if (!mounted) {
      await store.close();
      return;
    }
    final diagnostics = SessionDiagnostics(
      store,
      onWriteError: (message) {
        if (mounted) {
          setState(() => error = message);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
        debugPrint(message);
      },
    );
    try {
      await diagnostics.start(authenticatedNow: authenticatedNow);
      diagnostics.attach();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SessionBoundary(
            expiresAt: identity.sessionExpiresAt!,
            isValid: () => identity.hasValidSession,
            onExpired: _expire,
            onCheckpoint: identity.checkpoint,
            child: GardenScreen(
              store: store,
              identity: identity,
              invitationInbox: widget.invitationInbox,
              diagnostics: diagnostics,
              installerMeasurement: widget.measurement,
            ),
          ),
        ),
      );
    } finally {
      await diagnostics.close();
      await store.close();
    }
  }

  Future<void> _expire(String? reason) async {
    String message =
        'Your offline session ended. Sign in again; your saved garden was not deleted.';
    try {
      await identity.signOut();
    } catch (error) {
      message =
          'Your session ended, but saved authentication could not be cleared: $error';
    }
    if (reason != null) message = '$message\n\n$reason';
    if (!mounted) return;
    setState(() => error = message);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _signIn() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await identity.signIn();
      await _enter(authenticatedNow: true);
    } catch (e) {
      if (mounted) setState(() => error = 'Sign-in did not complete: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.local_florist_outlined,
                size: 88,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Bloomstep',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'One tiny step. A garden that grows with you.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              const Text(
                'Your garden is private. Sign in to plant, celebrate and keep it safe across devices.',
              ),
              const SizedBox(height: 16),
              if (!identity.configured)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Preview build - sign-in is not yet configured.\n\nThe personal identity tenant and cloud service must be provisioned before this app can be used. This is not the released MVP.',
                    ),
                  ),
                ),
              if (error != null) SelectableText(error!),
              if (widget.measurementWarning != null)
                SelectableText(widget.measurementWarning!),
              if (widget.measurement != null)
                TextButton(
                  onPressed: () async {
                    try {
                      await widget.measurement!.clear();
                      if (mounted) {
                        setState(
                          () => error = 'Installer receipt removed. No further local observations; nothing was sent.',
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => error = 'Installer receipt could not be removed. Clear the per-user Bloomstep measurement file manually; sign-in still works.',
                        );
                      }
                    }
                  },
                  child: const Text(
                    'Clear optional installer observation receipt',
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: busy || !identity.configured ? null : _signIn,
                icon: const Icon(Icons.login),
                label: Text(
                  busy ? 'Opening your garden...' : 'Sign in securely',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Microsoft personal accounts, Google and email options depend on the configured identity provider. Your provider handles its password and account consent in the system browser; Bloomstep never collects your password.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
