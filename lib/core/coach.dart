import 'dart:convert';

import 'models.dart';
import 'rules.dart';

const coachStateKey = 'quietCoach.v1';

class GardenBadge {
  const GardenBadge(this.id, this.name, this.message);
  final String id, name, message;
}

const badgeCatalog = [
  GardenBadge(
    'first-seed',
    'First seed',
    'You made room for one small beginning.',
  ),
  GardenBadge(
    'possibilities',
    'Growing possibilities',
    'Another tiny possibility has a place in your garden.',
  ),
  GardenBadge(
    'tiny-win',
    'Tiny step, real win',
    'You showed up for a tiny action. That counts.',
  ),
  GardenBadge(
    'roots',
    'Roots taking hold',
    'Three days of tiny steps. They never need to be in a row.',
  ),
  GardenBadge(
    'thoughtful',
    'Thoughtful gardener',
    'You paused to notice what helps your recipe fit.',
  ),
  GardenBadge(
    'making-yours',
    'Making it yours',
    'You adjusted your recipe to fit your life.',
  ),
];

List<String> eligibleBadges(
  List<Habit> habits, {
  required bool reflected,
  bool edited = false,
}) => [
  if (habits.isNotEmpty) 'first-seed',
  if (habits.length >= 2) 'possibilities',
  if (habits.any((h) => h.practiceCount > 0)) 'tiny-win',
  if (habits.any((h) => h.practiceCount >= 3)) 'roots',
  if (reflected) 'thoughtful',
  if (edited) 'making-yours',
];

enum CoachRule { friction, reflection, firstSeed, anotherSeed, anchor }

class CoachSuggestion {
  const CoachSuggestion(this.rule, this.message, this.action, {this.habitId});
  final CoachRule rule;
  final String message, action;
  final String? habitId;
}

CoachSuggestion nextCoach(List<Habit> habits, {required bool weeklyDue}) {
  final active = habits.where((h) => h.status == 'active').toList();
  for (final h in active) {
    if (h.lastReason != null) {
      return CoachSuggestion(
        CoachRule.friction,
        recipeDoctor(h.lastReason!),
        'Review my recipe',
        habitId: h.id,
      );
    }
  }
  if (habits.isEmpty) {
    return const CoachSuggestion(
      CoachRule.firstSeed,
      'One tiny action is enough to begin. Choose something that matters to you.',
      'Choose my tiny step',
    );
  }
  if (weeklyDue && active.any((h) => h.practiceCount > 0)) {
    final h = active.firstWhere((h) => h.practiceCount > 0);
    return CoachSuggestion(
      CoachRule.reflection,
      'Want to notice what made starting easier? A short reflection is optional.',
      'Reflect on my recipe',
      habitId: h.id,
    );
  }
  if (active.length < 3 && habits.any((h) => h.practiceCount >= 3)) {
    return const CoachSuggestion(
      CoachRule.anotherSeed,
      'If your tiny step feels easy, you can plant another. Keeping things small is just as good.',
      'Plant another',
    );
  }
  return CoachSuggestion(
    CoachRule.anchor,
    'Let your next anchor be the invitation. No need to practice right now.',
    'Review my recipe',
    habitId: active.isEmpty ? habits.first.id : active.first.id,
  );
}

class CoachExposure {
  const CoachExposure(this.rule, this.at, this.day);
  final CoachRule rule;
  final DateTime at;
  final String day;
}

class CoachState {
  CoachState({
    this.initialized = false,
    this.suggestions = true,
    this.reveals = true,
    Map<String, DateTime>? earned,
    List<CoachExposure>? exposures,
  }) : earned = Map.unmodifiable(earned ?? {}),
       exposures = List.unmodifiable(exposures ?? []);
  final bool initialized, suggestions, reveals;
  final Map<String, DateTime> earned;
  final List<CoachExposure> exposures;

  CoachState copyWith({
    bool? initialized,
    bool? suggestions,
    bool? reveals,
    Map<String, DateTime>? earned,
    List<CoachExposure>? exposures,
  }) => CoachState(
    initialized: initialized ?? this.initialized,
    suggestions: suggestions ?? this.suggestions,
    reveals: reveals ?? this.reveals,
    earned: earned ?? this.earned,
    exposures: exposures ?? this.exposures,
  );

  bool canSuggest(CoachRule rule, DateTime now) {
    if (!suggestions) return false;
    final recent = exposures.where(
      (e) => now.toUtc().difference(e.at) < const Duration(days: 7),
    );
    return recent.length < 3 &&
        !recent.any(
          (e) => e.day == localDate(now) || e.at.isAfter(now.toUtc()),
        ) &&
        !recent.any((e) => e.rule == rule);
  }

  CoachState exposed(CoachRule rule, DateTime now) => copyWith(
    exposures: [
      ...exposures.where(
        (e) => now.toUtc().difference(e.at) < const Duration(days: 7),
      ),
      CoachExposure(rule, now.toUtc(), localDate(now)),
    ],
  );

  String encode() => jsonEncode({
    'version': 1,
    'initialized': initialized,
    'suggestions': suggestions,
    'reveals': reveals,
    'earned': {
      for (final e in earned.entries) e.key: e.value.toIso8601String(),
    },
    'exposures': [
      for (final e in exposures)
        {'rule': e.rule.name, 'at': e.at.toIso8601String(), 'day': e.day},
    ],
  });

  static CoachState decode(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map<String, dynamic> ||
        raw['version'] != 1 ||
        raw['initialized'] is! bool ||
        raw['suggestions'] is! bool ||
        raw['reveals'] is! bool ||
        raw['earned'] is! Map<String, dynamic> ||
        raw['exposures'] is! List) {
      throw const FormatException(
        'Saved coach state has an unsupported format.',
      );
    }
    DateTime timestamp(Object? v) {
      if (v is! String || DateTime.tryParse(v) == null || !v.endsWith('Z')) {
        throw const FormatException('Invalid coach timestamp.');
      }
      return DateTime.parse(v);
    }

    final earned = <String, DateTime>{};
    for (final e in (raw['earned'] as Map<String, dynamic>).entries) {
      if (!badgeCatalog.any((b) => b.id == e.key)) {
        throw const FormatException('Unknown saved badge.');
      }
      earned[e.key] = timestamp(e.value);
    }
    final exposures = <CoachExposure>[];
    for (final e in raw['exposures'] as List) {
      if (e is! Map<String, dynamic> ||
          !CoachRule.values.any((r) => r.name == e['rule']) ||
          e['day'] is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(e['day'] as String)) {
        throw const FormatException('Invalid coach exposure.');
      }
      exposures.add(
        CoachExposure(
          CoachRule.values.byName(e['rule'] as String),
          timestamp(e['at']),
          e['day'] as String,
        ),
      );
    }
    if (exposures.length > 3) {
      throw const FormatException('Invalid coach exposure count.');
    }
    return CoachState(
      initialized: raw['initialized'] as bool,
      suggestions: raw['suggestions'] as bool,
      reveals: raw['reveals'] as bool,
      earned: earned,
      exposures: exposures,
    );
  }
}

class CoachUpdate {
  const CoachUpdate(this.state, this.newBadges);
  final CoachState state;
  final List<GardenBadge> newBadges;
}
