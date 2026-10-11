import 'package:flutter/material.dart';

import '../../core/coach.dart';

class BadgeMoment extends StatelessWidget {
  const BadgeMoment({
    super.key,
    required this.badges,
    this.reducedMotion = false,
  });
  final List<GardenBadge> badges;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      liveRegion: true,
      label:
          'A small surprise. ${badges.map((b) => '${b.name}. ${b.message}').join(' ')}',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome_outlined),
            const SizedBox(height: 8),
            Text(
              'A small surprise',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final badge in badges) ...[
              const SizedBox(height: 8),
              Text(badge.name, style: Theme.of(context).textTheme.titleLarge),
              Text(badge.message),
            ],
          ],
        ),
      ),
    );
    if (reducedMotion || MediaQuery.disableAnimationsOf(context)) {
      return content;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: content,
    );
  }
}

class BadgeReveal extends StatelessWidget {
  const BadgeReveal({
    super.key,
    required this.badges,
    required this.onDismiss,
    this.reducedMotion = false,
  });
  final List<GardenBadge> badges;
  final VoidCallback onDismiss;
  final bool reducedMotion;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BadgeMoment(badges: badges, reducedMotion: reducedMotion),
          TextButton(
            onPressed: onDismiss,
            child: const Text('Keep growing quietly'),
          ),
        ],
      ),
    ),
  );
}

class BadgeCollection extends StatelessWidget {
  const BadgeCollection({super.key, required this.state});
  final CoachState state;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Small moments, saved on this device. No ranks, deadlines or streaks.',
      ),
      const SizedBox(height: 12),
      if (state.earned.isEmpty)
        const Text('Your small beginnings have a place here when they happen.'),
      for (final b in badgeCatalog.where((b) => state.earned.containsKey(b.id)))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const ExcludeSemantics(
            child: Icon(Icons.local_florist_outlined),
          ),
          title: Text(b.name),
          subtitle: Text(b.message),
        ),
    ],
  );
}

class CoachCard extends StatelessWidget {
  const CoachCard({
    super.key,
    required this.suggestion,
    required this.onAction,
    required this.onDismiss,
  });
  final CoachSuggestion suggestion;
  final VoidCallback onAction, onDismiss;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A gentle invitation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(suggestion.message),
          Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: onAction, child: Text(suggestion.action)),
              TextButton(onPressed: onDismiss, child: const Text('Later')),
            ],
          ),
        ],
      ),
    ),
  );
}
