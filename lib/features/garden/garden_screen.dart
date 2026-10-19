import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/garden_store.dart';
import '../../core/models.dart';
import '../../core/rules.dart';
import '../../services/identity.dart';
import '../../services/anonymous_feedback.dart';
import '../../services/sync_service.dart';
import '../../services/desktop_reminders.dart';
import '../../services/remote_config.dart';
import '../../services/update_service.dart';
import '../../services/invitation_service.dart';
import '../../services/invitation_intent.dart';
import '../../services/session_diagnostics.dart';
import 'reminder_observation_controls.dart';
import '../../services/installer_measurement.dart';
import 'measurement_controls.dart';
import '../../services/analytics_sandbox.dart';
import 'analytics_sandbox_controls.dart';

import 'package:launch_at_startup/launch_at_startup.dart';

import 'plant_art.dart';
import 'garden_moment.dart';
import 'recipe_builder.dart';
import 'invitation_dialog.dart';
import 'garden_canopy.dart';
import 'experience_copy.dart';
import '../../services/experience_experiments.dart';

const _testBuild = bool.fromEnvironment('BUDLARK_TEST_BUILD');

class GardenScreen extends StatefulWidget {
  const GardenScreen({
    super.key,
    required this.store,
    this.identity,
    this.anonymousFeedback,
    this.onOpenDeviceGarden,
    this.updateService,
    this.reminderGateway,
    this.configLoader,
    this.invitationInbox,
    this.invitationService,
    this.experienceResolver,
    this.diagnostics,
    this.installerMeasurement,
    this.analyticsSandbox,
    this.feedbackSender,
    this.testExportPathSelector,
    this.clock,
    this.deviceGuest = false,
    this.testDisableServices = false,
    this.profileBuilder,
    this.profileSummaryBuilder,
    this.profileDetailsBuilder,
    this.onSignedOut,
    this.onProfileShown,
    this.autoInviteFirstHabit = false,
    this.firstHabitInvitationReady = true,
    this.onFirstHabitInvited,
    this.contentRevision = 0,
  });
  final GardenStore store;
  final IdentityService? identity;
  final AnonymousFeedback? anonymousFeedback;
  final VoidCallback? onOpenDeviceGarden;
  final UpdateService? updateService;
  final ReminderGateway? reminderGateway;
  final Future<RemoteConfigResult> Function(GardenStore)? configLoader;
  final InvitationInbox? invitationInbox;
  final InvitationService? invitationService;
  final ExperienceResolver? experienceResolver;
  final SessionDiagnostics? diagnostics;
  final InstallerMeasurement? installerMeasurement;
  final AnalyticsSandbox? analyticsSandbox;
  final Future<bool> Function(String feedbackId)? feedbackSender;
  final Future<String?> Function()? testExportPathSelector;
  final DateTime Function()? clock;
  final bool deviceGuest;
  final bool testDisableServices;
  final Widget Function(Future<void> Function() signOut, VoidCallback manage)?
  profileBuilder;
  final Widget Function(Future<void> Function() signOut, VoidCallback manage)?
  profileSummaryBuilder;
  final Widget Function(Future<void> Function() signOut, VoidCallback manage)?
  profileDetailsBuilder;
  final Future<void> Function(String? warning)? onSignedOut;
  final VoidCallback? onProfileShown;
  final bool autoInviteFirstHabit;
  final bool firstHabitInvitationReady;
  final VoidCallback? onFirstHabitInvited;
  final int contentRevision;
  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen>
    with WidgetsBindingObserver {
  DateTime _now() => widget.clock?.call() ?? DateTime.now();
  List<Habit> habits = [];
  bool loading = true;
  bool working = false;
  bool reducedMotion = false;
  bool moreOpen = false;
  String? selectedHabitId;
  String? returnHabitId;
  String? returnDay;
  bool momentAnimating = false;
  final GlobalKey momentKey = GlobalKey();
  int? checkInMinute;
  bool remindersRequested = false;
  GrowthStage? previousStage;
  final Map<String, GrowthStage> pendingGrowth = {};
  final Set<String> completedMoments = {};
  String? loadedAccount;
  GardenStore? loadedStore;
  String? loadedDay;
  Timer? dayTimer;
  bool weeklyDue = false;
  bool ratingInvitation = false;
  int ratingMoment = 0;
  Map<String, DateTime?> naturalnessDates = {};
  Set<String> pausedReminders = {};
  String? error;
  String? configWarning;
  String? reminderSetupError;
  String? startupWarning;
  String syncStatus = 'Local garden';
  bool syncing = false;
  bool closing = false;
  bool reminderSetupInProgress = false;
  bool profileShown = false;
  bool firstHabitInvited = false;
  bool invitationScheduled = false;
  Timer? syncTimer;
  Timer? configExpiryTimer;
  DesktopReminders? reminders;
  InvitationService? invitations;
  late final ExperienceResolver experiences =
      widget.experienceResolver ?? ExperienceExperiments(widget.store);
  InvitationIntent? pendingInvitation;
  InvitationStatus? invitationStatus;
  Map<String, dynamic>? acceptedCard;
  String? invitationWarning;
  String? invitationSupportInfo;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        (Platform.isWindows ||
            widget.identity != null ||
            widget.reminderGateway != null)) {
      reminders = DesktopReminders(
        widget.store,
        _load,
        (message) {
          if (mounted) setState(() => error = message);
        },
        gateway: widget.reminderGateway,
        onPositiveCheckIn: _acknowledgeSavedPractice,
      );
      reminderSetupInProgress = true;
      reminders!
          .initialize()
          .catchError((Object e) {
            if (mounted) {
              final message = _reminderFailureMessage(e);
              setState(() {
                reminderSetupError = message;
                error = message;
              });
            }
          })
          .whenComplete(() async {
            await _initializeStartup();
            if (mounted) setState(() => reminderSetupInProgress = false);
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
    WidgetsBinding.instance.removeObserver(this);
    dayTimer?.cancel();
    syncTimer?.cancel();
    widget.invitationInbox?.removeListener(_inboxChanged);
    configExpiryTimer?.cancel();
    reminders?.dispose().catchError(
      (Object e) => debugPrint('Reminder cleanup failed: $e'),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !closing) {
      unawaited(_load());
    }
  }

  void _scheduleDayRefresh() {
    dayTimer?.cancel();
    final now = _now();
    final next = now.isUtc
        ? DateTime.utc(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day + 1);
    dayTimer = Timer(next.difference(now), () {
      if (mounted && !closing) unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(GardenScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedGarden = oldWidget.store != widget.store ||
        loadedAccount != widget.store.account;
    if (changedGarden) {
      loading = true;
      momentAnimating = false;
    }
    if (changedGarden ||
        oldWidget.contentRevision != widget.contentRevision) {
      unawaited(_load());
      if (widget.identity != null && !widget.testDisableServices) {
        unawaited(_sync());
      }
    }
    _scheduleFirstHabit();
  }

  void _scheduleFirstHabit() {
    if (loading ||
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
          !widget.autoInviteFirstHabit ||
          !widget.firstHabitInvitationReady ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      firstHabitInvited = true;
      widget.onFirstHabitInvited?.call();
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
        setState(
          () =>
              error = "Couldn't record your return. Your garden is unchanged.",
        );
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
        setState(
          () => syncStatus = "Couldn't sync your garden. Your saved garden is still on this device.",
        );
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
                () =>
                    configWarning = 'Your garden is using its usual settings.',
              );
            }
          },
        );
      }
      if (mounted) {
        setState(
          () => configWarning = result.warning == null
              ? null
              : 'Your garden is using its usual settings.',
        );
      }
    } catch (_) {
      reminders?.config = RemoteConfig.defaults;
      configExpiryTimer?.cancel();
      if (mounted) {
        setState(
          () => configWarning = 'Your garden is using its usual settings.',
        );
      }
    }
  }

  Future<void> _load() async {
    final store = widget.store;
    final account = store.account;
    final now = _now();
    try {
      final data = await store.habits(now: now);
      final reduce = await widget.store.setting('reducedMotion') == 'true';
      final minute = int.tryParse(
        await store.setting('reminderMinute') ?? '',
      );
      final requested = await store.setting('reminders') == 'true';
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
      if (mounted && identical(widget.store, store) && store.account == account) {
        setState(() {
          if (loadedDay != localDate(now)) pendingGrowth.clear();
          if (loadedAccount == account && loadedStore == store) {
            for (final habit in data) {
              final previous =
                  habits.where((old) => old.id == habit.id).firstOrNull;
              if (previous != null && previous.stage != habit.stage) {
                pendingGrowth[habit.id] = previous.stage;
              }
            }
          }
          if (loadedAccount != account || loadedStore != store) {
            selectedHabitId = null;
            returnHabitId = null;
            returnDay = null;
            momentAnimating = false;
            previousStage = null;
            pendingGrowth.clear();
            completedMoments.clear();
            for (final habit in data) {
              if (habit.today == CheckInResult.did ||
                  habit.today == CheckInResult.didMore) {
                completedMoments.add(_completionKey(habit, day: localDate(now)));
              }
            }
            moreOpen = false;
          }
          loadedAccount = account;
          loadedStore = store;
          loadedDay = localDate(now);
          habits = data;
          reducedMotion = reduce;
          checkInMinute = minute != null && minute >= 0 && minute < 1440
              ? minute
              : null;
          remindersRequested = requested;
          weeklyDue = weekly;
          naturalnessDates = dates;
          pausedReminders = paused;
          loading = false;
        });
        _scheduleDayRefresh();
        _scheduleFirstHabit();
      }
    } catch (e) {
      if (mounted && identical(widget.store, store) && store.account == account) {
        setState(() {
          error =
              "Couldn't read local garden storage. Reload your garden to try again.";
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
      debugPrint('Garden action failed: ${e.runtimeType}');
      if (mounted) {
        setState(() => error =
            "Couldn't save the change to local storage. Try the action again.");
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  String _reminderFailureMessage(Object failure) {
    if (failure is UnsupportedError) {
      return 'Windows reminders are only available on Windows.';
    }
    if (failure is StateError) {
      final message = failure.message;
      if (message.startsWith(
            'Windows notifications are blocked by device policy',
          ) ||
          message.startsWith('Windows notifications are disabled')) {
        return message;
      }
    }
    return 'Windows reminders couldn’t be started. Check Windows Settings > System > Notifications, then try again.';
  }

  Future<void> _openNotificationSettings() async {
    try {
      if (reminders == null) {
        throw StateError('Reminder setup is not available in this build.');
      }
      await reminders!.openNotificationSettings();
    } catch (failure) {
      if (mounted) {
        setState(() => error =
            'Could not open notification settings: $failure. Open Windows Settings > System > Notifications.');
      }
    }
  }

  Future<void> _initializeStartup() async {
    if (!mounted ||
        !Platform.isWindows ||
        widget.testDisableServices ||
        widget.reminderGateway != null) {
      return;
    }
    final owner = widget.store.account;
    final generation = widget.store.syncGeneration;
    try {
      if (await widget.store.setting('launchAtStartup') != null) return;
      widget.store.requireSyncSession(owner, generation);
      if (!await launchAtStartup.enable()) {
        throw StateError('Windows startup registration failed.');
      }
      widget.store.requireSyncSession(owner, generation);
      await widget.store.setSetting('launchAtStartup', 'true');
    } catch (_) {
      if (mounted) {
        setState(
          () => startupWarning = 'Could not start Budlark at Windows sign-in. Try again in Reminders.',
        );
      }
    }
  }

  Widget _statusDetails(String message, String details) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(message),
      ExpansionTile(
        title: const Text('Details'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(details),
          ),
        ],
      ),
    ],
  );

  Widget _invitationStatusDetails() => ExpansionTile(
    title: const Text('Invitation status'),
    subtitle: Text(
      invitationStatus!.cached ? 'Last saved status' : 'Up to date',
    ),
    children: [
      if (invitationStatus!.rewards.isNotEmpty)
        const ListTile(
          title: Text('Rare flower — server-granted cosmetic'),
          subtitle: Text(
            'A cosmetic only. No growth, ranking or streak advantage.',
          ),
        ),
      for (final receipt in invitationStatus!.invitations)
        ListTile(
          title: Text('${receipt['direction']} · ${receipt['status']}'),
          subtitle: Text(
            'Expires ${localDate(DateTime.parse(receipt['expiresAt']).toLocal())}',
          ),
        ),
    ],
  );

  Future<void> _changeReminderPreference(
    bool value,
    StateSetter update,
    BuildContext settingsContext,
  ) async {
    if (working || reminderSetupInProgress || reminders == null) return;
    final previousReminderError = reminderSetupError;
    setState(() {
      working = true;
      reminderSetupInProgress = true;
      if (error == previousReminderError) error = null;
      reminderSetupError = null;
    });
    try {
      if (value) {
        await reminders!.enable();
      } else {
        await reminders!.disable();
      }
      if (mounted) {
        await _load();
        if (widget.identity?.account != null) unawaited(_sync());
      }
    } catch (failure) {
      if (mounted) {
        setState(() => reminderSetupError = _reminderFailureMessage(failure));
      }
    } finally {
      if (mounted) {
        setState(() {
          working = false;
          reminderSetupInProgress = false;
        });
      }
      if (settingsContext.mounted) update(() {});
    }
  }

  Future<void> _acknowledgeSavedPractice(String habitId) async {
    if (!mounted || closing) return;
    final account = widget.store.account;
    final before = habits.where((habit) => habit.id == habitId).firstOrNull;
    await _load();
    if (!mounted || closing || account != widget.store.account) return;
    _showSavedMoment(habitId, before?.stage);
  }

  void _showSavedMoment(String habitId, GrowthStage? before) {
    final saved = habits.where((habit) => habit.id == habitId).firstOrNull;
    if (loadedDay != localDate(_now()) ||
        saved == null ||
        (saved.today != CheckInResult.did &&
            saved.today != CheckInResult.didMore)) {
      return;
    }
    final key = _completionKey(saved);
    if (!completedMoments.add(key)) return;
    setState(() {
      selectedHabitId = habitId;
      returnHabitId = habitId;
      returnDay = localDate(_now());
      previousStage = pendingGrowth.remove(habitId) ?? before ?? saved.stage;
      momentAnimating = true;
      moreOpen = false;
    });
  }

  String _completionKey(Habit habit, {String? day}) => jsonEncode([
    widget.store.account,
    habit.id,
    day ?? localDate(_now()),
    habit.recipeRevision,
  ]);

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
    if (mounted && !closing) {
      setState(() {
        selectedHabitId = planted!.id;
        returnHabitId = planted!.id;
        returnDay = localDate(_now());
        moreOpen = false;
      });
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
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
      recipe ? 'Delete recipe?' : 'Delete this feedback?',
      recipe ? 'This also deletes its check-ins and reflections.' : 'Removes only this feedback or rating and its private replies. Deletion cannot be undone. Offline deletion is queued until sync; the team can see it until the server receives deletion. A minimal ID-only marker prevents stale copies from returning.',
      recipe ? 'Delete' : 'Delete feedback',
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
    if (working || closing) return;
    final account = widget.store.account;
    final alreadyDone = loadedDay == localDate(_now()) &&
        (habit.today == CheckInResult.did ||
            habit.today == CheckInResult.didMore);
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
    }
    var saved = false;
    await _act(() async {
      await widget.store.checkIn(habit.id, result, reason: reason, now: _now());
      saved = true;
    });
    if (!mounted || !saved || account != widget.store.account) return;
    if (result != CheckInResult.notToday &&
        !alreadyDone) {
      _showSavedMoment(habit.id, habit.stage);
    }
    try {
      await reminders?.practiced(habit.id);
    } catch (failure) {
      if (mounted) {
        setState(() => error =
            'Practice saved, but reminder cleanup failed. Open More → Settings and privacy to retry reminders.');
      }
    }
    if (!mounted || result == CheckInResult.notToday) return;
    unawaited(_offerRatingAfterCelebration(
      Future<void>.delayed(GardenMoment.duration),
      ratingMoment,
    ));
  }

  Future<void> _offerRatingAfterCelebration(
    Future<void> closed,
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
        setState(
          () => error = "Couldn't save the rating invitation. Try again.",
        );
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
    const questions = [
      'Starting feels automatic',
      'My routine reminds me without effort',
      'The tiny step needs little thought',
      'I begin naturally when my anchor happens',
    ];
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
                    Text(questions[i]),
                    Semantics(
                      label: questions[i],
                      child: Slider(
                        value: scores[i].toDouble(),
                        min: 1,
                        max: 7,
                        divisions: 6,
                        label: '${scores[i]}',
                        onChanged: (v) => update(() => scores[i] = v.round()),
                        semanticFormatterCallback: (value) =>
                            '${value.round()} of 7',
                      ),
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
              'Your recent practice and reflections met the graduation criteria. This is a milestone; keep adapting your habit whenever it suits you.',
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
          invitationSupportInfo = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          final failure = error is InvitationFailure
              ? error
              : const InvitationFailure(
                  InvitationFailureKind.unknown,
                  InvitationPhase.status,
                );
          invitationWarning = failure.message;
          invitationSupportInfo =
              '${failure.supportCode}\nSaved invitation status is last-known information, not a new reward.';
        });
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
    if (!await _confirm(
      'Approve this private recipe card?',
      'This deliberately shares these recipe fields:\n${habit.aspiration}\nAfter I ${habit.anchor}, I will ${habit.behavior}.\nThen I ${habit.celebration}.\nSpecies: ${habit.species}\n\nNo account identity, progress or habit ID is shared.',
      'Share this exact card',
    )) {
      return null;
    }
    return {
      'explicitChoice': true,
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
    await showDialog<void>(
      context: context,
      builder: (_) => InvitationDialog(
        service: invitations!,
        store: widget.store,
        hasRecipes: habits.isNotEmpty,
        chooseCard: _chooseShareCard,
        reducedMotion: reducedMotion,
        experiments: experiences,
      ),
    );
  }

  Future<void> _voice() async {
    final body = TextEditingController();
    int? rating;
    String? feedbackId;
    String? anonymousRequestId;
    String? status;
    bool sending = false;
    bool received = false;
    final owner = widget.store.account;
    final generation = widget.store.syncGeneration;
    try {
      final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            scrollable: true,
            title: const Text('Send feedback'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('How does Budlark feel? A rating is optional.'),
                  Wrap(
                    children: [
                      for (var star = 1; star <= 5; star++)
                        IconButton(
                          tooltip: '$star of 5 stars',
                          isSelected: rating != null && star <= rating!,
                          onPressed: sending || feedbackId != null
                              ? null
                              : () => update(() => rating = star),
                          icon: const Icon(Icons.star_border),
                          selectedIcon: const Icon(Icons.star),
                        ),
                    ],
                  ),
                  TextField(
                    controller: body,
                    enabled: !sending && feedbackId == null,
                    maxLength: 2000,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Your feedback',
                      hintText: 'Leave out passwords, private account information and sensitive habit details.',
                    ),
                  ),
                  Text(
                    widget.anonymousFeedback != null
                        ? 'Send only this feedback; never your account or habits.'
                        : widget.deviceGuest
                        ? 'Saved on this device only; no team delivery is connected.'
                        : 'Sent only when you choose Send feedback. Unsent feedback stays on this device until it can sync.',
                  ),
                  if (status != null)
                    Semantics(liveRegion: true, child: Text(status!)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(context),
                child: Text(received ? 'Done' : 'Close'),
              ),
              if (!received &&
                  !(widget.deviceGuest &&
                      widget.anonymousFeedback == null &&
                      feedbackId != null))
                FilledButton(
                  onPressed: sending
                      ? null
                      : () async {
                          if (body.text.trim().isEmpty && rating == null) {
                            update(
                              () => status = 'Add a rating or a message first.',
                            );
                            return;
                          }
                          update(() {
                            sending = true;
                            status = widget.deviceGuest ? 'Saving…' : 'Sending…';
                          });
                          try {
                            widget.store.requireSyncSession(owner, generation);
                            final anonymous = widget.anonymousFeedback;
                            if (anonymous != null) {
                              anonymousRequestId ??= await anonymous.enqueue(
                                consent: true,
                                text: body.text.trim().isEmpty ? null : body.text,
                                rating: rating,
                              );
                              feedbackId = anonymousRequestId;
                              final receipt = await anonymous.submitNext(
                                requestId: anonymousRequestId,
                              );
                              if (context.mounted) {
                                update(() {
                                  received = receipt?.requestId == anonymousRequestId;
                                  status = received
                                      ? 'Received by the team.'
                                      : 'Saved on this device — not sent to the team.';
                                });
                              }
                              return;
                            }
                            feedbackId ??= await widget.store.submitVoice(
                              'General',
                              body.text,
                              rating: rating,
                            );
                            bool acknowledged = false;
                            if (widget.deviceGuest) {
                              acknowledged = false;
                            } else if (widget.feedbackSender != null) {
                              acknowledged = await widget.feedbackSender!(
                                feedbackId!,
                              );
                            } else if (widget.identity != null) {
                              final service = SyncService(
                                widget.identity!,
                                widget.store,
                              );
                              await service.sync();
                              acknowledged = (await widget.store.voice()).any(
                                (row) =>
                                    row['id'] == feedbackId &&
                                    row['status'] == 'received',
                              );
                            }
                            widget.store.requireSyncSession(owner, generation);
                            if (context.mounted) {
                              update(() {
                                received = acknowledged;
                                status = widget.deviceGuest
                                    ? 'Saved on this device — not sent to the team.'
                                    : acknowledged
                                    ? 'Received by the team.'
                                    : 'Not sent — retry when you are connected.';
                              });
                            }
                          } catch (failure) {
                            if (context.mounted) {
                              update(
                                () => status = anonymousRequestId != null
                                    ? 'Saved on this device — not received. $failure'
                                    : widget.deviceGuest
                                    ? 'Could not save feedback: $failure'
                                    : 'Not sent — retry when you are connected.',
                              );
                            }
                          } finally {
                            if (context.mounted) update(() => sending = false);
                          }
                        },
                  child: Text(
                    feedbackId == null ? 'Send feedback' : 'Retry sending',
                  ),
                ),
            ],
          ),
        ),
      );
      await Navigator.of(context).push(route);
      await route.completed;
    } finally {
      body.dispose();
    }
  }

  Future<void> _settings() async {
    final owner = widget.store.account;
    final generation = widget.store.syncGeneration;
    var analytics = await widget.store.setting('analytics') == 'true';
    var reminderObservation = await widget.store.reminderObservationOptedIn();
    String? analyticsWarning;
    var personalized =
        await widget.store.setting('personalizedTiming') == 'true';
    var startOnSignIn = await widget.store.setting('launchAtStartup') == 'true';
    if (!mounted) return;
    if (reminderSetupError != null && error == reminderSetupError) {
      setState(() => error = null);
    }
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Settings'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExpansionTile(
                    title: const Text('Profile & account'),
                    onExpansionChanged: (expanded) {
                      if (expanded &&
                          !profileShown &&
                          widget.profileBuilder != null) {
                        profileShown = true;
                        widget.onProfileShown?.call();
                      }
                    },
                    children: [
                      if (widget.profileBuilder != null)
                        widget.profileBuilder!(_signOut, () {})
                      else
                        const ListTile(
                          title: Text('Device garden'),
                          subtitle: Text('Your habits stay on this device.'),
                        ),
                      ListTile(
                        title: const Text('Garden status'),
                        subtitle: Text(syncStatus),
                      ),
                      if (widget.identity != null)
                        ListTile(
                          title: const Text('Sync now'),
                          leading: const Icon(Icons.sync),
                          onTap: syncing ? null : _sync,
                        ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('Advanced'),
                    children: [
                      if (widget.onOpenDeviceGarden != null)
                        TextButton(
                          onPressed: working ? null : widget.onOpenDeviceGarden,
                          child: const Text('Use a device-only garden'),
                        ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('Privacy & measurement'),
                    children: [
                      SwitchListTile(
                        title: const Text('Share product event counts'),
                        subtitle: const Text(
                          'Optional counts only; off by default. Never your private text.',
                        ),
                        value: analytics,
                        onChanged: widget.deviceGuest
                            ? null
                            : (v) async {
                                await _act(() async {
                                  await widget.store.setSetting(
                                    'analytics',
                                    '$v',
                                  );
                                  await widget.diagnostics?.consentChanged();
                                  if (!v) {
                                    await widget.analyticsSandbox
                                        ?.consentChanged(false);
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
                      const ExpansionTile(
                        title: Text('What these counts include'),
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Text(
                              'Shares up to 10 error types and 10 sign-in or session attempts per session, plus basic counts. Turning off stops future sharing and clears unsent counts; sent counts follow account deletion and retention rules. Counts use set categories, app stages and elapsed time for errors Budlark sees while open, plus sign-in and session attempts after sign-in. We do not collect error messages or stacks, what you type, passwords or credentials, private account details, sensitive habit details, email, feedback or which sign-in provider you use. Device-only gardens send no counts. App closures Budlark cannot observe are not included, so this is not a crash-free measure.',
                            ),
                          ),
                        ],
                      ),
                      if (analyticsWarning != null)
                        SelectableText(
                          'Product-event choice: $analyticsWarning',
                        ),
                      if (widget.analyticsSandbox != null)
                        AnalyticsSandboxControls(
                          key: ValueKey(analytics),
                          sandbox: widget.analyticsSandbox!,
                        ),
                      ReminderObservationControls(
                        analyticsEnabled: analytics,
                        optedIn: reminderObservation,
                        onChanged: (value) async {
                          await _act(
                            () => widget.store.setReminderObservationConsent(
                              value,
                            ),
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
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('Reminders'),
                    children: [
                      if (reminders == null)
                        ListTile(
                          title: const Text('Reminders need the Windows app.'),
                          subtitle: Text(
                            widget.testDisableServices
                                ? 'This test build disables reminder services.'
                                : 'Open the installed Budlark app on Windows to set up reminders.',
                          ),
                        ),
                      if (reminders != null)
                        SwitchListTile(
                          title: const Text('Gentle Windows reminders'),
                          subtitle: const Text(
                            'On by default. Switch off any time. Closing the window keeps Budlark running. Delivery stops when you exit.',
                          ),
                          value: reminders!.requestedEnabled,
                          onChanged: working || reminderSetupInProgress
                              ? null
                              : (value) => _changeReminderPreference(
                                  value,
                                  update,
                                  context,
                                ),
                        ),
                      if (reminders != null &&
                          reminders!.requestedEnabled &&
                          !reminders!.enabled)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reminderSetupInProgress
                                    ? 'Windows reminders are starting.'
                                    : reminders!.unavailableReason ??
                                          'Your reminder preference is on, but Windows delivery is not active.',
                              ),
                              if (!reminderSetupInProgress)
                                const Text(
                                  'If Budlark is missing from the app list, reinstall the latest installer, open Budlark, then retry reminders.',
                                ),
                              if (!reminderSetupInProgress && Platform.isWindows)
                                TextButton(
                                  onPressed: () async {
                                    await _openNotificationSettings();
                                    if (context.mounted) update(() {});
                                  },
                                  child: const Text('Open Windows notification settings'),
                                ),
                              if (!reminderSetupInProgress)
                                TextButton(
                                  onPressed: working
                                      ? null
                                      : () => _changeReminderPreference(
                                          true,
                                          update,
                                          context,
                                        ),
                                  child: const Text('Retry Windows reminders'),
                                ),
                            ],
                          ),
                        ),
                      if (reminders != null && reminderSetupError != null)
                        _statusDetails(
                          'Windows reminders need your attention.',
                          reminderSetupError!,
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
                        SwitchListTile(
                          title: const Text('Launch at Windows sign-in'),
                          subtitle: const Text(
                            'On by default for new choices. Starts only this installed app, not a system service.',
                          ),
                          value: startOnSignIn,
                          onChanged: (value) async {
                            try {
                              widget.store.requireSyncSession(
                                owner,
                                generation,
                              );
                              final changed = value
                                  ? await launchAtStartup.enable()
                                  : await launchAtStartup.disable();
                              if (!changed) {
                                throw StateError('Startup preference failed.');
                              }
                              widget.store.requireSyncSession(
                                owner,
                                generation,
                              );
                              await widget.store.setSetting(
                                'launchAtStartup',
                                '$value',
                              );
                              if (context.mounted) {
                                update(() {
                                  startOnSignIn = value;
                                  startupWarning = null;
                                });
                              }
                            } catch (_) {
                              if (context.mounted) {
                                update(
                                  () => startupWarning = 'Could not change Windows sign-in launch. Check your Windows startup settings and retry.',
                                );
                              }
                            }
                          },
                        ),
                        if (startupWarning != null)
                          ListTile(title: Text(startupWarning!)),
                      ],
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('Garden & data'),
                    children: [
                      if (weeklyDue && habits.isNotEmpty)
                        const ListTile(
                          title: Text('Weekly reflection is ready'),
                          subtitle: Text('Open More on a recipe to reflect.'),
                        ),
                      if (invitationStatus != null) _invitationStatusDetails(),
                      ListTile(
                        title: const Text('Export my data (JSON)'),
                        leading: const Icon(Icons.download),
                        onTap: () => _act(() async {
                          final owner = widget.store.account;
                          final generation = widget.store.syncGeneration;
                          final targetPath =
                              widget.testExportPathSelector == null
                              ? (await getSaveLocation(
                                  suggestedName: 'budlark-export.json',
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
                            name: 'budlark-export.json',
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
                        title: const Text('Delete local garden'),
                        subtitle: const Text(
                          'Cloud account deletion requires the connected service.',
                        ),
                        leading: const Icon(Icons.delete_outline),
                        onTap: () async {
                          if (await _confirm(
                            'Delete local data?',
                            'This deletes habits, check-ins, and reflections saved on this device—not your Microsoft or Google account.',
                            'Delete',
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
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('App & support'),
                    children: [
                      SwitchListTile(
                        title: const Text('Reduced motion'),
                        value: reducedMotion,
                        onChanged: (value) async {
                          await _act(
                            () => widget.store.setSetting(
                              'reducedMotion',
                              '$value',
                            ),
                          );
                          if (context.mounted) update(() {});
                        },
                      ),
                      ListTile(
                        title: const Text('Check for updates'),
                        leading: const Icon(Icons.system_update),
                        onTap: _checkUpdates,
                      ),
                      ListTile(
                        title: const Text('Send feedback'),
                        leading: const Icon(Icons.chat_bubble_outline),
                        onTap: _voice,
                      ),
                      if (configWarning != null)
                        ListTile(title: Text(configWarning!)),
                      if (invitations != null)
                        ListTile(
                          title: const Text('Refresh invitation status'),
                          onTap: () => _act(_refreshInvitations),
                        ),
                      if (invitationWarning != null)
                        _statusDetails(
                          invitationWarning!,
                          invitationSupportInfo ?? 'Try refreshing invitation status when connected.',
                        ),
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'No streak penalties. Your habit text is never sold or used for ads. AI features, if added, will be explained and optional. Original content inspired by behavior design research. Health recipes are not medical advice. Ages 16+.',
                        ),
                      ),
                    ],
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

  Future<void> _profile() async {
    final builder = widget.profileBuilder;
    if (builder == null) {
      await _settings();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              builder(_signOut, _settings),
              ExpansionTile(
                title: const Text('Linked providers'),
                children: [
                  Text('Current sign-in: ${widget.identity?.profile?.signInProvider ?? "Not available"}'),
                  const Text('Linked-provider management is not available in this build.'),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _settings();
            },
            child: const Text('Account settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    if (working || closing || widget.identity == null) return;
    if (!await _confirm(
      'Sign out?',
      'Unsynced account data is removed from this device; your separate device garden stays here. Export it first if you need a copy.',
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
        warning = 'Couldn’t finish sign-out. Saved sign-in may remain on this device; clear it before sharing this device.';
      }
      if (widget.onSignedOut != null) {
        await widget.onSignedOut!(warning);
      } else if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Could not finish sign-out. Check that saved sign-in is cleared before sharing this device.';
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
                      else if (failure != null) ...[
                        const Text('Couldn’t check for updates. Please try again.'),
                        Text(
                          '$failure\nCheck your connection and retry. No installer was downloaded.',
                        ),
                      ]
                      else if (release == null)
                        const Text('No newer published release found')
                      else ...[
                        Text('Published version: ${release.version}'),
                        if (release.prerelease)
                          const Text(
                            'Unsigned preview: experimental and not a signed update. Windows may show an unknown-publisher warning.',
                          ),
                        const Text(
                          'You choose whether to open the release page and download anything. Budlark will not download or run an installer automatically.',
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
                                update(
                                  () => launchError =
                                      "Couldn't open the release page.",
                                );
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

  Widget _plantAction(ThemeData theme) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 300),
    child: FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
      onPressed: working ? null : _plant,
      icon: ExcludeSemantics(
        child: Container(
          width: 32,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const FittedBox(
            child: SizedBox(
              width: 100,
              height: 130,
              child: PlantArt(stage: GrowthStage.sprout, species: 'Fern'),
            ),
          ),
        ),
      ),
      label: const Text('Plant a habit'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (moreOpen) return _buildMore(context);
    final active = habits.where((habit) => habit.status == 'active').toList();
    final habit = active
            .where((habit) => habit.id == selectedHabitId)
            .firstOrNull ??
        active.where((habit) => habit.today == null).firstOrNull ??
        active.firstOrNull;
    final done = loadedDay == localDate(_now()) &&
        (habit?.today == CheckInResult.did ||
            habit?.today == CheckInResult.didMore);
    final returning = habit != null &&
        (done ||
            (returnHabitId == habit.id && returnDay == localDate(_now())));
    final theme = Theme.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.height <= 600 ||
        MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final minute = checkInMinute;
    final delivery = !remindersRequested
        ? 'reminders off'
        : pausedReminders.contains(habit?.id)
            ? 'reminders paused'
            : reminders?.enabled == true
                ? 'reminders enabled'
                : 'Windows delivery inactive';
    final time = minute == null
        ? 'Check-in time not set · choose in More'
        : 'Check-in ${_minuteLabel(minute)} · $delivery';
    final warnings = <String>{
      if (error != null) error!,
      if (reminderSetupError != null) reminderSetupError!,
      if (configWarning != null) configWarning!,
      if (startupWarning != null) startupWarning!,
      if (invitationWarning != null) invitationWarning!,
    };
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: MediaQuery.textScalerOf(context).scale(48) + 24,
        actions: [
          if (widget.profileSummaryBuilder != null &&
              (ModalRoute.of(context)?.isCurrent ?? true))
            SizedBox(
              width: (viewport.width / 2).clamp(0, 320).toDouble(),
              child: widget.profileSummaryBuilder!(_signOut, _profile),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, compact ? 0 : 24, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      if (compact)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 100,
                              height: 80,
                              child: _momentFor(habit),
                            ),
                            Flexible(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  habit?.aspiration ?? 'Your garden',
                                  style: theme.textTheme.headlineMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Semantics(
                          header: true,
                          child: Text(
                            habit?.aspiration ?? 'Your garden',
                            style: theme.textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (!compact)
                        SizedBox(
                          width: 300,
                          height: 200,
                          child: _momentFor(habit),
                        ),
                      if (habit == null)
                        const Text('Choose one tiny habit to begin.')
                      else
                        Column(
                          children: [
                            Text(
                              done ? 'Done today' : 'After I ${habit.anchor}',
                              textAlign: TextAlign.center,
                            ),
                            if (!done)
                              Text(
                                habit.behavior,
                                textAlign: TextAlign.center,
                              )
                            else
                              Text(
                                'Now ${habit.celebration}.',
                                textAlign: TextAlign.center,
                              ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: working
                            ? null
                            : habit == null
                                ? _plant
                                : () => _check(habit, CheckInResult.did),
                        child: Text(habit == null ? 'Plant a habit' : 'I did it'),
                      ),
                      if (returning) ...[
                        const SizedBox(height: 8),
                        Text(
                          'See you tomorrow after I ${habit.anchor}.',
                          textAlign: TextAlign.center,
                        ),
                        Text(time, textAlign: TextAlign.center),
                      ],
                      if (ModalRoute.of(context)?.isCurrent ?? true)
                        TextButton(
                          key: const ValueKey('garden-more'),
                          onPressed: working
                              ? null
                              : () => setState(() {
                                  momentAnimating = false;
                                  moreOpen = true;
                                }),
                          child: Text(
                            pendingInvitation != null || acceptedCard != null
                                ? 'More · invitation'
                                : 'More',
                          ),
                        ),
                      for (final warning in warnings)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                Text(warning),
                                TextButton(
                                  onPressed: working
                                      ? null
                                      : () async {
                                          setState(() => error = null);
                                          await _load();
                                        },
                                  child: const Text('Reload garden'),
                                ),
                                TextButton(
                                  onPressed: working ? null : _settings,
                                  child: const Text('Settings and privacy'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  String _minuteLabel(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  Widget _momentFor(Habit? habit) => GardenMoment(
    key: momentKey,
    stage: habit?.stage ?? GrowthStage.seed,
    species: habit?.species ?? 'Cosmos',
    reducedMotion: reducedMotion,
    previousStage: previousStage,
    animate: momentAnimating && selectedHabitId == habit?.id,
    onFinished: () {
      if (mounted && momentAnimating) {
        setState(() => momentAnimating = false);
      }
    },
    completion: loadedDay == localDate(_now()) &&
            habit != null &&
            (habit.today == CheckInResult.did ||
                habit.today == CheckInResult.didMore)
        ? _completionKey(habit)
        : null,
  );

  Widget _buildMore(BuildContext context) {
    final theme = Theme.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final shortWindow = viewport.height <= 512;
    final compactPracticeFirst =
        habits.isNotEmpty &&
        (viewport.height <= 600 || (viewport.width <= 700 && textScale >= 1.5));
    final habitCardWidth = compactPracticeFirst && viewport.height <= 600
        ? (viewport.width - 32).clamp(0, double.infinity).toDouble()
        : (viewport.width - 64).clamp(0, 350).toDouble();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back to your habit',
          onPressed: () => setState(() => moreOpen = false),
          icon: const Icon(Icons.arrow_back),
        ),
        toolbarHeight: MediaQuery.textScalerOf(context).scale(48) + 24,
        title: widget.profileSummaryBuilder == null ? const Text('Budlark') : null,
        actions: [
          IconButton(
            tooltip: 'Invite a friend',
            onPressed: working ? null : _share,
            icon: const Icon(Icons.spa_outlined),
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
          if (widget.profileSummaryBuilder != null &&
              (ModalRoute.of(context)?.isCurrent ?? true))
            SizedBox(
              width: (viewport.width - 232).clamp(0, 320).toDouble(),
              child: widget.profileSummaryBuilder!(_signOut, _profile),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: compactPracticeFirst
                  ? EdgeInsets.fromLTRB(16, shortWindow ? 4 : 8, 16, 24)
                  : const EdgeInsets.fromLTRB(32, 24, 32, 100),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!compactPracticeFirst || habits.isEmpty) ...[
                        GardenCanopy(
                          key: const ValueKey('garden-canopy'),
                          reducedMotion: reducedMotion,
                          compact: habits.isNotEmpty,
                          heading: Semantics(
                            header: true,
                            child: ExperienceCopy(
                              experiments: experiences,
                              surface: ExperienceSurface.gardenPrompt,
                              builder: (context, copy) => Text(
                                copy,
                                style: habits.isEmpty
                                    ? theme.textTheme.headlineMedium
                                    : theme.textTheme.titleLarge,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
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
                      if (error != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Something needs your attention.'),
                                SelectableText(error!),
                                TextButton(
                                  onPressed: working
                                      ? null
                                      : () async {
                                          setState(() => error = null);
                                          await _load();
                                        },
                                  child: const Text('Reload garden'),
                                ),
                                if (reminderSetupError != null &&
                                    error == reminderSetupError) ...[
                                  Text(reminders?.unavailableReason ?? reminderSetupError!),
                                  TextButton(
                                    onPressed: _settings,
                                    child: const Text('Set up reminders'),
                                  ),
                                  if (Platform.isWindows && reminders != null)
                                    TextButton(
                                      onPressed: _openNotificationSettings,
                                      child: const Text('Open Windows notification settings'),
                                    ),
                                ],
                              ],
                            ),
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
                                  'A positive moment in your garden. Want to share how Budlark feels? Ratings are optional and never affect your garden.',
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
                                              _voice();
                                            },
                                      child: const Text('Rate Budlark'),
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
                              width: habitCardWidth,
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                child: Padding(
                                  padding: EdgeInsets.all(
                                    compactPracticeFirst
                                        ? shortWindow
                                              ? 8
                                              : 12
                                        : 20,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              habit.status == 'graduated'
                                                  ? 'Graduation milestone · ${habit.aspiration}'
                                                  : habit.aspiration,
                                              style: compactPracticeFirst
                                                  ? theme.textTheme.titleMedium
                                                  : theme.textTheme.titleLarge,
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            tooltip:
                                                'More for ${habit.aspiration}',
                                            enabled: !working,
                                            onSelected: (action) async {
                                              switch (action) {
                                                case 'edit':
                                                  await _edit(habit);
                                                case 'delete':
                                                  await _removeRecord(
                                                    'habits',
                                                    habit.id,
                                                  );
                                                case 'weekly':
                                                  await _weeklyReflection(
                                                    habit,
                                                  );
                                                case 'naturalness':
                                                  await _reflection(habit);
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Text('Edit recipe'),
                                              ),
                                              const PopupMenuItem(
                                                value: 'weekly',
                                                child: Text(
                                                  'Weekly reflection / Recipe Doctor',
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'naturalness',
                                                enabled:
                                                    !(naturalnessDates[habit.id]
                                                            ?.isAfter(
                                                              _now().toUtc(),
                                                            ) ??
                                                        false),
                                                child: Text(
                                                  naturalnessDates[habit.id]
                                                              ?.isAfter(
                                                                _now().toUtc(),
                                                              ) ??
                                                          false
                                                      ? 'Naturalness available ${localDate(naturalnessDates[habit.id]!.toLocal())}'
                                                      : 'Check naturalness',
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Text(
                                                  'Delete this recipe',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      if (!compactPracticeFirst ||
                                          viewport.height > 600)
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
                                              height: compactPracticeFirst
                                                  ? 96
                                                  : 180,
                                              width: double.infinity,
                                              child: PlantArt(
                                                stage: habit.stage,
                                                species: habit.species,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (!compactPracticeFirst ||
                                          viewport.height > 600)
                                        Text(
                                          '${habit.stage.name.toUpperCase()}  /  ${habit.practiceCount} tiny steps',
                                          style: theme.textTheme.labelLarge,
                                        ),
                                      SizedBox(
                                        height: compactPracticeFirst ? 4 : 12,
                                      ),
                                      Text(
                                        habit.recipe,
                                        style: compactPracticeFirst
                                            ? theme.textTheme.bodyLarge
                                            : theme.textTheme.titleMedium,
                                      ),
                                      SizedBox(
                                        height: compactPracticeFirst ? 4 : 8,
                                      ),
                                      Text('Then I ${habit.celebration}.'),
                                      SizedBox(
                                        height: compactPracticeFirst
                                            ? shortWindow
                                                  ? 4
                                                  : 8
                                            : 16,
                                      ),
                                      if (habit.status != 'graduated')
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                      ),
                                                  minimumSize: const Size(
                                                    0,
                                                    48,
                                                  ),
                                                ),
                                                onPressed: working
                                                    ? null
                                                    : () => _check(
                                                        habit,
                                                        CheckInResult.did,
                                                      ),
                                                child: const Text('Did it'),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                      ),
                                                  minimumSize: const Size(
                                                    0,
                                                    48,
                                                  ),
                                                ),
                                                onPressed: working
                                                    ? null
                                                    : () => _check(
                                                        habit,
                                                        CheckInResult.didMore,
                                                      ),
                                                child: const Text('Did more'),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                      ),
                                                  minimumSize: const Size(
                                                    0,
                                                    48,
                                                  ),
                                                ),
                                                onPressed: working
                                                    ? null
                                                    : () => _check(
                                                        habit,
                                                        CheckInResult.notToday,
                                                      ),
                                                child: const Text('Not today'),
                                              ),
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
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (compactPracticeFirst) ...[
                        const SizedBox(height: 8),
                        GardenCanopy(
                          key: const ValueKey('garden-canopy'),
                          reducedMotion: reducedMotion,
                          compact: true,
                          heading: Semantics(
                            header: true,
                            child: ExperienceCopy(
                              experiments: experiences,
                              surface: ExperienceSurface.gardenPrompt,
                              builder: (context, copy) =>
                                  Text(copy, style: theme.textTheme.titleLarge),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: _plantAction(theme),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: compactPracticeFirst
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Align(heightFactor: 1, child: _plantAction(theme)),
              ),
            ),
    );
  }
}
