import 'package:flutter/material.dart';

class GardenScreen extends StatelessWidget {
  const GardenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bloomstep')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.spa_outlined, size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Your garden is ready to grow', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Plant your first tiny habit to begin.',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: null,
        icon: const Icon(Icons.add),
        label: const Text('Plant a habit'),
      ),
    );
  }
}
