import 'models.dart';

class WeeklyHabitStory {
  const WeeklyHabitStory({
    required this.id,
    required this.aspiration,
    required this.species,
    required this.stage,
    required this.status,
    required this.practiceDays,
    required this.suggestion,
  });

  final String id;
  final String aspiration;
  final String species;
  final GrowthStage stage;
  final String status;
  final int practiceDays;
  final String suggestion;

  bool get isEvergreen => status == 'graduated';

  Map<String, Object?> toJson() => {
    'aspiration': aspiration,
    'species': species,
    'stage': stage.name,
    'inEvergreenGrove': isEvergreen,
    'practiceDays': practiceDays,
    'suggestion': suggestion,
  };
}

class WeeklyGardenStory {
  const WeeklyGardenStory({
    required this.weekStart,
    required this.through,
    required this.habits,
  });

  final String weekStart;
  final String through;
  final List<WeeklyHabitStory> habits;

  int get practiceDays =>
      habits.fold(0, (total, habit) => total + habit.practiceDays);

  int get evergreenCount => habits.where((habit) => habit.isEvergreen).length;

  Map<String, Object?> toJson() => {
    'weekStartLocalDate': weekStart,
    'throughLocalDate': through,
    'practiceDays': practiceDays,
    'evergreenGroveCount': evergreenCount,
    'habits': habits.map((habit) => habit.toJson()).toList(),
  };
}
