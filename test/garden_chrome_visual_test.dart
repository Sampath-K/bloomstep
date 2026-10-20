import 'package:budlark/app/theme.dart';
import 'package:budlark/core/garden_store.dart';
import 'package:budlark/features/garden/garden_screen.dart';
import 'package:budlark/features/garden/profile_section.dart';
import 'package:budlark/features/garden/garden_canopy.dart';
import 'package:budlark/services/identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'invitation_widget_test.dart' show waitInvitation;
import 'support/visual_capture.dart';

void main() {
  testWidgets(
    'canopy motion is finite and both reduced-motion choices are static',
    (tester) async {
      await loadVisualFonts(tester);
      for (final choice in [
        (name: 'animated', app: false, os: false),
        (name: 'app-static', app: true, os: false),
        (name: 'os-static', app: false, os: true),
      ]) {
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: BudlarkTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: choice.os),
                child: child!,
              ),
              home: Scaffold(
                body: Column(
                  children: [
                    const Text(
                      'SYNTHETIC UI - decorative scenery, not earned growth',
                    ),
                    GardenCanopy(
                      key: ValueKey(choice.name),
                      reducedMotion: choice.app,
                      heading: const Text('A little is enough.'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final opacity = find.descendant(
          of: find.byType(GardenCanopy),
          matching: find.byType(Opacity),
        );
        expect(
          tester.widget<Opacity>(opacity).opacity,
          choice.app || choice.os ? 1 : 0,
        );
        await tester.pump(const Duration(milliseconds: 350));
        await captureVisual(tester, key, 'canopy-${choice.name}-middle');
        if (!choice.app && !choice.os) {
          expect(
            tester.widget<Opacity>(opacity).opacity,
            inExclusiveRange(0, 1),
          );
        }
        await tester.pumpAndSettle();
        expect(tester.widget<Opacity>(opacity).opacity, 1);
        expect(tester.hasRunningAnimations, isFalse);
        await captureVisual(tester, key, 'canopy-${choice.name}-complete');
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  for (final variant in [
    (
      name: 'device-empty',
      size: const Size(1100, 900),
      populated: false,
      device: true,
      scale: 1.0,
      dark: false,
    ),
    (
      name: 'account-populated',
      size: const Size(1100, 900),
      populated: true,
      device: false,
      scale: 1.0,
      dark: false,
    ),
    (
      name: 'device-populated-large',
      size: const Size(420, 820),
      populated: true,
      device: true,
      scale: 2.0,
      dark: false,
    ),
    (
      name: 'account-populated-large',
      size: const Size(420, 820),
      populated: true,
      device: false,
      scale: 2.0,
      dark: false,
    ),
    (
      name: 'account-populated-short-large',
      size: const Size(640, 480),
      populated: true,
      device: false,
      scale: 2.0,
      dark: false,
    ),
    (
      name: 'account-populated-short',
      size: const Size(640, 480),
      populated: true,
      device: false,
      scale: 1.0,
      dark: false,
    ),
    (
      name: 'account-empty-dark-small',
      size: const Size(640, 480),
      populated: false,
      device: false,
      scale: 1.0,
      dark: true,
    ),
  ]) {
    testWidgets('garden chrome ${variant.name} is responsive and actionable', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(variant.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadVisualFonts(tester);
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'synthetic-${variant.name}'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.runAsync(() async {
        await store.setSetting('reducedMotion', 'true');
        if (variant.populated) {
          await store.plant(
            aspiration: 'Synthetic calm',
            anchor: 'put my mug down',
            behavior: 'take one breath',
            celebration: 'smile',
            species: 'Fern',
          );
        }
      });
      Widget profile(
        Future<void> Function() signOut,
        VoidCallback manage, {
        bool compactSummary = false,
        bool detailsOnly = false,
      }) => ProfileSection(
        signedIn: !variant.device,
        configured: true,
        busy: false,
        profile: IdentityProfile.fromClaims({'name': 'Synthetic Gardener'}),
        onSignIn: () async {},
        onSignOut: signOut,
        onManage: manage,
        notice: variant.device
            ? null
            : 'Device garden stays separate; switch any time.',
        onCopyDeviceGarden: variant.device ? null : () async {},
        onSwitchGarden: variant.device ? null : () async {},
        compactSummary: compactSummary,
        detailsOnly: detailsOnly,
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: variant.dark
                ? BudlarkTheme.dark()
                : BudlarkTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: variant.size,
                textScaler: TextScaler.linear(variant.scale),
                disableAnimations: true,
              ),
              child: Column(
                children: [
                  const Material(
                    child: Text('SYNTHETIC UI - no live account or sending'),
                  ),
                  Expanded(child: child!),
                ],
              ),
            ),
            home: GardenScreen(
              store: store,
              testDisableServices: true,
              deviceGuest: variant.device,
              profileBuilder: profile,
              profileSummaryBuilder: (signOut, manage) =>
                  profile(signOut, manage, compactSummary: true),
              profileDetailsBuilder: (signOut, manage) =>
                  profile(signOut, manage, detailsOnly: true),
            ),
          ),
        ),
      );
      await waitInvitation(tester, find.text('Plant a habit'));
      await tester.pumpAndSettle();
      await captureVisual(tester, key, 'chrome-${variant.name}');
      expect(find.byKey(const ValueKey('garden-canopy')), findsOneWidget);
      if (variant.populated &&
          (variant.scale >= 2 || variant.size.height <= 480)) {
        expect(
          find.widgetWithText(OutlinedButton, 'Did it').hitTestable(),
          findsOneWidget,
          reason: 'The primary practice action must be hit-testable without scrolling.',
        );
        final practice = find.widgetWithText(OutlinedButton, 'Did it');
        final practiceRect = tester.getRect(practice);
        expect(
          practiceRect.left,
          greaterThanOrEqualTo(0),
          reason:
              'The full practice action must be inside the initial viewport.',
        );
        expect(
          practiceRect.top,
          greaterThanOrEqualTo(0),
          reason:
              'The full practice action must be inside the initial viewport.',
        );
        expect(
          practiceRect.right,
          lessThanOrEqualTo(variant.size.width),
          reason:
              'The full practice action must be inside the initial viewport.',
        );
        expect(
          practiceRect.bottom,
          lessThanOrEqualTo(variant.size.height),
          reason:
              'The full practice action must be inside the initial viewport.',
        );
        expect(
          tester.getSemantics(practice).flagsCollection.isButton,
          isTrue,
          reason: 'The primary practice action must keep button semantics.',
        );
        if (!variant.device) {
          expect(find.byTooltip('Settings and privacy'), findsOneWidget);
          expect(find.text('Separate gardens; switch any time.'), findsNothing);
          final details = find.byTooltip('Settings and privacy');
          expect(details, findsOneWidget);
          expect(find.byKey(const ValueKey('profile-details')), findsNothing);
          Future<bool> isFocusedWithin(Finder finder) async {
            await tester.pump();
            final focused = FocusManager.instance.primaryFocus?.context;
            if (focused == null) return false;
            var found = false;
            focused.visitAncestorElements((element) {
              if (finder.evaluate().contains(element)) {
                found = true;
                return false;
              }
              return true;
            });
            return found;
          }

          Future<void> tabUntil(Finder finder) async {
            for (var i = 0; i < 80; i++) {
              if (await isFocusedWithin(finder)) return;
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            }
          }

          FocusManager.instance.primaryFocus?.unfocus();
          await tabUntil(practice);
          expect(
            await isFocusedWithin(practice),
            isTrue,
            reason: 'Keyboard focus reaches the primary practice action.',
          );
          await tabUntil(details);
          expect(
            await isFocusedWithin(details),
            isTrue,
            reason: 'Keyboard focus reaches Settings for profile details.',
          );
        }
      } else if (variant.populated) {
        final practice = find.widgetWithText(OutlinedButton, 'Did it');
        await tester.ensureVisible(practice);
        await tester.pumpAndSettle();
        expect(
          practice.hitTestable(),
          findsOneWidget,
          reason: 'Primary practice must remain reachable in compact layouts.',
        );
        if (variant.scale >= 2) {
          await captureVisual(
            tester,
            key,
            'combined-device-garden-practice-200',
          );
        } else {
          await captureVisual(
            tester,
            key,
            'combined-account-garden-practice-short',
          );
        }
      }
      final cta = find.widgetWithText(FilledButton, 'Plant a habit');
      expect(tester.getSize(cta).width, lessThanOrEqualTo(300));
      expect(
        find.descendant(of: cta, matching: find.byType(CustomPaint)),
        findsWidgets,
      );
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.text('Plant a Seed').hitTestable(), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
