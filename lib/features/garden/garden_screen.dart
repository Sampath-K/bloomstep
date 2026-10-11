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
import '../../services/update_service.dart';
import '../../services/invitation_service.dart';
import '../../services/invitation_intent.dart';
import '../../services/native_share.dart';
import '../../services/session_diagnostics.dart';
import 'reminder_observation_controls.dart';
import '../../services/installer_measurement.dart';
import 'measurement_controls.dart';

import 'package:launch_at_startup/launch_at_startup.dart';

import 'plant_art.dart';
import 'recipe_builder.dart';

const _testBuild = bool.fromEnvironment('BLOOMSTEP_TEST_BUILD');

class GardenScreen extends StatefulWidget {
  const GardenScreen({
    super.key,
    required this.store,
    this.identity,
    this.updateService,
    this.reminderGateway,
    this.configLoader,
    this.invitationInbox,
    this.invitationService,
    this.diagnostics,
    this.installerMeasurement,
    this.testExportPathSelector,
    this.clock,
    this.deviceGuest = false,
    this.testDisableServices = false,
    this.profileBuilder,
    this.onSignedOut,
    this.onProfileShown,
    this.autoInviteFirstHabit = false,
    this.firstHabitInvitationReady = true,
  });
  final GardenStore store;
  final IdentityService? identity;
  final UpdateService? updateService;
  final ReminderGateway? reminderGateway;
  final Future<RemoteConfigResult> Function(GardenStore)? configLoader;
  final InvitationInbox? invitationInbox;
  final InvitationService? invitationService;
  final SessionDiagnostics? diagnostics;
  final InstallerMeasurement? installerMeasurement;
  final Future<String?> Function()? testExportPathSelector;
  final DateTime Function()? clock;
  final bool deviceGuest;
  final bool testDisableServices;
  final Widget Function(Future<void> Function() signOut, VoidCallback manage)?
  profileBuilder;
  final Future<void> Function(String? warning)? onSignedOut;
  final VoidCallback? onProfileShown;
  final bool autoInviteFirstHabit;
  final bool firstHabitInvitationReady;
  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen> {
  DateTime _now() => widget.clock?.call() ?? DateTime.now();
  List<Habit> habits = [];
  bool loading = true;
  bool working = false;
  bool reducedMotion = false;
  bool weeklyDue = false;
  bool ratingInvitation = false;
  int ratingMoment = 0;
  Map<String, DateTime?> naturalnessDates = {};
  Set<String> pausedReminders = {};
  String? error;
  String? configWarning;
  String syncStatus = 'Local garden';
  bool syncing = false;
  bool closing = false;
  bool profileShown = false;
  bool firstHabitInvited = false;
  bool invitationScheduled = false;
  Timer? syncTimer;
  Timer? configExpiryTimer;
  DesktopReminders? reminders;
  InvitationService? invitations;
  InvitationIntent? pendingInvitation;
  InvitationStatus? invitationStatus;
  Map<String, dynamic>? acceptedCard;
  String? invitationWarning;
  @override
  void initState() {
    super.initState();
    if (!_testBuild &&
        (widget.clock != null ||
            widget.testExportPathSelector != null ||
            widget.testDisableServices)) {
      throw StateError(
        'Test-only garden adapters are unavailable in release builds.',
      );
    }
    invitations = widget.testDisableServices
        ? null
        : widget.invitationService ??
              (widget.identity == null
                  ? null
                  : InvitationService(widget.store, identity: widget.identity));
    widget.invitationInbox?.addListener(_inboxChanged);
    _inboxChanged();
    if (invitations != null) unawaited(_loadInvitationCache());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_foregroundOpening());
    });
    _load();
    if (!widget.testDisableServices &&
        (widget.identity != null || widget.reminderGateway != null)) {
      reminders = DesktopReminders(widget.store, _load, (message) {
        if (mounted) setState(() => error = message);
      }, gateway: widget.reminderGateway);
      reminders!.initialize().catchError((Object e) {
        if (mounted) setState(() => error = 'Reminders could not start: $e');
      });
      _refreshConfig();
    }
    if (widget.identity != null && !widget.testDisableServices) {
      _sync();
      syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => _sync());
    }
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    widget.invitationInbox?.removeListener(_inboxChanged);
    configExpiryTimer?.cancel();
    reminders?.dispose().catchError(
      (Object e) => debugPrint('Reminder cleanup failed: $e'),
    );
    super.dispose();
  }

  @override
  void didUpdateWidget(GardenScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleFirstHabit();
  }

  void _scheduleFirstHabit() {
    if (loading ||
        !widget.deviceGuest ||
        !widget.autoInviteFirstHabit ||
        !widget.firstHabitInvitationReady ||
        habits.isNotEmpty ||
        firstHabitInvited ||
        invitationScheduled ||
        closing ||
        working) {
      return;
    }
    invitationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      invitationScheduled = false;
      if (!mounted ||
          loading ||
          closing ||
          working ||
          firstHabitInvited ||
          habits.isNotEmpty ||
          !widget.deviceGuest ||
          !widget.autoInviteFirstHabit ||
          !widget.firstHabitInvitationReady ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      firstHabitInvited = true;
      unawaited(_plant());
    });
  }

  Future<void> _foregroundOpening() async {
    final account = widget.store.account;
    final generation = widget.store.syncGeneration;
    try {
      final last = DateTime.tryParse(
        await widget.store.setting('lastInteraction') ?? '',
      );
      if (!mounted || closing) return;
      widget.store.requireSyncSession(account, generation);
      final now = _now();
      final returning =
          last != null &&
          now.toUtc().difference(last) >= const Duration(days: 3);
      await widget.store.recordInteraction(now: now, positiveReturn: returning);
      if (!mounted || closing) return;
      widget.store.requireSyncSession(account, generation);
      if (returning) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Returning is a win; your garden kept its growth'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Your return could not be recorded: $e');
      }
    }
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
      await reminders?.removeDeletedRecipes();
      if (mounted) {
        setState(() => syncStatus = 'Saved on this device and synced');
      }
      await _load();
      if (invitations != null) await _refreshInvitations();
    } catch (e) {
      if (mounted) {
        setState(() => syncStatus = 'Sync needs attention: $e');
      }
    } finally {
      syncing = false;
    }
  }

  Future<void> _refreshConfig() async {
    try {
      final result = await (widget.configLoader ?? RemoteConfig.fetch)(
        widget.store,
      );
      reminders?.config = result.config;
      configExpiryTimer?.cancel();
      final expires = result.config.expiresAt;
      if (expires != null) {
        final remaining = expires.difference(_now().toUtc());
        configExpiryTimer = Timer(
          remaining.isNegative ? Duration.zero : remaining,
          () {
            reminders?.config = RemoteConfig.defaults;
            if (mounted) {
              setState(
                () => configWarning = 'Remote configuration expired; using reviewed local control copy. No experiment is active.',
              );
            }
          },
        );
      }
      if (mounted) setState(() => configWarning = result.warning);
    } catch (_) {
      reminders?.config = RemoteConfig.defaults;
      configExpiryTimer?.cancel();
      if (mounted) {
        setState(
          () => configWarning = 'Remote configuration unavailable; using reviewed local control copy. No experiment is active.',
        );
      }
    }
  }

  Future<void> _load() async {
    try {
      final data = await widget.store.habits();
      final reduce = await widget.store.setting('reducedMotion') == 'true';
      final weekly = await widget.store.weeklyReflectionDue();
      final dates = <String, DateTime?>{};
      final paused = <String>{};
      for (final habit in data) {
        dates[habit.id] = await widget.store.naturalnessAvailableAt(habit.id);
        if ((int.tryParse(
                  await widget.store.setting('ignored:${habit.id}') ?? '',
                ) ??
                0) >=
            7) {
          paused.add(habit.id);
        }
      }
      if (mounted) {
        setState(() {
          habits = data;
          reducedMotion = reduce;
          weeklyDue = weekly;
          naturalnessDates = dates;
          pausedReminders = paused;
          loading = false;
        });
        _scheduleFirstHabit();
        if (!profileShown && widget.profileBuilder != null) {
          profileShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onProfileShown?.call();
          });
        }
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
      ratingInvitation = false;
      ratingMoment++;
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

  Future<void> _plant({Habit? prefill}) async {
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
      builder: (_) => RecipeBuilder(habit: prefill),
    );
    if (recipe == null || !mounted || closing || working) return;
    Habit? planted;
    await _act(() async {
      planted = await widget.store.plant(
        aspiration: recipe.aspiration,
        anchor: recipe.anchor,
        behavior: recipe.behavior,
        celebration: recipe.celebration,
        species: recipe.species,
        templateCategory: recipe.templateCategory,
        celebrationPracticed: recipe.celebrationPracticed,
      );
    });
    if (!mounted || closing || error != null || planted == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          PlantedRecipeDialog(habit: planted!, reducedMotion: reducedMotion),
    );
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

  Future<bool> _removeRecord(String type, String id) async {
    if (working) return false;
    final recipe = type == 'habits';
    if (!await _confirm(
      recipe ? 'Delete this recipe?' : 'Delete this feedback?',
      recipe
          ? 'Removes only this recipe, its check-ins, reflections and linked event records. Deletion cannot be undone. Offline deletion is queued until sync; other devices apply it when they reconnect. A minimal ID-only marker prevents stale copies from returning.'
          : 'Removes only this feedback or rating and its private replies. Deletion cannot be undone. Offline deletion is queued until sync; the team can see it until the server receives deletion. A minimal ID-only marker prevents stale copies from returning.',
      recipe ? 'Delete recipe' : 'Delete feedback',
    )) {
      return false;
    }
    if (working || !mounted) return false;
    await _act(() async {
      await widget.store.deleteRecord(type, id);
      if (recipe) await reminders?.removeDeletedRecipes();
    });
    return error == null;
  }

  Future<void> _check(Habit habit, CheckInResult result) async {
    String? reason;
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? celebration;
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
      celebration = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result == CheckInResult.didMore ? 'A little extra! ' : 'That tiny step counts! '}Now ${habit.celebration}.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
    var saved = false;
    await _act(() async {
      await widget.store.checkIn(habit.id, result, reason: reason, now: _now());
      saved = true;
    });
    await reminders?.practiced(habit.id);
    if (saved && celebration != null) {
      unawaited(_offerRatingAfterCelebration(celebration.closed, ratingMoment));
    }
  }

  Future<void> _offerRatingAfterCelebration(
    Future<SnackBarClosedReason> closed,
    int moment,
  ) async {
    await closed;
    if (!mounted ||
        closing ||
        working ||
        error != null ||
        moment != ratingMoment) {
      return;
    }
    try {
      final eligible = await widget.store.claimRatingPrompt();
      if (!mounted || closing || error != null || moment != ratingMoment) {
        return;
      }
      if (eligible) {
        setState(() => ratingInvitation = true);
        await widget.store.track(
          'rating_prompt_shown',
          properties: {
            'localDay': localDate(_now()),
            'platform': GardenStore.telemetryPlatform,
          },
        );
        if (widget.identity?.account != null) unawaited(_sync());
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Rating invitation could not be saved: $e');
      }
    }
  }

  Future<bool> _edit(Habit habit) async {
    final draft = await showDialog<RecipeDraft>(
      context: context,
      builder: (_) => RecipeBuilder(habit: habit),
    );
    if (draft != null) {
      await _act(() async {
        await widget.store.edit(
          habit,
          anchor: draft.anchor,
          behavior: draft.behavior,
          celebration: draft.celebration,
        );
        if (draft.celebrationPracticed) {
          await widget.store.track(
            'celebration_practiced',
            properties: {
              'habitId': habit.id,
              'localDay': localDate(_now()),
              'platform': GardenStore.telemetryPlatform,
            },
          );
        }
      });
      return error == null;
    }
    return false;
  }

  Future<void> _reflection(Habit habit) async {
    final available = await widget.store.naturalnessAvailableAt(habit.id);
    if (!mounted) return;
    if (available != null && _now().toUtc().isBefore(available)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Naturalness available ${localDate(available.toLocal())}. Weekly reflection is always available.',
          ),
        ),
      );
      return;
    }
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
      if (error == null &&
          habit.status != 'graduated' &&
          habits.firstWhere((h) => h.id == habit.id).status == 'graduated') {
        final celebration = ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This one is part of you now. Welcome to your evergreen Grove!',
            ),
          ),
        );
        unawaited(
          _offerRatingAfterCelebration(celebration.closed, ratingMoment),
        );
      }
    }
  }

  Future<void> _weeklyReflection(Habit habit) async {
    final recommendation = await widget.store.weeklyRecommendation(habit.id);
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('A minute for your recipe'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(habit.recipe),
                const SizedBox(height: 12),
                const Text(
                  'Under 60 seconds: What made starting easier this week? Does your anchor happen reliably? Does your celebration feel good?',
                ),
                const SizedBox(height: 12),
                Text(recommendation),
                const SizedBox(height: 12),
                const Text(
                  'Recipe Doctor uses your recorded reasons from the last seven days, not AI. You choose whether to change anything. This does not change your naturalness score or graduation criteria.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('Adjust my recipe'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('Keep my recipe'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await _act(() => widget.store.completeWeeklyReflection(habit.id));
    if (choice == 'edit' && error == null && mounted && await _edit(habit)) {
      await widget.store.track(
        'recipe_doctor_applied',
        properties: {
          'habitId': habit.id,
          'localDay': localDate(_now()),
          'platform': GardenStore.telemetryPlatform,
        },
      );
    }
  }

  void _inboxChanged() => unawaited(_readInvitation());

  Future<void> _readInvitation() async {
    try {
      final intent = await widget.invitationInbox?.read();
      if (mounted) setState(() => pendingInvitation = intent);
    } catch (_) {
      if (mounted) {
        setState(
          () => invitationWarning = 'The saved invitation is unavailable or expired. Open the original link again.',
        );
      }
    }
  }

  Future<void> _loadInvitationCache() async {
    try {
      final status = await invitations!.cachedStatus();
      final card = await invitations!.cachedAcceptedCard();
      if (mounted) {
        setState(() {
          invitationStatus = status;
          acceptedCard = card;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => invitationWarning =
              'Private invitation cache needs attention; reconnect to refresh.',
        );
      }
    }
  }

  Future<void> _refreshInvitations() async {
    try {
      final status = await invitations!.refreshStatus();
      if (mounted) {
        setState(() {
          invitationStatus = status;
          invitationWarning = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => invitationWarning = 'Invitation status could not be refreshed. Cached cosmetics are last-known server receipts, not a new grant.',
        );
      }
    }
  }

  Future<void> _clearCurrentInvitation(String code) async {
    final inbox = widget.invitationInbox;
    if (inbox != null && (await inbox.read())?.code == code) {
      await inbox.clear();
    }
    if (mounted && pendingInvitation?.code == code) {
      setState(() => pendingInvitation = null);
    }
  }

  Future<void> _acceptInvitation() async {
    final intent = pendingInvitation;
    if (intent == null || invitations == null) return;
    await _act(() async {
      final receipt = await invitations!.redeem(intent.code);
      if (mounted) setState(() => acceptedCard = receipt.recipeCard);
      await _clearCurrentInvitation(intent.code);
      await _refreshInvitations();
    });
  }

  Future<void> _importCard() async {
    final card = acceptedCard;
    if (card == null ||
        !await _confirm(
          'Use this shared recipe?',
          '${card['aspiration']}\nAfter I ${card['anchor']}, I will ${card['behavior']}.\nThen I ${card['celebration']}.\nSpecies: ${card['species']}\n\nYou can edit it before planting. Nothing is planted automatically.',
          'Open recipe builder',
        )) {
      return;
    }
    await _plant(
      prefill: Habit(
        id: '',
        aspiration: card['aspiration'],
        anchor: card['anchor'],
        behavior: card['behavior'],
        celebration: card['celebration'],
        species: card['species'],
        stage: GrowthStage.seed,
        status: 'active',
        practiceCount: 0,
        recentPractice: 0,
      ),
    );
  }

  Future<Map<String, dynamic>?> _chooseShareCard() async {
    if (habits.isEmpty) return null;
    final habit = await showDialog<Habit>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a recipe to explicitly share'),
        children: [
          for (final h in habits)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, h),
              child: Text(h.aspiration),
            ),
        ],
      ),
    );
    if (habit == null || !mounted) return null;
    final category = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose shared recipe category'),
        children: [
          for (final c in invitationCategories)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, c),
              child: Text(c),
            ),
        ],
      ),
    );
    if (category == null) return null;
    if (!await _confirm(
      'Approve this private recipe card?',
      'This deliberately shares these recipe fields:\n${habit.aspiration}\nAfter I ${habit.anchor}, I will ${habit.behavior}.\nThen I ${habit.celebration}.\nSpecies: ${habit.species}\nCategory: $category\n\nNo account identity, progress or habit ID is shared.',
      'Share this exact card',
    )) {
      return null;
    }
    return {
      'explicitChoice': true,
      'templateCategory': category,
      'aspiration': habit.aspiration,
      'anchor': habit.anchor,
      'behavior': habit.behavior,
      'celebration': habit.celebration,
      'species': habit.species,
    };
  }

  Future<void> _share() async {
    if (invitations == null) {
      setState(
        () => error = 'Connected invitations require an authenticated garden. No demo invitation was created.',
      );
      return;
    }
    Map<String, dynamic>? card;
    var busy = false;
    String? failure;
    InvitationReceipt? receipt;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          Future<void> send(String channel) async {
            update(() {
              busy = true;
              failure = null;
            });
            try {
              final created = await invitations!.create(
                channel,
                recipeCard: card,
              );
              final url = invitations!.webUri(created);
              if (!context.mounted) return;
              update(() => receipt = created);
              if (channel == 'link') {
                await Clipboard.setData(ClipboardData(text: url.toString()));
              } else if (channel == 'email') {
                if (!await launchUrl(
                  Uri(
                    scheme: 'mailto',
                    query:
                        'subject=${Uri.encodeComponent('A tiny step together with Bloomstep')}&body=${Uri.encodeComponent('Grow a tiny habit with Bloomstep. $url')}',
                  ),
                )) {
                  throw StateError(
                    'No email application is available. Nothing was sent.',
                  );
                }
              } else if (channel == 'native') {
                await NativeShare.share(url);
              }
              await widget.store.track(
                'share_initiated',
                properties: {
                  'channel': ['link', 'email'].contains(channel)
                      ? channel
                      : 'invite',
                  'platform': GardenStore.telemetryPlatform,
                },
              );
            } catch (e) {
              if (context.mounted) {
                update(
                  () => failure = 'Invitation needs a connection or retry: $e',
                );
              }
            } finally {
              if (context.mounted) update(() => busy = false);
            }
          }

          return AlertDialog(
            title: const Text('Invite someone to grow'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Default: no private habit text. We do not contact anyone. Email opens your composer; Windows share opens the OS panel, not proof of transmission.',
                    ),
                    Text(
                      card == null
                          ? 'No recipe card included.'
                          : 'Explicitly approved recipe card included.',
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final chosen = await _chooseShareCard();
                              if (context.mounted && chosen != null) {
                                update(() => card = chosen);
                              }
                            },
                      child: const Text('Choose and approve a recipe card'),
                    ),
                    if (card != null)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => update(() => card = null),
                        child: const Text('Remove recipe card'),
                      ),
                    if (receipt != null) ...[
                      Text(
                        '${receipt!.cached ? "Cached existing invitation" : "Server-created invitation"}; expires ${receipt!.expiresAt.toLocal()}.',
                      ),
                      SelectableText(invitations!.webUri(receipt!).toString()),
                      if (receipt!.channel == 'qr')
                        Semantics(
                          label: 'Server invitation QR code',
                          child: QrImageView(
                            data: invitations!.webUri(receipt!).toString(),
                            size: 180,
                            backgroundColor: Colors.white,
                          ),
                        ),
                    ],
                    if (failure != null) Text(failure!),
                    if (busy) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => send('link'),
                child: const Text('Copy link'),
              ),
              TextButton(
                onPressed: busy ? null : () => send('email'),
                child: const Text('Email invite'),
              ),
              TextButton(
                onPressed: busy ? null : () => send('qr'),
                child: const Text('Show QR'),
              ),
              TextButton(
                onPressed: busy ? null : () => send('native'),
                child: const Text('Windows share'),
              ),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _voice({String initialKind = 'Idea'}) async {
    final body = TextEditingController();
    var kind = initialKind;
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
                    decoration: InputDecoration(
                      labelText: kind == 'Rating'
                          ? 'Optional feedback'
                          : 'Your feedback',
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
                  title: Text(
                    record['kind'] == 'Rating'
                        ? '${record['rating']} / 5${(record['body'] as String).isEmpty ? '' : ' — ${record['body']}'}'
                        : record['body'] as String,
                  ),
                  subtitle: Text(
                    '${record['kind']} - ${record['status']}\n${(jsonDecode(record['replies'] as String) as List).join('\n')}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete this feedback',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await _removeRecord(
                            'voice',
                            record['id'] as String,
                          ) &&
                          context.mounted) {
                        Navigator.pop(context);
                      }
                    },
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
    var reminderObservation = await widget.store.reminderObservationOptedIn();
    String? analyticsWarning;
    var personalized =
        await widget.store.setting('personalizedTiming') == 'true';
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
                      'Off by default. Counts, up to 10 observed Dart/Flutter errors and 10 account-session/token attempts per session; fixed stage/outcome/category and elapsed time only. No message/stack, credentials, habit text, email or feedback. Pre-sign-in failures and provider choice are not captured. Native/process deaths are not captured; no crash-free claim. Turning off clears local queued events; previously synced events follow account deletion and retention rules.',
                    ),
                    value: analytics,
                    onChanged: widget.deviceGuest
                        ? null
                        : (v) async {
                            await _act(() async {
                              await widget.store.setSetting('analytics', '$v');
                              await widget.diagnostics?.consentChanged();
                              if (!v) {
                                await widget.installerMeasurement?.clear();
                              }
                            });
                            analytics =
                                await widget.store.setting('analytics') ==
                                'true';
                            reminderObservation = await widget.store
                                .reminderObservationOptedIn();
                            if (context.mounted) {
                              update(() => analyticsWarning = error);
                            }
                          },
                  ),
                  if (analyticsWarning != null)
                    SelectableText('Product-event choice: $analyticsWarning'),
                  ReminderObservationControls(
                    analyticsEnabled: analytics,
                    optedIn: reminderObservation,
                    onChanged: (value) async {
                      await _act(
                        () => widget.store.setReminderObservationConsent(value),
                      );
                      reminderObservation = await widget.store
                          .reminderObservationOptedIn();
                      if (context.mounted) {
                        update(() => analyticsWarning = error);
                      }
                    },
                  ),
                  MeasurementControls(
                    store: widget.store,
                    analytics: analytics,
                    installer: widget.installerMeasurement,
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
                    SwitchListTile(
                      title: const Text('Personalized reminder timing'),
                      subtitle: const Text(
                        'Device-only, off by default. When enabled, uses your last 14 practice times after five samples, rounded to 15 minutes. Local time, daylight-saving changes, quiet hours and daily limits still apply.',
                      ),
                      value: personalized,
                      onChanged: (value) async {
                        await widget.store.setSetting(
                          'personalizedTiming',
                          '$value',
                        );
                        update(() => personalized = value);
                      },
                    ),
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
                      title: const Text('Quiet for one hour'),
                      subtitle: const Text(
                        'Postpones unsent reminders only. A request already made today will not be repeated.',
                      ),
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
                      final owner = widget.store.account;
                      final generation = widget.store.syncGeneration;
                      final targetPath = widget.testExportPathSelector == null
                          ? (await getSaveLocation(
                              suggestedName: 'bloomstep-export.json',
                            ))?.path
                          : await widget.testExportPathSelector!();
                      if (targetPath == null) return;
                      widget.store.requireSyncSession(owner, generation);
                      Map<String, Object?> data;
                      final warnings = <String>[];
                      if (widget.identity != null) {
                        final prepared =
                            await SyncService(
                              widget.identity!,
                              widget.store,
                            ).prepareOwnerExport(
                              invitationExport: invitations == null
                                  ? null
                                  : () async =>
                                        (await invitations!.refreshStatus(
                                          export: true,
                                        )).json,
                            );
                        data = prepared.data;
                        warnings.addAll(prepared.warnings);
                      } else {
                        data = await widget.store.export();
                        data['supportReceiptExportWarning'] = 'No authenticated service session: server support receipts were not exported.';
                        warnings.add(
                          'No authenticated server support receipts.',
                        );
                      }
                      widget.store.requireSyncSession(owner, generation);
                      if (widget.identity != null &&
                          widget.identity!.account != owner) {
                        throw StateError(
                          'Account changed; export cancelled before saving. Sign in to the garden owner and try again.',
                        );
                      }
                      final bytes = utf8.encode(
                        const JsonEncoder.withIndent('  ').convert(data),
                      );
                      await XFile.fromData(
                        bytes,
                        mimeType: 'application/json',
                        name: 'bloomstep-export.json',
                      ).saveTo(targetPath);
                      if (mounted && warnings.isNotEmpty) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Local export saved. ${warnings.join(' ')} See the JSON export warnings; this is not a complete server export.',
                            ),
                          ),
                        );
                      }
                    }),
                  ),
                  ListTile(
                    title: const Text('Check for updates'),
                    leading: const Icon(Icons.system_update),
                    onTap: _checkUpdates,
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
                          await reminders?.disable(explicitChoice: false);
                          await widget.store.deleteLocalAccount();
                          if (pendingInvitation != null) {
                            await _clearCurrentInvitation(
                              pendingInvitation!.code,
                            );
                          }
                          invitationStatus = null;
                          acceptedCard = null;
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
                          await reminders?.disable(explicitChoice: false);
                          await SyncService(
                            widget.identity!,
                            widget.store,
                          ).deleteAccount();
                          if (pendingInvitation != null) {
                            await _clearCurrentInvitation(
                              pendingInvitation!.code,
                            );
                          }
                        });
                        if (context.mounted && mounted && error == null) {
                          Navigator.pop(context);
                          if (widget.onSignedOut != null) {
                            await widget.onSignedOut!(null);
                          } else if (mounted) {
                            Navigator.of(this.context)
                                .popUntil((route) => route.isFirst);
                          }
                        } else {
                          closing = false;
                        }
                      },
                    ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'No streak penalties. Your habit text is never sold or used for ads. AI features, if added, will be explained and optional. Original content inspired by behavior design research. Health recipes are not medical advice. Ages 16+.',
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

  Future<void> _signOut() async {
    if (working || closing || widget.identity == null) return;
    if (!await _confirm(
      'Sign out?',
      'Unsynced account data will be removed from this device. Export it in Settings first if needed. Your separate device garden is unchanged.',
      'Sign out',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      working = true;
      closing = true;
      error = null;
    });
    syncTimer?.cancel();
    String? warning;
    try {
      while (syncing) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await reminders?.disable(explicitChoice: false);
      await widget.store.deleteLocalAccount();
      if (pendingInvitation != null) {
        await _clearCurrentInvitation(pendingInvitation!.code);
      }
      try {
        await widget.identity!.signOut();
      } catch (e) {
        warning =
            'Signed out of this session, but saved authentication could not be cleared: $e. Try again before sharing this device.';
      }
      if (widget.onSignedOut != null) {
        await widget.onSignedOut!(warning);
      } else if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Sign-out cleanup did not complete: $e';
          working = false;
          closing = false;
        });
      }
    }
  }

  Future<void> _checkUpdates() async {
    Future<(UpdateInfo?, Object?)> checkSafely() async {
      try {
        return (await (widget.updateService ?? UpdateService()).check(), null);
      } catch (e) {
        return (null, e);
      }
    }

    final check = checkSafely();
    String? launchError;
    var opening = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => FutureBuilder<(UpdateInfo?, Object?)>(
          future: check,
          builder: (context, snapshot) {
            final release = snapshot.data?.$1;
            final failure = snapshot.data?.$2;
            return AlertDialog(
              title: const Text('Published releases'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bundled version: ${UpdateService.bundledVersion}',
                      ),
                      const SizedBox(height: 12),
                      if (snapshot.connectionState != ConnectionState.done)
                        const Text('Checking GitHub Releases…')
                      else if (failure != null)
                        Text('Update check failed: $failure')
                      else if (release == null)
                        const Text('No newer published release found')
                      else ...[
                        Text('Published version: ${release.version}'),
                        if (release.prerelease)
                          const Text(
                            'Unsigned preview: experimental and not a signed update. Windows may show an unknown-publisher warning.',
                          ),
                        const Text(
                          'You choose whether to open the release page and download anything. Bloomstep will not download or run an installer automatically.',
                        ),
                      ],
                      if (launchError != null) Text(launchError!),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Not now'),
                ),
                if (release != null && failure == null)
                  FilledButton(
                    onPressed: opening
                        ? null
                        : () async {
                            update(() {
                              opening = true;
                              launchError = null;
                            });
                            try {
                              if (!await launchUrl(
                                release.releasePage,
                                mode: LaunchMode.externalApplication,
                              )) {
                                throw StateError(
                                  'Release page could not be opened.',
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                update(() => launchError = '$e');
                              }
                            } finally {
                              if (context.mounted) {
                                update(() => opening = false);
                              }
                            }
                          },
                    child: const Text('Open release page'),
                  ),
              ],
            );
          },
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
        automaticallyImplyLeading: false,
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
          if (widget.profileBuilder == null)
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
                      if (widget.profileBuilder != null) ...[
                        widget.profileBuilder!(_signOut, () {
                          if (!working && !closing) unawaited(_settings());
                        }),
                        const SizedBox(height: 16),
                      ],
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
                      Text(
                        weeklyDue && habits.isNotEmpty
                            ? '$syncStatus • Weekly reflection is ready'
                            : syncStatus,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (widget.identity != null)
                        TextButton.icon(
                          onPressed: syncing ? null : _sync,
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync now'),
                        ),
                      if (pendingInvitation != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Someone invited you to grow a tiny habit.',
                                ),
                                const Text(
                                  'Accept only if you want. Acceptance is sent to the authenticated service; attribution comes from the server, not the link. A cosmetic reward requires the server to observe your first positive practice.',
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton(
                                      onPressed: working || invitations == null
                                          ? null
                                          : _acceptInvitation,
                                      child: const Text('Accept invitation'),
                                    ),
                                    TextButton(
                                      onPressed: working
                                          ? null
                                          : () => _act(
                                              () => _clearCurrentInvitation(
                                                pendingInvitation!.code,
                                              ),
                                            ),
                                      child: const Text('Decline invitation'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (acceptedCard != null)
                        TextButton(
                          onPressed: working ? null : _importCard,
                          child: const Text(
                            'Review shared recipe before planting',
                          ),
                        ),
                      if (invitations != null)
                        TextButton(
                          onPressed: working
                              ? null
                              : () => _act(_refreshInvitations),
                          child: const Text('Refresh invitation receipts'),
                        ),
                      if (invitationStatus != null &&
                          invitationStatus!.rewards.isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.local_florist,
                                  semanticLabel: 'Rare flower cosmetic',
                                ),
                                if (invitationStatus != null &&
                                    invitationStatus!.invitations.isNotEmpty)
                                  ExpansionTile(
                                    title: const Text(
                                      'Private invitation receipts',
                                    ),
                                    subtitle: Text(
                                      '${invitationStatus!.cached ? "Cached" : "Server"} status as of ${invitationStatus!.fetchedAt.toLocal()}',
                                    ),
                                    children: [
                                      for (final receipt
                                          in invitationStatus!.invitations)
                                        ListTile(
                                          title: Text(
                                            '${receipt['direction']} • ${receipt['channel']} • ${receipt['status']}',
                                          ),
                                          subtitle: Text(
                                            'Receipt expires ${DateTime.parse(receipt['expiresAt']).toLocal()}',
                                          ),
                                        ),
                                    ],
                                  ),
                                const Text(
                                  'Rare flower — server-granted cosmetic',
                                ),
                                Text(
                                  '${invitationStatus!.rewards.length} server grant(s). ${invitationStatus!.cached ? "Cached receipt" : "Server status"} as of ${invitationStatus!.fetchedAt.toLocal()}. No growth, ranking or streak advantage.',
                                ),
                                Text(invitationStatus!.json['definition']),
                              ],
                            ),
                          ),
                        ),
                      if (invitationWarning != null) Text(invitationWarning!),
                      if (configWarning != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(configWarning!),
                          ),
                        ),
                      if (error != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(error!),
                          ),
                        ),
                      if (ratingInvitation && error == null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'A positive moment in your garden. Want to share how Bloomstep feels? Ratings are optional and never affect your garden.',
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: working
                                          ? null
                                          : () {
                                              setState(
                                                () => ratingInvitation = false,
                                              );
                                              _voice(initialKind: 'Rating');
                                            },
                                      child: const Text('Rate Bloomstep'),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(
                                        () => ratingInvitation = false,
                                      ),
                                      child: const Text('Snooze 120 days'),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(
                                        () => ratingInvitation = false,
                                      ),
                                      child: const Text('Dismiss'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
                                          IconButton(
                                            tooltip: 'Delete this recipe',
                                            onPressed: working
                                                ? null
                                                : () => _removeRecord(
                                                    'habits',
                                                    habit.id,
                                                  ),
                                            icon: const Icon(
                                              Icons.delete_outline,
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
                                            Flexible(
                                              child: TextButton(
                                                onPressed: working
                                                    ? null
                                                    : () => _act(
                                                        () => widget.store.undo(
                                                          habit.id,
                                                        ),
                                                      ),
                                                child: const Text('Undo today'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (pausedReminders.contains(
                                        habit.id,
                                      )) ...[
                                        const Text(
                                          'Reminders are paused after seven unanswered requests. Your garden kept its growth. Resume only if you want; daily limits still apply.',
                                        ),
                                        TextButton(
                                          onPressed: working
                                              ? null
                                              : () => _act(() async {
                                                  if (reminders != null) {
                                                    await reminders!
                                                        .resumeHabit(habit.id);
                                                  } else {
                                                    await widget.store
                                                        .setSetting(
                                                          'ignored:${habit.id}',
                                                          '0',
                                                        );
                                                  }
                                                }),
                                          child: const Text(
                                            'Resume gentle reminders',
                                          ),
                                        ),
                                      ],
                                      TextButton.icon(
                                        onPressed: working
                                            ? null
                                            : () => _weeklyReflection(habit),
                                        icon: const Icon(
                                          Icons.self_improvement,
                                        ),
                                        label: const Text(
                                          'Weekly reflection / Recipe Doctor',
                                        ),
                                      ),
                                      TextButton(
                                        onPressed:
                                            working ||
                                                (naturalnessDates[habit.id]
                                                        ?.isAfter(
                                                          _now().toUtc(),
                                                        ) ??
                                                    false)
                                            ? null
                                            : () => _reflection(habit),
                                        child: Text(
                                          naturalnessDates[habit.id]?.isAfter(
                                                    _now().toUtc(),
                                                  ) ??
                                                  false
                                              ? 'Naturalness available ${localDate(naturalnessDates[habit.id]!.toLocal())}'
                                              : 'Check naturalness',
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: FilledButton.icon(
            onPressed: working ? null : _plant,
            icon: const Icon(Icons.add),
            label: const Text('Plant a habit'),
          ),
        ),
      ),
    );
  }
}
