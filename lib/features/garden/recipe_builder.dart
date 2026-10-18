import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'plant_art.dart';

class RecipeDraft {
  RecipeDraft(
    this.aspiration,
    this.anchor,
    this.behavior,
    this.celebration,
    this.species, {
    this.templateCategory,
    this.celebrationPracticed = false,
  });
  final String aspiration, anchor, behavior, celebration, species;
  final String? templateCategory;
  final bool celebrationPracticed;
}

class RecipeBuilder extends StatefulWidget {
  const RecipeBuilder({super.key, this.habit});
  final Habit? habit;
  @override
  State<RecipeBuilder> createState() => _RecipeBuilderState();
}

class PlantedRecipeDialog extends StatelessWidget {
  const PlantedRecipeDialog({
    super.key,
    required this.habit,
    this.reducedMotion = false,
  });
  final Habit habit;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your seed is planted'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: SizedBox(
                width: 144,
                height: 144,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Transform.scale(
                    scale: 1.5,
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: SeedGrowthPreview(
                        species: habit.species,
                        reducedMotion: reducedMotion,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'After I ${habit.anchor}, I will ${habit.behavior}. '
              'Then I celebrate: ${habit.celebration}.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Try it when your moment comes. Practicing now is optional.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('See my garden'),
      ),
    ],
  );
}

class SeedGrowthPreview extends StatefulWidget {
  const SeedGrowthPreview({
    super.key,
    required this.species,
    required this.reducedMotion,
  });
  final String species;
  final bool reducedMotion;

  @override
  State<SeedGrowthPreview> createState() => _SeedGrowthPreviewState();
}

class _SeedGrowthPreviewState extends State<SeedGrowthPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController growth = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool get reduce =>
      widget.reducedMotion || MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduce) {
      growth.stop();
      growth.value = 1;
    } else if (growth.value == 0 && !growth.isAnimating) {
      growth.forward();
    }
  }

  @override
  void didUpdateWidget(SeedGrowthPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (reduce) {
      growth.stop();
      growth.value = 1;
    }
  }

  @override
  void dispose() {
    growth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Seed planted. Tiny actions and practice help your plant grow.',
    child: ExcludeSemantics(
      child: reduce
          ? PlantArt(
              key: const ValueKey('growth-static-sprout'),
              stage: GrowthStage.sprout,
              species: widget.species,
            )
          : AnimatedBuilder(
              animation: growth,
              builder: (context, _) {
                final progress = Curves.easeInOutCubic.transform(growth.value);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: 1 - progress,
                      child: PlantArt(
                        key: const ValueKey('growth-seed'),
                        stage: GrowthStage.seed,
                        species: widget.species,
                      ),
                    ),
                    Opacity(
                      key: const ValueKey('growth-sprout-opacity'),
                      opacity: progress,
                      child: Transform.scale(
                        alignment: Alignment.bottomCenter,
                        scale: .2 + .8 * progress,
                        child: PlantArt(
                          stage: GrowthStage.sprout,
                          species: widget.species,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    ),
  );
}

class _RecipeBuilderState extends State<RecipeBuilder> {
  final form = GlobalKey<FormState>();
  final scroll = ScrollController();
  late final TextEditingController aspiration, anchor, behavior, celebration;
  var species = 'Cosmos';
  bool practiced = false;
  bool celebrationObserved = false;
  int step = 0;
  final customFocus = List.generate(3, (_) => FocusNode());
  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    aspiration = TextEditingController(text: h?.aspiration ?? 'Calm');
    anchor = TextEditingController(text: h?.anchor);
    behavior = TextEditingController(text: h?.behavior);
    celebration = TextEditingController(text: h?.celebration);
    species = h?.species ?? 'Cosmos';
  }

  @override
  void dispose() {
    scroll.dispose();
    for (final focus in customFocus) {
      focus.dispose();
    }
    for (final controller in [aspiration, anchor, behavior, celebration]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.habit == null ? _pickerDialog(context) : _editingDialog(context);

  bool get complete => [aspiration, anchor, behavior, celebration].every(
    (field) => field.text.trim().isNotEmpty && field.text.trim().length <= 200,
  );

  void save() {
    if (!complete) return;
    if (widget.habit != null && !form.currentState!.validate()) return;
    final matching = starterRecipes.where(
      (recipe) =>
          recipe.aspiration == aspiration.text.trim() &&
          recipe.anchor == anchor.text.trim() &&
          recipe.behavior == behavior.text.trim() &&
          recipe.celebration == celebration.text.trim(),
    );
    Navigator.pop(
      context,
      RecipeDraft(
        aspiration.text.trim(),
        anchor.text.trim(),
        behavior.text.trim(),
        celebration.text.trim(),
        species,
        templateCategory: matching.isEmpty
            ? null
            : matching.first.aspiration.toLowerCase(),
        celebrationPracticed: celebrationObserved,
      ),
    );
  }

  void _next() {
    final current = [anchor, behavior, celebration][step];
    if (current.text.trim().isEmpty || current.text.trim().length > 200) return;
    if (step == 2) {
      save();
      return;
    }
    if (scroll.hasClients) scroll.jumpTo(0);
    setState(() => step++);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) customFocus[step].requestFocus();
    });
  }

  Widget _pickerDialog(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fields = [anchor, behavior, celebration];
    final current = fields[step];
    final labels = ['After I...', 'I will...', 'Then I celebrate by...'];
    final choices = [
      for (final recipe in starterRecipes)
        [recipe.anchor, recipe.behavior, recipe.celebration][step],
    ];
    final recommendedCelebration = starterRecipes
        .firstWhere(
          (recipe) => recipe.aspiration == aspiration.text.trim(),
          orElse: () => starterRecipes.first,
        )
        .celebration;
    final icons = [
      Icons.wb_sunny_outlined,
      Icons.laptop_outlined,
      Icons.spa_outlined,
      Icons.menu_book_outlined,
      Icons.favorite_outline,
    ];
    final canContinue =
        current.text.trim().isNotEmpty && current.text.trim().length <= 200;
    final preview =
        'After I ${anchor.text.isEmpty ? '[moment]' : anchor.text}, '
        'I will ${behavior.text.isEmpty ? '[tiny action]' : behavior.text}. '
        'Then I celebrate: ${celebration.text.isEmpty ? '[celebration]' : celebration.text}.';
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${step + 1} of 3',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              [
                'Choose a moment',
                'Choose a tiny action',
                'Choose a celebration',
              ][step],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          controller: scroll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: (step + 1) / 3),
              const SizedBox(height: 12),
              Text(
                [
                  'Pick a daily routine, or write your own.',
                  'Pick one small action, or write your own.',
                  'Pick a gesture or phrase. Practicing is optional.',
                ][step],
              ),
              const SizedBox(height: 12),
              Text(
                'Write my own',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: ValueKey(
                  [
                    'custom-anchor',
                    'custom-action',
                    'custom-celebration',
                  ][step],
                ),
                controller: current,
                focusNode: customFocus[step],
                maxLength: 200,
                textInputAction: step < 2
                    ? TextInputAction.next
                    : TextInputAction.done,
                decoration: InputDecoration(
                  labelText: labels[step],
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: [
                    'put my cup away',
                    'stretch one finger',
                    'whisper well done',
                  ][step],
                ),
                onFieldSubmitted: (_) => _next(),
                onChanged: (_) => setState(() {
                  practiced = false;
                  celebrationObserved = false;
                }),
              ),
              if (current.text.trim().length > 200 ||
                  (step == 2 && canContinue && !complete))
                Semantics(
                  liveRegion: true,
                  child: Text(
                    current.text.trim().length > 200
                        ? 'Keep this choice to 200 characters or fewer.'
                        : 'Add every part of your recipe before planting.',
                  ),
                ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth >= 480
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < choices.length; i++)
                        SizedBox(
                          width: width,
                          child: Semantics(
                            selected: current.text == choices[i],
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.all(14),
                                minimumSize: const Size(0, 68),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                backgroundColor: current.text == choices[i]
                                    ? colors.primaryContainer
                                    : null,
                              ),
                              onPressed: () => setState(() {
                                FocusScope.of(context).unfocus();
                                current.text = choices[i];
                                if (step == 0) {
                                  aspiration.text =
                                      starterRecipes[i].aspiration;
                                }
                                celebrationObserved = false;
                                practiced = false;
                                if (scroll.hasClients) scroll.jumpTo(0);
                                if (step < 2) step++;
                              }),
                              child: Row(
                                children: [
                                  Icon(icons[i], size: 24),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(choices[i]),
                                        if (step == 2 &&
                                            choices[i] ==
                                                recommendedCelebration)
                                          Text(
                                            'Suggested · a short way to mark your step.',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Card(
                color: colors.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 64,
                        child: PlantArt(
                          stage: GrowthStage.seed,
                          species: species,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(preview),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (step == 2)
                ExpansionTile(
                  key: ValueKey('custom-$step'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Plant details (optional)'),
                  children: [
                    if (step == 2) ...[
                      TextFormField(
                        controller: aspiration,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          labelText: 'I want more...',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: species,
                        decoration: const InputDecoration(
                          labelText: 'Your plant',
                        ),
                        items: [
                          for (final value in ['Cosmos', 'Sunflower', 'Fern'])
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => species = value);
                        },
                      ),
                    ],
                  ],
                ),
              if (step == 2)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('I practiced my celebration'),
                  subtitle: const Text('Optional. You can try it later.'),
                  value: practiced,
                  onChanged: celebration.text.trim().isEmpty
                      ? null
                      : (value) => setState(() {
                          practiced = value ?? false;
                          celebrationObserved = practiced;
                        }),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (step > 0)
          TextButton(
            onPressed: () {
              if (scroll.hasClients) scroll.jumpTo(0);
              setState(() => step--);
            },
            child: const Text('Back'),
          ),
        FilledButton(
          onPressed: canContinue && (step < 2 || complete)
              ? () {
                  if (step < 2) {
                    if (scroll.hasClients) scroll.jumpTo(0);
                    setState(() => step++);
                  } else {
                    save();
                  }
                }
              : null,
          child: Text(
            [
              'Choose a tiny action',
              'Choose a celebration',
              'Plant this seed',
            ][step],
          ),
        ),
      ],
    );
  }

  Widget _editingDialog(BuildContext context) => AlertDialog(
    title: Text(
      widget.habit == null ? 'Plant one tiny step' : 'Adjust your recipe',
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Start with less than 30 seconds. Pick a starter, or make it your own.',
              ),
              const SizedBox(height: 16),
              for (final field in [
                (aspiration, 'I want more...', 'Calm, focus, connection...'),
                (
                  anchor,
                  'After I...',
                  'A specific routine that already happens',
                ),
                (behavior, 'I will...', 'One breath, one word, one movement'),
                (
                  celebration,
                  'Then I celebrate by...',
                  'A smile, gesture, or encouraging phrase',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: field.$1,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: field.$2,
                      hintText: field.$3,
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Add this part of your recipe.'
                        : null,
                    onChanged: (_) => setState(() {
                      practiced = false;
                      celebrationObserved = false;
                    }),
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: species,
                decoration: const InputDecoration(labelText: 'Your plant'),
                items: [
                  for (final s in ['Cosmos', 'Sunflower', 'Fern'])
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) => setState(() => species = v!),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I practiced my celebration'),
                subtitle: const Text('Optional. You can try it later.'),
                value: practiced,
                onChanged: (v) => setState(() {
                  practiced = v!;
                  celebrationObserved = v;
                }),
              ),
              if (!complete)
                const Text(
                  'Add every part of your recipe, up to 200 characters each, before saving.',
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: complete ? save : null,
        child: Text(widget.habit == null ? 'Plant this seed' : 'Save recipe'),
      ),
    ],
  );
}
