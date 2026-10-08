enum CheckInResult { did, didMore, notToday }

enum GrowthStage { seed, sprout, sapling, budding, bloom }

String localDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class Habit {
  const Habit({
    required this.id,
    required this.aspiration,
    required this.anchor,
    required this.behavior,
    required this.celebration,
    required this.species,
    required this.stage,
    required this.status,
    required this.practiceCount,
    required this.recentPractice,
    this.today,
    this.todayReason,
    this.lastReason,
  });
  final String id, aspiration, anchor, behavior, celebration, species, status;
  final GrowthStage stage;
  final int practiceCount, recentPractice;
  final CheckInResult? today;
  final String? todayReason, lastReason;

  String get recipe => 'After I $anchor, I will $behavior.';
}

class StarterRecipe {
  const StarterRecipe(
    this.aspiration,
    this.anchor,
    this.behavior,
    this.celebration,
  );
  final String aspiration, anchor, behavior, celebration;
}

const starterRecipes = [
  StarterRecipe(
    'Calm',
    'pour my morning drink',
    'take one slow breath',
    'relax my shoulders and smile',
  ),
  StarterRecipe(
    'Focus',
    'open my laptop',
    'write my one next step',
    'say "I have a starting point"',
  ),
  StarterRecipe(
    'Health',
    'brush my teeth',
    'stretch my arms once',
    'give myself a thumbs up',
  ),
  StarterRecipe(
    'Learning',
    'sit down with a book',
    'read one sentence',
    'say "I learned something"',
  ),
  StarterRecipe(
    'Connection',
    'finish lunch',
    'send one kind sentence',
    'put my hand on my heart',
  ),
];
