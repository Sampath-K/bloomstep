import 'package:flutter/material.dart';

import '../../core/models.dart';

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

class _RecipeBuilderState extends State<RecipeBuilder> {
  final form = GlobalKey<FormState>();
  late final TextEditingController aspiration, anchor, behavior, celebration;
  var species = 'Cosmos';
  bool practiced = false;
  bool celebrationObserved = false;
  String? templateCategory;
  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    aspiration = TextEditingController(text: h?.aspiration ?? 'Calm');
    anchor = TextEditingController(text: h?.anchor);
    behavior = TextEditingController(text: h?.behavior);
    celebration = TextEditingController(text: h?.celebration);
    species = h?.species ?? 'Cosmos';
    practiced = h != null;
  }

  @override
  void dispose() {
    for (final controller in [aspiration, anchor, behavior, celebration]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
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
              if (widget.habit == null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final recipe in starterRecipes)
                      ActionChip(
                        label: Text(recipe.aspiration),
                        onPressed: () => setState(() {
                          aspiration.text = recipe.aspiration;
                          anchor.text = recipe.anchor;
                          behavior.text = recipe.behavior;
                          celebration.text = recipe.celebration;
                          practiced = false;
                          celebrationObserved = false;
                          templateCategory = recipe.aspiration.toLowerCase();
                        }),
                      ),
                  ],
                ),
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
                      templateCategory = null;
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
                subtitle: const Text(
                  'Try it now. Let the tiny success feel good.',
                ),
                value: practiced,
                onChanged: (v) => setState(() {
                  practiced = v!;
                  celebrationObserved = v;
                }),
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
        onPressed: practiced
            ? () {
                if (form.currentState!.validate()) {
                  Navigator.pop(
                    context,
                    RecipeDraft(
                      aspiration.text,
                      anchor.text,
                      behavior.text,
                      celebration.text,
                      species,
                      templateCategory: templateCategory,
                      celebrationPracticed: celebrationObserved,
                    ),
                  );
                }
              }
            : null,
        child: Text(widget.habit == null ? 'Plant this seed' : 'Save recipe'),
      ),
    ],
  );
}
