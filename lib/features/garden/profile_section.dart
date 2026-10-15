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
    this.onCopyDeviceGarden,
    this.onSwitchGarden,
    this.returningToAccount = false,
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
  final Future<void> Function()? onCopyDeviceGarden;
  final Future<void> Function()? onSwitchGarden;
  final bool returningToAccount;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: signedIn ? _signedInProfile(context) : _signedOutProfile(context),
    ),
  );

  Widget _signedInProfile(BuildContext context) {
    final name = profile?.displayName;
    final initials = _initials(name);
    final fallback = initials.isEmpty
        ? const Icon(Icons.person_outline)
        : Text(initials, style: Theme.of(context).textTheme.titleMedium);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              image: true,
              label: name == null
                  ? 'Account avatar'
                  : 'Account avatar for $name',
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .secondaryContainer,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      fallback,
                      if (profile?.photoUrl case final photoUrl?)
                        ClipOval(
                          child: Image.network(
                            photoUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name ?? 'Signed-in account',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: TextButton.icon(
                onPressed: busy ? null : onSignOut,
                icon: const Icon(Icons.logout),
                label: Text(busy ? 'Updating profile...' : 'Sign out'),
              ),
            ),
          ],
        ),
        if (name == null)
          const Text('Your sign-in provider did not supply a name.'),
        if (notice != null) Semantics(liveRegion: true, child: Text(notice!)),
        if (onCopyDeviceGarden != null)
          TextButton(
            onPressed: busy ? null : onCopyDeviceGarden,
            child: const Text('Copy device habits to this account'),
          ),
        if (onSwitchGarden != null)
          TextButton(
            onPressed: busy ? null : onSwitchGarden,
            child: const Text('View device garden'),
          ),
        if (error != null)
          Semantics(liveRegion: true, child: SelectableText(error!)),
        if (onClearSavedSignIn != null)
          TextButton(
            onPressed: busy ? null : onClearSavedSignIn,
            child: const Text('Clear saved sign-in'),
          ),
      ],
    );
  }

  Widget _signedOutProfile(BuildContext context) => Column(
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
            returningToAccount ? 'Viewing device garden' : 'Not signed in',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          TextButton.icon(
            onPressed: busy || (!configured && !returningToAccount)
                ? null
                : onSignIn,
            icon: const Icon(Icons.login),
            label: Text(
              busy
                  ? returningToAccount
                        ? 'Opening account garden...'
                        : 'Complete sign-in in your browser'
                  : returningToAccount
                  ? 'Return to account garden'
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
        'Plant without signing in. This device garden stays on this device; no sync or analytics.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (!configured)
        const Text('Account sign-in is not configured in this build.'),
      if (configured && !returningToAccount)
        const Text(
          'Choose Microsoft personal account, Google or another enabled option in the system browser. Bloomstep never collects your password.',
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
  );

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '';
    final parts = name.trim().split(RegExp(r'\s+'));
    final first = parts.first.runes.first;
    final last = parts.length > 1 ? parts.last.runes.first : null;
    return String.fromCharCode(first) +
        (last == null ? '' : String.fromCharCode(last));
  }
}
