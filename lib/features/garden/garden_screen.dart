import 'dart:convert';
import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/garden_store.dart';
import '../../core/models.dart';
import '../../core/rules.dart';
import '../../services/identity.dart';
import '../../services/sync_service.dart';
import '../../services/desktop_reminders.dart';
import '../../services/remote_config.dart';

import 'package:launch_at_startup/launch_at_startup.dart';

import 'plant_art.dart';
import 'recipe_builder.dart';

class GardenScreen extends StatefulWidget {
  const GardenScreen({super.key, required this.store, this.identity});
  final GardenStore store;
  final IdentityService? identity;
  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen> {
  List<Habit> habits = [];
  bool loading = true;
  bool working = false;
  bool reducedMotion = false;
  String? error;
  String syncStatus = 'Local garden';
  bool syncing = false;
  bool closing = false;
  Timer? syncTimer;
  DesktopReminders? reminders;
  @override
  void initState() {
    super.initState();
    _load();
    if (widget.identity != null) {
      reminders = DesktopReminders(widget.store, _load, (message) {
        if (mounted) setState(() => error = message);
      });
      reminders!.initialize().catchError((Object e) {
        if (mounted) setState(() => error = 'Reminders could not start: $e');
      });
      _sync();
      _refreshConfig();
      syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => _sync());
    }
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    reminders?.dispose().catchError(
      (Object e) => debugPrint('Reminder cleanup failed: $e'),
    );
    super.dispose();
  }

  Future<void> _sync() async {
    final identity = widget.identity;
    if (identity == null || identity.account == null || syncing || closing) {
      return;
    }

    syncing = true;
    if (mounted) setState(() => syncStatus = 'Syncing...');
    try {
      await SyncService(identity, widget.store).sync();
      if (mounted) {
        setState(() => syncStatus = 'Saved on this device and synced');
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => syncStatus = 'Offline / sync needs attention: $e');
      }
    } finally {
      syncing = false;
    }
  }

  Future<void> _refreshConfig() async {
    try {
      final config = await RemoteConfig.fetch(widget.store);
      reminders?.config = config;
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Remote config unavailable; using reviewed local control copy. $e',
        );
      }
    }
  }

  Future<void> _load() async {
    try {
      final data = await widget.store.habits();
      final reduce = await widget.store.setting('reducedMotion') == 'true';
      if (mounted) {
        setState(() {
          habits = data;
          reducedMotion = reduce;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Your garden could not be read: $e';
          loading = false;
        });
      }
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (working) return;
    setState(() {
      working = true;
      error = null;
    });
    try {
      await action();
      await _load();
      if (widget.identity?.account != null) unawaited(_sync());
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _plant() async {
    if (habits.where((h) => h.status == 'active').length >= 3) {
      final more = await _confirm(
        'Start small',
        'Three active recipes are plenty to begin. Plant another only if it feels easy.',
        'Plant another',
      );
      if (!more) return;
    }
    if (!mounted) return;
    final recipe = await showDialog<RecipeDraft>(
      context: context,
      builder: (_) => const RecipeBuilder(),
    );
    if (recipe == null) return;
    await _act(() async {
      await widget.store.plant(
        aspiration: recipe.aspiration,
        anchor: recipe.anchor,
        behavior: recipe.behavior,
        celebration: recipe.celebration,
        species: recipe.species,
      );
    });
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _check(Habit habit, CheckInResult result) async {
    String? reason;
    if (result == CheckInResult.notToday) {
      reason = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Rest days belong in a garden.'),
          children: [
            for (final entry in {
              'forgot': 'I forgot',
              'too hard': 'It felt too hard',
              'anchor': 'My anchor did not happen',
              'motivation': 'It did not feel right',
              'skip': 'No reason needed',
            }.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
      );
      if (reason == null) return;
      if (reason == 'skip') reason = null;
    } else {
      // Show the personal celebration immediately; persistence follows independently.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result == CheckInResult.didMore ? 'A little extra! ' : 'That tiny step counts! '}Now ${habit.celebration}.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
    await _act(() => widget.store.checkIn(habit.id, result, reason: reason));
    await reminders?.practiced(habit.id);
  }

  Future<void> _edit(Habit habit) async {
    final draft = await showDialog<RecipeDraft>(
      context: context,
      builder: (_) => RecipeBuilder(habit: habit),
    );
    if (draft != null) {
      await _act(
        () => widget.store.edit(
          habit,
          anchor: draft.anchor,
          behavior: draft.behavior,
          celebration: draft.celebration,
        ),
      );
    }
  }

  Future<void> _reflection(Habit habit) async {
    final scores = [4, 4, 4, 4];
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('How natural does this feel?'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(habit.recipe),
                  const SizedBox(height: 12),
                  Text(
                    '${habit.recentPractice} practice days in the last 28. Every return counts.',
                  ),
                  if (habit.lastReason != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(recipeDoctor(habit.lastReason!)),
                    ),
                  const Text(
                    'Reflect on what helped this week. These original self-reflection questions are not a validated clinical instrument. 1 = not yet; 7 = very natural.',
                  ),
                  for (var i = 0; i < 4; i++) ...[
                    const SizedBox(height: 12),
                    Text(
                      [
                        'Starting feels automatic',
                        'My routine reminds me without effort',
                        'The tiny step needs little thought',
                        'I begin naturally when my anchor happens',
                      ][i],
                    ),
                    Slider(
                      value: scores[i].toDouble(),
                      min: 1,
                      max: 7,
                      divisions: 6,
                      label: '${scores[i]}',
                      onChanged: (v) => update(() => scores[i] = v.round()),
                    ),
                  ],
                  const Text(
                    'Naturalness checks are spaced 14 days apart. Two scores of 5.5+ and at least 17 practice days in 28 invite graduation.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save reflection'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await _act(() => widget.store.reflect(habit.id, scores));
      if (!mounted) return;
      if (habits.firstWhere((h) => h.id == habit.id).status == 'graduated') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This one is part of you now. Welcome to your evergreen Grove!',
            ),
          ),
        );
      }
    }
  }

  Future<void> _share() async {
    const url =
        'https://sampath-k.github.io/bloomstep/?invite=garden&channel=link';
    await widget.store.track('share_initiated');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite someone to grow'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This invitation contains no habit text or account information. Personalized referral credit is not enabled until the cloud service is live.',
              ),
              const SizedBox(height: 16),
              Semantics(
                label: 'QR code for the Bloomstep website',
                child: QrImageView(
                  data: url,
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
              const SelectableText(url),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(this.context);
              await Clipboard.setData(const ClipboardData(text: url));
              messenger.showSnackBar(
                const SnackBar(content: Text('Invitation link copied.')),
              );
            },
            child: const Text('Copy link'),
          ),
          TextButton(
            onPressed: () => _act(() async {
              if (!await launchUrl(
                Uri(
                  scheme: 'mailto',
                  query:
                      'subject=${Uri.encodeComponent('A tiny step together')}&body=${Uri.encodeComponent('Bloomstep is growing a gentle habit garden. $url')}',
                ),
              )) {
                throw StateError(
                  'No email application is available. Copy the invitation link instead.',
                );
              }
            }),
            child: const Text('Email invite'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _voice() async {
    final body = TextEditingController();
    var kind = 'Idea';
    var rating = 5;
    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Help us grow'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    items: [
                      for (final k in [
                        'Idea',
                        'Bug',
                        'Question',
                        'Praise',
                        'This felt wrong',
                        'Rating',
                      ])
                        DropdownMenuItem(value: k, child: Text(k)),
                    ],
                    onChanged: (v) => update(() => kind = v!),
                  ),
                  if (kind == 'Rating')
                    Slider(
                      value: rating.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: '$rating stars',
                      onChanged: (v) => update(() => rating = v.round()),
                    ),
                  TextField(
                    controller: body,
                    maxLength: 2000,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Your feedback',
                      hintText: 'Please do not include secrets or private account details.',
                    ),
                  ),
                  const Text(
                    'Private by default. Saved locally first; queued is not the same as received by the team.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save feedback'),
              ),
            ],
          ),
        ),
      );
      if (submitted == true) {
        await _act(
          () => widget.store.submitVoice(
            kind,
            body.text,
            rating: kind == 'Rating' ? rating : null,
          ),
        );
      }
    } finally {
      body.dispose();
    }
    final records = await widget.store.voice();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('My feedback'),
        content: SizedBox(
          width: 520,
          height: 350,
          child: ListView(
            children: [
              if (records.isEmpty)
                const Text('No feedback yet. Your voice is welcome.'),
              for (final record in records)
                ListTile(
                  title: Text(record['body'] as String),
                  subtitle: Text(
                    '${record['kind']} - ${record['status']}\n${(jsonDecode(record['replies'] as String) as List).join('\n')}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _settings() async {
    var analytics = await widget.store.setting('analytics') == 'true';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Your garden, your choices'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Reduced motion'),
                    value: reducedMotion,
                    onChanged: (v) async {
                      await _act(
                        () => widget.store.setSetting('reducedMotion', '$v'),
                      );
                      update(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Share product event counts'),
                    subtitle: const Text(
                      'Off by default. No habit text, email or feedback in telemetry.',
                    ),
                    value: analytics,
                    onChanged: (v) async {
                      await _act(
                        () => widget.store.setSetting('analytics', '$v'),
                      );
                      update(() => analytics = v);
                    },
                  ),
                  if (reminders != null)
                    SwitchListTile(
                      title: const Text('Gentle Windows reminders'),
                      subtitle: const Text(
                        'Opt in to toasts and tray. Closing the window keeps Bloomstep running. Delivery stops when you exit.',
                      ),
                      value: reminders!.enabled,
                      onChanged: (value) async {
                        await _act(
                          value ? reminders!.enable : reminders!.disable,
                        );
                        update(() {});
                      },
                    ),
                  if (reminders != null) ...[
                    ListTile(
                      title: const Text('Choose check-in time'),
                      onTap: () => _chooseMinute('reminderMinute', 1080),
                    ),
                    ListTile(
                      title: const Text('Quiet hours start'),
                      subtitle: const Text('Default 21:30'),
                      onTap: () => _chooseMinute('quietStart', 1290),
                    ),
                    ListTile(
                      title: const Text('Quiet hours end'),
                      subtitle: const Text('Default 07:30'),
                      onTap: () => _chooseMinute('quietEnd', 450),
                    ),
                    ListTile(
                      title: const Text('Snooze for one hour'),
                      onTap: () => _act(reminders!.snooze),
                    ),
                    ListTile(
                      title: const Text('Enable launch at Windows sign-in'),
                      subtitle: const Text(
                        'Optional. Starts only this installed app, not a system service.',
                      ),
                      onTap: () => _act(() async {
                        if (!await launchAtStartup.enable()) {
                          throw StateError(
                            'Windows startup registration failed.',
                          );
                        }
                      }),
                    ),
                    ListTile(
                      title: const Text('Disable launch at Windows sign-in'),
                      onTap: () => _act(() async {
                        if (!await launchAtStartup.disable()) {
                          throw StateError('Windows startup removal failed.');
                        }
                      }),
                    ),
                  ],
                  ListTile(
                    title: const Text('Export my data (JSON)'),
                    leading: const Icon(Icons.download),
                    onTap: () => _act(() async {
                      final target = await getSaveLocation(
                        suggestedName: 'bloomstep-export.json',
                      );
                      if (target == null) return;
                      final bytes = utf8.encode(
                        const JsonEncoder.withIndent('  ')
                            .convert(await widget.store.export()),
                      );
                      await XFile.fromData(
                        bytes,
                        mimeType: 'application/json',
                        name: 'bloomstep-export.json',
                      ).saveTo(target.path);
                    }),
                  ),
                  ListTile(
                    title: const Text('Check for updates'),
                    leading: const Icon(Icons.system_update),
                    onTap: () => _act(() async {
                      if (!await launchUrl(
                        Uri.parse(
                          'https://github.com/Sampath-K/bloomstep/releases',
                        ),
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw StateError('Release page could not be opened.');
                      }
                    }),
                  ),
                  ListTile(
                    title: const Text('Delete local garden'),
                    subtitle: const Text(
                      'Cloud account deletion requires the connected service.',
                    ),
                    leading: const Icon(Icons.delete_outline),
                    onTap: () async {
                      if (await _confirm(
                        'Delete this local garden?',
                        'Export first if you want a copy. This cannot be undone. It does not delete your identity provider account.',
                        'Delete local data',
                      )) {
                        await _act(() async {
                          closing = true;
                          while (syncing) {
                            await Future<void>.delayed(
                              const Duration(milliseconds: 50),
                            );
                          }
                          await reminders?.disable();
                          await widget.store.deleteLocalAccount();
                          closing = false;
                        });
                      }
                    },
                  ),
                  if (widget.identity != null)
                    ListTile(
                      title: const Text('Delete account data everywhere'),
                      subtitle: const Text(
                        'Requires internet. Keeps a deletion marker so old devices cannot restore deleted records. Does not delete your Microsoft/Google identity.',
                      ),
                      onTap: () async {
                        if (!await _confirm(
                          'Delete account data everywhere?',
                          'This is permanent. Export first. The server must confirm deletion before local data is cleared.',
                          'Delete everywhere',
                        )) {
                          return;
                        }
                        await _act(() async {
                          closing = true;
                          while (syncing) {
                            await Future<void>.delayed(
                              const Duration(milliseconds: 50),
                            );
                          }
                          await reminders?.disable();
                          await SyncService(
                            widget.identity!,
                            widget.store,
                          ).deleteAccount();
                        });
                        if (context.mounted && mounted && error == null) {
                          Navigator.pop(context);
                          Navigator.pop(this.context);
                        } else {
                          closing = false;
                        }
                      },
                    ),
                  if (widget.identity != null)
                    ListTile(
                      title: const Text('Sign out'),
                      subtitle: const Text(
                        'Clears this account garden from this device. Export any unsynced work first.',
                      ),
                      leading: const Icon(Icons.logout),
                      onTap: () async {
                        if (!await _confirm(
                          'Sign out?',
                          'Unsynced data will be removed from this device. Export it first if needed.',
                          'Sign out',
                        )) {
                          return;
                        }
                        await _act(() async {
                          closing = true;
                          while (syncing) {
                            await Future<void>.delayed(
                              const Duration(milliseconds: 50),
                            );
                          }
                          await reminders?.disable();
                          await widget.store.deleteLocalAccount();
                          await widget.identity!.signOut();
                        });
                        if (context.mounted && mounted && error == null) {
                          Navigator.pop(context);
                          Navigator.pop(this.context);
                        }
                      },
                    ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'No AI. No streak penalties. Original content inspired by behavior design research. Health recipes are not medical advice. Ages 16+.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseMinute(String key, int fallback) async {
    final minute = int.parse(await widget.store.setting(key) ?? '$fallback');
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (time != null) {
      await _act(
        () => widget.store.setSetting(key, '${time.hour * 60 + time.minute}'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bloomstep'),
        actions: [
          IconButton(
            tooltip: 'Invite a friend',
            onPressed: working ? null : _share,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: 'Help us grow',
            onPressed: working ? null : _voice,
            icon: const Icon(Icons.chat_bubble_outline),
          ),
          IconButton(
            tooltip: 'Settings and privacy',
            onPressed: working ? null : _settings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 100),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A little is enough.',
                        style: theme.textTheme.displaySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your plants keep their growth. Rest days and returning both belong here.',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 24),
                      Text(syncStatus, style: theme.textTheme.bodySmall),
                      if (widget.identity != null)
                        TextButton.icon(
                          onPressed: syncing ? null : _sync,
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync now'),
                        ),
                      if (error != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(error!),
                          ),
                        ),
                      if (habits.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(40),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            children: [
                              const SizedBox(
                                height: 180,
                                width: 240,
                                child: PlantArt(
                                  stage: GrowthStage.seed,
                                  species: 'Cosmos',
                                ),
                              ),
                              Text(
                                'Your garden is ready to grow',
                                style: theme.textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Choose one tiny behavior, give it an anchor, and practice your celebration.',
                              ),
                            ],
                          ),
                        ),
                      Wrap(
                        spacing: 20,
                        runSpacing: 20,
                        children: [
                          for (final habit in habits)
                            SizedBox(
                              width: 350,
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              habit.status == 'graduated'
                                                  ? 'Evergreen Grove'
                                                  : habit.aspiration,
                                              style: theme.textTheme.titleLarge,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Edit recipe',
                                            onPressed: working
                                                ? null
                                                : () => _edit(habit),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Semantics(
                                        label:
                                            '${habit.species}, ${habit.stage.name}. ${habit.practiceCount} practice days.',
                                        child: AnimatedScale(
                                          duration:
                                              reducedMotion ||
                                                  MediaQuery.disableAnimationsOf(
                                                    context,
                                                  )
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 240,
                                                ),
                                          scale:
                                              habit.today ==
                                                  CheckInResult.didMore
                                              ? 1.04
                                              : 1,
                                          child: SizedBox(
                                            height: 180,
                                            width: double.infinity,
                                            child: PlantArt(
                                              stage: habit.stage,
                                              species: habit.species,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${habit.stage.name.toUpperCase()}  /  ${habit.practiceCount} tiny steps',
                                        style: theme.textTheme.labelLarge,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        habit.recipe,
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      Text('Then I ${habit.celebration}.'),
                                      const SizedBox(height: 16),
                                      if (habit.status != 'graduated')
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            FilledButton(
                                              onPressed: working
                                                  ? null
                                                  : () => _check(
                                                      habit,
                                                      CheckInResult.did,
                                                    ),
                                              child: const Text('Did it'),
                                            ),
                                            OutlinedButton(
                                              onPressed: working
                                                  ? null
                                                  : () => _check(
                                                      habit,
                                                      CheckInResult.didMore,
                                                    ),
                                              child: const Text('Did more'),
                                            ),
                                            TextButton(
                                              onPressed: working
                                                  ? null
                                                  : () => _check(
                                                      habit,
                                                      CheckInResult.notToday,
                                                    ),
                                              child: const Text('Not today'),
                                            ),
                                          ],
                                        ),
                                      if (habit.today != null)
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                habit.today ==
                                                        CheckInResult.notToday
                                                    ? 'Resting today. Growth stays.'
                                                    : 'Today is recorded. You can change it.',
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: working
                                                  ? null
                                                  : () => _act(
                                                      () => widget.store.undo(
                                                        habit.id,
                                                      ),
                                                    ),
                                              child: const Text('Undo today'),
                                            ),
                                          ],
                                        ),
                                      TextButton.icon(
                                        onPressed: working
                                            ? null
                                            : () => _reflection(habit),
                                        icon: const Icon(
                                          Icons.self_improvement,
                                        ),
                                        label: const Text(
                                          'Reflect / Recipe Doctor',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: working ? null : _plant,
        icon: const Icon(Icons.add),
        label: const Text('Plant a habit'),
      ),
    );
  }
}
