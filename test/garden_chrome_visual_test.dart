import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/features/garden/profile_section.dart';
import 'package:bloomstep/features/garden/garden_canopy.dart';
import 'package:bloomstep/services/identity.dart';
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
              theme: BloomstepTheme.light(),
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
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: variant.dark
                ? BloomstepTheme.dark()
                : BloomstepTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
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
              deviceGuest: variant.device,
              profileBuilder: (signOut, manage) => ProfileSection(
                signedIn: !variant.device,
                configured: true,
                busy: false,
                profile: IdentityProfile.fromClaims({
                  'name': 'Synthetic Gardener',
                }),
                onSignIn: () async {},
                onSignOut: signOut,
                onManage: manage,
              ),
            ),
          ),
        ),
      );
      await waitInvitation(tester, find.text('Plant a habit'));
      await tester.pumpAndSettle();
      await captureVisual(tester, key, 'chrome-${variant.name}');
      expect(find.byKey(const ValueKey('garden-canopy')), findsOneWidget);
      if (variant.populated && variant.size.width >= 1000) {
        expect(
          find.widgetWithText(FilledButton, 'Did it').hitTestable(),
          findsOneWidget,
          reason: 'Populated desktop scenery must not displace practice.',
        );
      }
      final cta = find.widgetWithText(FilledButton, 'Plant a habit');
      expect(tester.getSize(cta).width, lessThanOrEqualTo(300));
      expect(
        find.descendant(of: cta, matching: find.byType(CustomPaint)),
        findsWidgets,
      );
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.text('Plant one tiny step'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
