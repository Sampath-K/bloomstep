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
  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    aspiration = TextEditingController(text: h?.aspiration ?? 'Calm');
    anchor = TextEditingController(text: h?.anchor ?? 'drink coffee');
    behavior = TextEditingController(text: h?.behavior ?? 'take one breath');
    celebration = TextEditingController(text: h?.celebration ?? 'smile');
    species = h?.species ?? 'Cosmos';
  }

  @override
  void dispose() {
    scroll.dispose();
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

  Widget _pickerDialog(BuildContext context) {
    return AlertDialog(
      title: Semantics(
        header: true,
        child: const Text('Plant a habit'),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          controller: scroll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sentenceChoices('After I', anchor, const [
                ('coffee', 'drink coffee'),
                ('tea', 'drink tea'),
              ]),
              _sentenceChoices('I will', behavior, const [
                ('take one breath', 'take one breath'),
                ('stretch', 'stretch once'),
              ]),
              ExpansionTile(
                title: const Text('More'),
                tilePadding: EdgeInsets.zero,
                children: [_recipeFields()],
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
        FilledButton(
          onPressed: complete ? save : null,
          child: const Text('Plant a Seed'),
        ),
      ],
    );
  }

  Widget _sentenceChoices(
    String label,
    TextEditingController controller,
    List<(String, String)> choices,
  ) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(label),
      for (final choice in choices)
        ChoiceChip(
          label: Text(choice.$1),
          selected: controller.text == choice.$2,
          onSelected: (_) => setState(() {
            controller.text = choice.$2;
            practiced = false;
            celebrationObserved = false;
          }),
        ),
      if (!choices.any((choice) => choice.$2 == controller.text))
        InputChip(
          label: Text(controller.text),
          isEnabled: false,
        ),
    ],
  );

  Widget _editingDialog(BuildContext context) => AlertDialog(
    title: Text(
      widget.habit == null ? 'Plant one tiny step' : 'Adjust your recipe',
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(child: _recipeFields()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: complete ? save : null,
        child: const Text('Save recipe'),
      ),
    ],
  );

  Widget _recipeFields() => Form(
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
          (anchor, 'After I...', 'A specific routine that already happens'),
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
              key: field.$1 == anchor
                  ? const ValueKey('custom-anchor')
                  : field.$1 == behavior
                  ? const ValueKey('custom-action')
                  : field.$1 == celebration
                  ? const ValueKey('custom-celebration')
                  : const ValueKey('custom-aspiration'),
              controller: field.$1,
              maxLength: 200,
              textInputAction: field.$1 == celebration
                  ? TextInputAction.done
                  : TextInputAction.next,
              decoration: InputDecoration(
                labelText: field.$2,
                hintText: field.$3,
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Add this part of your recipe.';
                if (text.length > 200) {
                  return 'Keep this choice to 200 characters or fewer.';
                }
                return null;
              },
              onChanged: (_) => setState(() {
                practiced = false;
                celebrationObserved = false;
              }),
            ),
          ),
        if (widget.habit == null)
          for (final recipe in starterRecipes)
            OutlinedButton(
              key: ValueKey('starter-${recipe.aspiration}'),
              onPressed: () => setState(() {
                FocusScope.of(context).unfocus();
                aspiration.text = recipe.aspiration;
                anchor.text = recipe.anchor;
                behavior.text = recipe.behavior;
                celebration.text = recipe.celebration;
                practiced = false;
                celebrationObserved = false;
              }),
              child: Text(
                'After I ${recipe.anchor}, I will ${recipe.behavior}. '
                'Then I celebrate: ${recipe.celebration}.',
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
          onChanged: celebration.text.trim().isEmpty
              ? null
              : (v) => setState(() {
                  practiced = v ?? false;
                  celebrationObserved = practiced;
                }),
        ),
        if (!complete)
          const Text(
            'Add every part of your recipe, up to 200 characters each, before saving.',
          ),
      ],
    ),
  );
}
