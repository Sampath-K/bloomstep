import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/automatic_updates.dart';

class UpdateStatus extends StatefulWidget {
  const UpdateStatus({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.controller,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final AutomaticUpdates? controller;

  @override
  State<UpdateStatus> createState() => _UpdateStatusState();
}

class _UpdateStatusState extends State<UpdateStatus> {
  AutomaticUpdates? updates;
  String? error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final directory = widget.controller == null
          ? await getApplicationSupportDirectory()
          : null;
      if (!mounted) return;
      updates =
          widget.controller ??
          AutomaticUpdates(
            preferences: File(
              p.join(directory!.path, 'updates', 'preferences.json'),
            ),
          );
      updates!.addListener(_changed);
      await updates!.start();
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'Automatic updates unavailable: $exception');
      }
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    updates?.removeListener(_changed);
    updates?.dispose();
    super.dispose();
  }

  Future<void> _details() => showDialog<void>(
    context: widget.navigatorKey.currentState!.overlay!.context,
    builder: (context) => ListenableBuilder(
      listenable: updates!,
      builder: (context, _) => AlertDialog(
        title: const Text('Automatic updates'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(updates!.status),
                const SizedBox(height: 16),
                const Text(
                  'Checks run when Bloomstep opens and every 24 hours while running. '
                  'Your work, garden and sign-in are not interrupted. '
                  'The unsigned Inno preview is never automatically executed. '
                  'For signed MSIX installations, Windows checks on launch and in the background; '
                  'manage those updates in Windows Settings. Offline, disabled or policy-blocked clients may remain behind.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Automatic release checks'),
                  value: updates!.enabled,
                  onChanged: updates!.savingPreference
                      ? null
                      : updates!.setEnabled,
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (updates!.available != null)
            TextButton(
              onPressed: () async {
                try {
                  if (!await launchUrl(
                    updates!.available!.releasePage,
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw StateError('The release page could not be opened.');
                  }
                } catch (exception) {
                  if (mounted) setState(() => error = '$exception');
                }
              },
              child: const Text('View release (manual installation)'),
            ),
          TextButton(
            onPressed: updates!.checking || !updates!.enabled
                ? null
                : updates!.check,
            child: const Text('Check now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(child: widget.child),
      Material(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    error ??
                        updates?.status ??
                        'Starting automatic release checks...',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: updates == null ? null : _details,
                  child: const Text('Update settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
