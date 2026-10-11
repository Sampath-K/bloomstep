import 'package:flutter/material.dart';

import '../../services/identity.dart';

class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.signedIn,
    required this.configured,
    required this.busy,
    required this.onSignIn,
    required this.onSignOut,
    this.profile,
    this.error,
    this.notice,
    this.onManage,
    this.onClearSavedSignIn,
  });
  final bool signedIn;
  final bool configured;
  final bool busy;
  final IdentityProfile? profile;
  final String? error;
  final String? notice;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignOut;
  final VoidCallback? onManage;
  final Future<void> Function()? onClearSavedSignIn;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.account_circle_outlined),
              const Text('Profile'),
              Text(
                signedIn ? 'Signed in' : 'Not signed in',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (signedIn && profile?.displayName != null)
                Text(profile!.displayName!),
              if (signedIn && profile?.email != null)
                SelectableText(profile!.email!),
              if (signedIn && profile?.provider != null)
                Text(profile!.provider!),
              TextButton.icon(
                onPressed: busy || (!signedIn && !configured)
                    ? null
                    : signedIn
                    ? onSignOut
                    : onSignIn,
                icon: Icon(signedIn ? Icons.logout : Icons.login),
                label: Text(
                  busy
                      ? signedIn
                            ? 'Updating profile...'
                            : 'Complete sign-in in your browser'
                      : signedIn
                      ? 'Sign out'
                      : 'Sign in with Microsoft or Google',
                ),
              ),
              if (onManage != null)
                IconButton(
                  tooltip: 'Settings and privacy',
                  onPressed: onManage,
                  icon: const Icon(Icons.settings_outlined),
                ),
            ],
          ),
          Text(
            signedIn
                ? 'Your account garden is private. You can keep growing offline.'
                : 'Plant without signing in. This device garden stays on this device; no sync or analytics.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!signedIn && !configured)
            const Text('Account sign-in is not configured in this build.'),
          if (!signedIn && configured)
            const Text(
              'Choose Microsoft personal account, Google or another enabled option in the system browser. Microsoft hosts Bloomstep sign-in at ciamlogin.com; Bloomstep never collects your password.',
            ),
          if (notice != null) Text(notice!),
          if (error != null)
            Semantics(liveRegion: true, child: SelectableText(error!)),
          if (onClearSavedSignIn != null)
            TextButton(
              onPressed: busy ? null : onClearSavedSignIn,
              child: const Text('Clear saved sign-in'),
            ),
        ],
      ),
    ),
  );
}
