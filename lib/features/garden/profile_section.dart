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
    this.compactSummary = false,
    this.detailsOnly = false,
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
  final bool compactSummary;
  final bool detailsOnly;

  Future<void> _runProfileAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    if (ModalRoute.of(context) is PopupRoute) {
      Navigator.of(context).pop();
    }
    await action();
  }

  String? get _displayName {
    final name = profile?.displayName?.trim();
    return name == null || name.isEmpty || name.toLowerCase() == 'unknown'
        ? null
        : name;
  }

  Widget _accountError() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Your account needs attention. Try signing in again.'),
      ExpansionTile(
        title: const Text('Details'),
        children: [Semantics(liveRegion: true, child: SelectableText(error!))],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (detailsOnly) return _detailsOnly(context);
    if (compactSummary) return _compactSummary(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: signedIn
            ? _signedInProfile(context)
            : _signedOutProfile(context),
      ),
    );
  }

  Widget _compactSummary(BuildContext context) {
    final name = _displayName;
    final initials = _initials(name);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  child: initials.isEmpty
                      ? const Icon(Icons.person_outline)
                      : Text(initials),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    signedIn ? name ?? 'Signed-in account' : 'Not signed in',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (signedIn && name == null)
              const Text("Your account doesn't include a name."),
            if (signedIn &&
                (onCopyDeviceGarden != null || onSwitchGarden != null))
              Semantics(
                label: 'Device garden stays separate. Switch any time.',
                child: const Text(
                  'Separate gardens; switch any time.',
                  maxLines: 2,
                ),
              ),
            if (!signedIn &&
                notice != null &&
                notice != 'Device garden stays separate; switch any time.')
              Semantics(liveRegion: true, child: Text(notice!)),
            if (!signedIn)
              const Text(
                'Your habits stay on this device. Sign in to use an account garden.',
              ),
          ],
        ),
      ),
    );
  }

  Widget _detailsOnly(BuildContext context) => Card(
    child: ExpansionTile(
      key: const ValueKey('profile-details'),
      title: const Text('Profile and garden details'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: signedIn
          ? _signedInDetails(context)
          : _signedOutDetails(context),
    ),
  );

  List<Widget> _signedInDetails(BuildContext context) => [
    if (notice != null &&
        notice != 'Device garden stays separate; switch any time.')
      Semantics(liveRegion: true, child: Text(notice!)),
    if (error != null) _accountError(),
    if (onCopyDeviceGarden != null)
      TextButton(
        onPressed: busy
            ? null
            : () => _runProfileAction(context, onCopyDeviceGarden!),
        child: const Text('Copy device habits to this account'),
      ),
    if (onSwitchGarden != null)
      TextButton(
        onPressed: busy
            ? null
            : () => _runProfileAction(context, onSwitchGarden!),
        child: const Text('View device garden'),
      ),
    if (onClearSavedSignIn != null)
      TextButton(
        onPressed: busy
            ? null
            : () => _runProfileAction(context, onClearSavedSignIn!),
        child: const Text('Clear saved sign-in'),
      ),
    TextButton(
      onPressed: busy ? null : () => _runProfileAction(context, onSignOut),
      child: Text(busy ? 'Updating profile...' : 'Sign out'),
    ),
  ];

  List<Widget> _signedOutDetails(BuildContext context) => [
    if (!configured)
      const Text('Account sign-in is not configured in this build.'),
    if (configured && !returningToAccount)
      const Text(
        'Choose Microsoft personal account, Google or another enabled option in the system browser. Budlark never collects your password.',
      ),
    TextButton.icon(
      onPressed: busy || (!configured && !returningToAccount)
          ? null
          : () => _runProfileAction(context, onSignIn),
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
    if (notice != null) Text(notice!),
    if (error != null) _accountError(),
    if (onClearSavedSignIn != null)
      TextButton(
        onPressed: busy
            ? null
            : () => _runProfileAction(context, onClearSavedSignIn!),
        child: const Text('Clear saved sign-in'),
      ),
  ];

  Widget _signedInProfile(BuildContext context) {
    final name = _displayName;
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
                      if (profile?.photoBytes != null)
                        ClipOval(child: _MemoryPhoto(profile: profile!))
                      else if (profile?.photoUrl case final photoUrl?)
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
                onPressed: busy
                    ? null
                    : () => _runProfileAction(context, onSignOut),
                icon: const Icon(Icons.logout),
                label: Text(busy ? 'Updating profile...' : 'Sign out'),
              ),
            ),
          ],
        ),
        if (name == null) const Text("Your account doesn't include a name."),
        if (onCopyDeviceGarden != null || onSwitchGarden != null)
          const Text('Device garden stays separate; switch any time.'),
        if (notice != null &&
            notice != 'Device garden stays separate; switch any time.')
          Semantics(liveRegion: true, child: Text(notice!)),
        if (onCopyDeviceGarden != null)
          TextButton(
            onPressed: busy
                ? null
                : () => _runProfileAction(context, onCopyDeviceGarden!),
            child: const Text('Copy device habits to this account'),
          ),
        if (onSwitchGarden != null)
          TextButton(
            onPressed: busy
                ? null
                : () => _runProfileAction(context, onSwitchGarden!),
            child: const Text('View device garden'),
          ),
        if (error != null) _accountError(),
        if (onClearSavedSignIn != null)
          TextButton(
            onPressed: busy
                ? null
                : () => _runProfileAction(context, onClearSavedSignIn!),
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
                : () => _runProfileAction(context, onSignIn),
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
          if (onManage != null && ModalRoute.of(context) is! PopupRoute)
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
          'Choose Microsoft personal account, Google or another enabled option in the system browser. Budlark never collects your password.',
        ),
      if (notice != null) Text(notice!),
      if (error != null) _accountError(),
      if (onClearSavedSignIn != null)
        TextButton(
          onPressed: busy
              ? null
              : () => _runProfileAction(context, onClearSavedSignIn!),
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

class _MemoryPhoto extends StatefulWidget {
  const _MemoryPhoto({required this.profile});
  final IdentityProfile profile;

  @override
  State<_MemoryPhoto> createState() => _MemoryPhotoState();
}

class _MemoryPhotoState extends State<_MemoryPhoto> {
  late ImageProvider _provider;

  void _replace() {
    _provider = ResizeImage(
      MemoryImage(widget.profile.photoBytes!),
      width: 112,
      height: 112,
    );
  }

  @override
  void initState() {
    super.initState();
    _replace();
  }

  @override
  void didUpdateWidget(_MemoryPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.photoBytes != widget.profile.photoBytes) {
      _provider.evict();
      _replace();
    }
  }

  @override
  void dispose() {
    _provider.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
    image: _provider,
    width: 56,
    height: 56,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}
