import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/analytics_sandbox.dart';

class AnalyticsSandboxControls extends StatefulWidget {
  const AnalyticsSandboxControls({super.key, required this.sandbox});
  final AnalyticsSandbox sandbox;
  @override
  State<AnalyticsSandboxControls> createState() => _SandboxControlsState();
}

class _SandboxControlsState extends State<AnalyticsSandboxControls> {
  bool consent = false;
  String status = 'No vendors loaded. Separate fresh consent for this session.';
  final referral = TextEditingController();
  @override
  void dispose() {
    unawaited(widget.sandbox.consentChanged(false));
    referral.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      CheckboxListTile(
        title: const Text('Staging only: Aptabase and Sentry'),
        subtitle: const Text(
          'Requires product-event consent too. Sends fixed staging events and '
          'scrubbed Dart error categories to configured vendors; no habit text, '
          'identity, messages, stacks or native crashes. Off in release builds. '
          'Revoking discards queued events; in-flight requests cannot be recalled.',
        ),
        value: consent,
        onChanged: (value) async {
          await widget.sandbox.consentChanged(value == true);
          final active = await widget.sandbox.allowed();
          if (mounted) {
            setState(() {
              consent = active;
              status = active
                  ? 'Consent enabled; missing vendor keys disable that vendor.'
                  : 'Off. Enable product-event consent before this separate choice.';
            });
          }
        },
      ),
      TextField(
        controller: referral,
        decoration: const InputDecoration(
          labelText: 'Website referral code (BS-SANDBOX)',
        ),
      ),
      TextButton(
        onPressed: () async {
          try {
            await widget.sandbox.referral(referral.text.trim());
            if (mounted) {
              setState(
                () => status = 'Referral test requested only if both consents and Aptabase are active; no delivery claim.',
              );
            }
          } catch (error) {
            if (mounted) setState(() => status = '$error');
          }
        },
        child: const Text('Link shared test campaign'),
      ),
      Text(status),
    ],
  );
}
