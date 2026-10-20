import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'plant_art.dart';

class SignInWelcome extends StatelessWidget {
  const SignInWelcome({
    super.key,
    required this.busy,
    required this.configured,
    required this.onSignIn,
    required this.onSettings,
    this.error,
  });

  final bool busy, configured;
  final VoidCallback onSignIn, onSettings;
  final String? error;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(
          tooltip: 'Settings and privacy',
          onPressed: busy ? null : onSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 180,
                height: 200,
                child: PlantArt(stage: GrowthStage.sprout, species: 'Fern'),
              ),
              Semantics(
                header: true,
                child: Text('Your tiny garden', style: Theme.of(context).textTheme.headlineMedium),
              ),
              const SizedBox(height: 12),
              const Text('Your garden, synced and safe across devices.'),
              const SizedBox(height: 24),
              Semantics(
                hint: 'Microsoft, Google or email code in your browser',
                child: FilledButton(
                  onPressed: busy || !configured ? null : onSignIn,
                  child: const Text('Sign in to grow'),
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator()),
                ),
              if (error != null || !configured)
                ExpansionTile(
                  title: const Text('More'),
                  children: [
                    Text(error ?? 'Sign-in is not configured in this build. Contact support.'),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
