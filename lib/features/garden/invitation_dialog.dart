import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/garden_store.dart';
import '../../core/models.dart';
import '../../services/invitation_service.dart';
import '../../services/native_share.dart';
import 'plant_art.dart';
import 'experience_copy.dart';
import '../../services/experience_experiments.dart';

class InvitationDialog extends StatefulWidget {
  const InvitationDialog({
    super.key,
    required this.service,
    required this.store,
    required this.hasRecipes,
    required this.chooseCard,
    this.reducedMotion = false,
    this.experiments,
  });

  final InvitationService service;
  final GardenStore store;
  final bool hasRecipes;
  final Future<Map<String, dynamic>?> Function() chooseCard;
  final bool reducedMotion;
  final ExperienceResolver? experiments;

  @override
  State<InvitationDialog> createState() => _InvitationDialogState();
}

class _InvitationDialogState extends State<InvitationDialog> {
  Map<String, dynamic>? card;
  InvitationReceipt? receipt;
  bool busy = false;
  String? failure;
  String? supportInfo;
  String? supportCopyOutcome;
  String? outcome;
  late final ExperienceResolver experiments =
      widget.experiments ?? ExperienceExperiments(widget.store);
  ExperienceAssignment? assignment;

  Future<void> observe(ExperienceOutcome outcome) async {
    final shown = assignment;
    if (shown == null) return;
    try {
      await experiments.outcome(shown, outcome);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'invitation experience',
          context: ErrorDescription(
            'while recording an optional experience outcome',
          ),
        ),
      );
    }
  }

  Future<void> share(String channel) async {
    if (busy) return;
    var phase = InvitationPhase.creation;
    setState(() {
      busy = true;
      failure = null;
      supportInfo = null;
      supportCopyOutcome = null;
      receipt = null;
      outcome = null;
    });
    try {
      final created = await widget.service.create(channel, recipeCard: card);
      if (!mounted) return;
      final url = widget.service.webUri(created);
      phase = InvitationPhase.handoff;
      if (channel == 'link') {
        await Clipboard.setData(ClipboardData(text: url.toString()));
      } else if (channel == 'email') {
        if (!await launchUrl(
          Uri(
            scheme: 'mailto',
            query:
                'subject=${Uri.encodeComponent('A tiny step together with Budlark')}&body=${Uri.encodeComponent('Grow a tiny habit with Budlark. ${card == null ? '' : 'This link includes my chosen recipe: ${card!['aspiration']}. '}$url')}',
          ),
        )) {
          throw StateError('No email application is available.');
        }
      } else if (channel == 'native') {
        await NativeShare.share(url);
      }
      if (!mounted) return;
      setState(() {
        receipt = created;
        outcome = switch (channel) {
          'link' => 'Link copied',
          'email' => 'Email composer requested',
          'native' => 'Windows share panel requested',
          _ => 'Your QR is ready',
        };
      });
      if (channel == 'qr') {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      await widget.store.track(
        'share_initiated',
        properties: {
          'channel': ['link', 'email'].contains(channel) ? channel : 'invite',
          'platform': GardenStore.telemetryPlatform,
        },
      );
      await observe(ExperienceOutcome.taskCompleted);
    } catch (error) {
      if (mounted) {
        setState(() {
          receipt = null;
          outcome = null;
          failure = invitationErrorMessage(
            error,
            phase: phase,
            includeSupportCode: false,
          );
          supportInfo = error is InvitationFailure
              ? error.supportCode
              : InvitationFailure(
                  InvitationFailureKind.unknown,
                  phase,
                ).supportCode;
        });
        await observe(ExperienceOutcome.error);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact =
        MediaQuery.sizeOf(context).height < 650 ||
        MediaQuery.textScalerOf(context).scale(16) >= 28;
    return AlertDialog(
      title: Semantics(
        header: true,
        child: ExperienceCopy(
          experiments: experiments,
          surface: ExperienceSurface.invitationHeading,
          builder: (context, copy) => Text(copy),
          onAssignment: (value) => assignment = value,
        ),
      ),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Container(
                height: compact ? 96 : 150,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 284,
                    height: 150,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 130,
                          height: 140,
                          child: PlantArt(
                            stage: GrowthStage.sprout,
                            species: 'Fern',
                          ),
                        ),
                        Icon(Icons.favorite_outline, size: 24),
                        SizedBox(
                          width: 130,
                          height: 140,
                          child: PlantArt(
                            stage: GrowthStage.budding,
                            species: 'Cosmos',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Invite a friend to start a tiny habit.'),
            const SizedBox(height: 8),
            const Text(
              'Anyone with the link can open it. No one is contacted automatically.',
            ),
            if (card != null) ...[
              const SizedBox(height: 8),
              Text('Chosen recipe: ${card!['aspiration']}'),
              const Text(
                'Your chosen recipe is included in the link for email, QR and Windows share.',
              ),
            ],
            const SizedBox(height: 16),
            if (busy)
              Semantics(
                liveRegion: true,
                label: 'Preparing your invitation',
                child: Column(
                  children: [
                    const Text('Preparing your invitation'),
                    if (!widget.reducedMotion &&
                        !MediaQuery.disableAnimationsOf(context))
                      const LinearProgressIndicator(),
                  ],
                ),
              ),
            if (failure != null)
              Semantics(
                liveRegion: true,
                child: Text(failure!, style: TextStyle(color: colors.error)),
              ),
            if (outcome != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  outcome!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (receipt!.channel == 'email' || receipt!.channel == 'native')
                const Text(
                  'You choose the recipient and send. This is not delivery confirmation.',
                ),
              if (receipt!.channel == 'qr')
                Center(
                  child: Semantics(
                    label: 'Server invitation QR code',
                    container: true,
                    image: true,
                    excludeSemantics: true,
                    child: SizedBox.square(
                      dimension: 180,
                      child: QrImageView(
                        data: widget.service.webUri(receipt!).toString(),
                        size: 180,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
            FilledButton.icon(
              key: const ValueKey('invite-copy'),
              autofocus: true,
              style: FilledButton.styleFrom(
                textStyle: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              onPressed: busy ? null : () => share('link'),
              icon: const Icon(Icons.link),
              label: const Text('Copy link'),
            ),
            ExpansionTile(
              key: const ValueKey('invite-methods'),
              tilePadding: EdgeInsets.zero,
              title: const Text('More ways to invite'),
              children: [
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('Email invite'),
                  subtitle: Text(
                    card == null ? 'Choose a recipient and send the email.' : 'The email link includes your chosen recipe. You choose the recipient and send.',
                  ),
                  enabled: !busy,
                  onTap: busy ? null : () => share('email'),
                ),
                ListTile(
                  leading: const Icon(Icons.qr_code),
                  title: const Text('Show QR'),
                  subtitle: Text(
                    card == null
                        ? 'Your friend can scan the link.'
                        : 'The QR link includes your chosen recipe.',
                  ),
                  enabled: !busy,
                  onTap: busy ? null : () => share('qr'),
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Windows share'),
                  subtitle: Text(
                    card == null ? 'Choose an app and where to share.' : 'The shared link includes your chosen recipe. Choose an app and where to share.',
                  ),
                  enabled: !busy,
                  onTap: busy ? null : () => share('native'),
                ),
              ],
            ),
            ExpansionTile(
              key: const ValueKey('invite-recipe'),
              tilePadding: EdgeInsets.zero,
              title: Text(
                card == null
                    ? 'Include a recipe? Optional'
                    : 'Approved recipe included',
              ),
              children: [
                Text(
                  card == null
                      ? 'Only a link is shared by default.'
                      : 'Anyone with this link can see your approved recipe.',
                ),
                if (!widget.hasRecipes)
                  const Text(
                    'Plant a habit first to share a recipe. You can still invite with a link.',
                  )
                else
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              final chosen = await widget.chooseCard();
                              if (mounted && chosen != null) {
                                setState(() {
                                  card = chosen;
                                  receipt = null;
                                  outcome = null;
                                  failure = null;
                                  supportInfo = null;
                                  supportCopyOutcome = null;
                                });
                              }
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: const Text('Choose and approve a recipe card'),
                  ),
                if (card != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            card = null;
                            receipt = null;
                            outcome = null;
                            failure = null;
                            supportInfo = null;
                            supportCopyOutcome = null;
                          }),
                    child: const Text('Remove recipe card'),
                  ),
              ],
            ),
            ExpansionTile(
              key: const ValueKey('invite-details'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Privacy and link details'),
              children: [
                if (supportInfo != null) ...[
                  SelectableText(supportInfo!),
                  TextButton(
                    onPressed: () async {
                      final info = supportInfo!;
                      try {
                        await Clipboard.setData(ClipboardData(text: info));
                        if (mounted && supportInfo == info) {
                          setState(
                            () => supportCopyOutcome = 'Support info copied',
                          );
                        }
                      } catch (_) {
                        if (mounted && supportInfo == info) {
                          setState(
                            () => supportCopyOutcome = "Couldn't copy support info. Select the code to copy it.",
                          );
                        }
                      }
                    },
                    child: const Text('Copy support info'),
                  ),
                  if (supportCopyOutcome != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(supportCopyOutcome!),
                    ),
                ],
                const Text(
                  'Optional analytics is off by default; when enabled, Budlark '
                  'records invitation creation and the sharing method. Recipe '
                  'cards show only the fields you approve—not your name, email, '
                  'or practice history.',
                ),
                if (receipt != null) ...[
                  Text(
                    '${receipt!.cached ? "Cached existing invitation" : "Server-created invitation"}; expires ${receipt!.expiresAt.toLocal()}.',
                  ),
                  SelectableText(widget.service.webUri(receipt!).toString()),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
