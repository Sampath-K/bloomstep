import 'package:flutter/material.dart';

class ReminderObservationControls extends StatelessWidget {
  const ReminderObservationControls({
    super.key,
    required this.analyticsEnabled,
    required this.optedIn,
    required this.onChanged,
  });

  final bool analyticsEnabled, optedIn;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    title: const Text('Observe my app reminder preference (optional)'),
    value: analyticsEnabled && optedIn,
    onChanged: analyticsEnabled && onChanged != null
        ? (value) => onChanged!(value == true)
        : null,
    subtitle: Text(
      'Disclosure version 1. Separate fresh choice, off by default; existing product-event consent does not include this observation. '
      'After you explicitly turn app reminders on, record a random episode/consent ID, fixed platform and dates; record an explicit app disable or a confirmed preference followup after 30 days. '
      'This is not Windows permission, delivery or lifetime tracking. No later observation means unknown, not a successful no-disable outcome. '
      'No habit text, contacts or location. Revoking clears local observation state; previously synced events follow account deletion and retention rules.'
      '${analyticsEnabled ? '' : ' Enable product event counts first to make this separate choice.'}',
    ),
  );
}
