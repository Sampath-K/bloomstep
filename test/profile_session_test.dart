import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloomstep/app/bloomstep_app.dart';
import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/measurement_receipt.dart';
import 'package:bloomstep/services/identity.dart';
import 'package:bloomstep/services/installer_measurement.dart';
import 'package:bloomstep/services/auth_observations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _SyntheticIdentity extends IdentityService {
  bool active = false;
  bool restoreOffline = false;
  Object? failure;
  bool failSignOut = false;
  Completer<void>? pending;
  @override
  bool get configured => true;
  @override
  bool get hasValidSession => active;
  @override
  DateTime? get sessionExpiresAt => DateTime.now().add(const Duration(days: 1));
  @override
  IdentityProfile? get profile => active
      ? IdentityProfile.fromClaims({
          'name': 'Synthetic Garden Tester',
          'email': 'synthetic@example.invalid',
          'idp': 'google.com',
        })
      : null;
  @override
  Future<bool> restore() async {
    if (restoreOffline) await signIn();
    return active;
  }

  @override
  Future<void> checkpoint() async {}
  @override
  Future<void> signIn() async {
    await pending?.future;
    if (failure != null) throw failure!;
    active = true;
    account = List.filled(64, 'a').join();
  }

  @override
  Future<void> signOut() async {
    active = false;
    account = null;
    if (failSignOut) {
      throw StateError('Synthetic secure-storage delete failure');
    }
  }
}

Future<void> _ready(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

void main() {
  for (final scenario in [
    'no receipt',
    'consented guest',
    'restored account',
  ]) {
    testWidgets('legacy view consent: $scenario', (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bloomstep-profile-'),
      ))!;
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      final collector = (await tester.runAsync(
        () async => InstallerMeasurement(
          root.path,
          ownerId: '00000000-0000-4000-8000-000000000001',
        ),
      ))!;
      if (scenario != 'no receipt') {
        await tester.runAsync(() async {
          final now = DateTime.now().toUtc();
          await File(collector.path).writeAsString(
            jsonEncode({
              'schemaVersion': 1,
              'source': 'installer',
              'consentedAt': now
                  .subtract(const Duration(minutes: 2))
                  .toIso8601String(),
              'events': [
                {
                  'id': '00000000-0000-4000-8000-000000000001',
                  'name': 'installer_started',
                  'ts': now
                      .subtract(const Duration(minutes: 2))
                      .toIso8601String(),
                },
                {
                  'id': '00000000-0000-4000-8000-000000000002',
                  'name': 'install_completed',
                  'ts': now
                      .subtract(const Duration(minutes: 1))
                      .toIso8601String(),
                },
              ],
            }),
          );
          await collector.observe('first_launch');
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: HabitHome(
            measurement: collector,
            testIdentity: _SyntheticIdentity()
              ..restoreOffline = scenario == 'restored account',
            testOpenStore: (account) =>
                GardenStore.open(p.join(root.path, '$account.sqlite'), account),
          ),
        ),
      );
      await _ready(
        tester,
        find.text(
          scenario == 'restored account' ? 'Signed in' : 'Not signed in',
        ),
      );
      MeasurementReceipt? receipt;
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        receipt = await tester.runAsync<MeasurementReceipt?>(() async {
          final file = File(collector.path);
          return await file.exists()
              ? MeasurementReceipt.parse(await file.readAsString())
              : null;
        });
        if (scenario == 'consented guest' &&
            receipt?.events.any((event) => event.name == 'signin_view') ==
                true) {
          break;
        }
        if (scenario != 'consented guest' && i >= 10) break;
      }
      if (scenario == 'no receipt') {
        expect(receipt, isNull);
        expect(
          await tester.runAsync(() => File(collector.path).exists()),
          isFalse,
        );
      } else {
        expect(receipt!.events.map((event) => event.name), [
          'installer_started',
          'install_completed',
          'first_launch',
          if (scenario == 'consented guest') 'signin_view',
        ]);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
    });
  }

  testWidgets('guest planting is primary even without configured identity', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('bloomstep-profile-'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    await tester.pumpWidget(
      MaterialApp(
        home: HabitHome(
          testIdentity: IdentityService(),
          testOpenStore: (account) =>
              GardenStore.open(p.join(root.path, '$account.sqlite'), account),
        ),
      ),
    );
    await _ready(tester, find.text('Not signed in'));
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byTooltip('Settings and privacy'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings and privacy'));
    await _ready(tester, find.text('Share product event counts'));
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Share product event counts'),
          )
          .onChanged,
      isNull,
    );
    expect(find.text('Sign out'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plant a habit'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in securely'), findsNothing);
    expect(find.text('pour my morning drink'), findsOneWidget);
    await tester.tap(find.text('pour my morning drink'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('take one slow breath'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('relax my shoulders and smile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('I practiced my celebration'));
    await tester.tap(find.text('I practiced my celebration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plant this seed'));
    await _ready(tester, find.text('See my seed'));
    await tester.tap(find.text('See my seed'));
    await _ready(tester, find.text('Did it'));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.runAsync(() async {
      final guest = await GardenStore.open(
        p.join(root.path, '${HabitHome.guestAccount}.sqlite'),
        HabitHome.guestAccount,
      );
      expect(await guest.habits(), hasLength(1));
      expect(await guest.setting('analytics'), 'false');
      await guest.close();
    });
  });

  testWidgets('guest stays separate by default through sign-in and sign-out', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('bloomstep-profile-'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final guest = (await tester.runAsync(
      () => GardenStore.open(
        p.join(root.path, '${HabitHome.guestAccount}.sqlite'),
        HabitHome.guestAccount,
      ),
    ))!;
    await tester.runAsync(() async {
      await guest.plant(
        aspiration: 'Synthetic guest habit',
        anchor: 'pour my morning drink',
        behavior: 'take one slow breath',
        celebration: 'smile',
        species: 'Cosmos',
      );
      await guest.close();
    });
    final identity = _SyntheticIdentity();
    if (Platform.isWindows) {
      await tester.runAsync(() async {
        final bytes = await File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytes();
        await (FontLoader(
          'Segoe UI',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        final icons = await File(
          p.join(
            File(Platform.resolvedExecutable).parent.parent.parent.path,
            'material_fonts',
            'MaterialIcons-Regular.otf',
          ),
        ).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      });
    }
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: BloomstepTheme.light(),
        home: RepaintBoundary(
          key: boundaryKey,
          child: HabitHome(
            testIdentity: identity,
            testOpenStore: (account) =>
                GardenStore.open(p.join(root.path, '$account.sqlite'), account),
          ),
        ),
      ),
    );
    await _ready(tester, find.text('Did it'));
    await _screenshot(tester, boundaryKey, 'profile-signed-out.png');
    await tester.tap(find.text('Sign in with Microsoft or Google'));
    await _ready(tester, find.text('Synthetic Garden Tester'));
    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text('synthetic@example.invalid'), findsOneWidget);
    expect(find.text('Did it'), findsNothing);
    expect(find.textContaining('kept separate'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    await _screenshot(tester, boundaryKey, 'profile-signed-in-SYNTHETIC.png');
    final account = identity.account!;
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in'), findsOneWidget);
    expect(identity.account, account);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unsynced'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await _ready(tester, find.text('Not signed in'));
    await _ready(tester, find.text('Did it'));
    expect(identity.account, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final guest = await GardenStore.open(
        p.join(root.path, '${HabitHome.guestAccount}.sqlite'),
        HabitHome.guestAccount,
      );
      expect(await guest.habits(), hasLength(1));
      expect(await guest.setting('analytics'), 'false');
      expect((await guest.syncPayload())['events'], isEmpty);
      await guest.close();
      final owned = await GardenStore.open(
        p.join(root.path, '$account.sqlite'),
        account,
      );
      expect(await owned.habits(), isEmpty);
      await owned.close();
    });
  });

  for (final category in ['cancelled', 'network', 'validation']) {
    testWidgets('$category sign-in leaves guest editable and unchanged', (
      tester,
    ) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bloomstep-profile-'),
      ))!;
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      final identity = _SyntheticIdentity()
        ..pending = Completer<void>()
        ..failure = AuthFailure(category, 'Synthetic $category failure');
      await tester.pumpWidget(
        MaterialApp(
          home: HabitHome(
            testIdentity: identity,
            testOpenStore: (account) =>
                GardenStore.open(p.join(root.path, '$account.sqlite'), account),
          ),
        ),
      );
      await _ready(tester, find.text('Sign in with Microsoft or Google'));
      await tester.tap(find.text('Sign in with Microsoft or Google'));
      await tester.pump();
      expect(find.text('Complete sign-in in your browser'), findsOneWidget);
      expect(find.text('Plant a habit'), findsOneWidget);
      identity.pending!.complete();
      await _ready(tester, find.textContaining('Synthetic $category failure'));
      expect(find.text('Not signed in'), findsOneWidget);
      expect(identity.account, isNull);
      await tester.tap(find.text('Plant a habit'));
      await tester.pumpAndSettle();
      expect(find.text('pour my morning drink'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(
        (await tester.runAsync(() => root.list().toList()))!
            .whereType<File>()
            .every(
              (file) =>
                  p.basename(file.path).startsWith(HabitHome.guestAccount),
            ),
        isTrue,
      );
    });
  }

  testWidgets(
    'valid offline restore shows profile without authenticating again',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bloomstep-profile-'),
      ))!;
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      final identity = _SyntheticIdentity()..restoreOffline = true;
      await tester.pumpWidget(
        MaterialApp(
          home: HabitHome(
            testIdentity: identity,
            testOpenStore: (account) =>
                GardenStore.open(p.join(root.path, '$account.sqlite'), account),
          ),
        ),
      );
      await _ready(tester, find.text('Synthetic Garden Tester'));
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('Plant a habit'), findsOneWidget);
      expect(find.text('Sign in with Microsoft or Google'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
    },
  );

  testWidgets(
    'account storage failure rolls back sign-in without migrating guest',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bloomstep-profile-'),
      ))!;
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      final identity = _SyntheticIdentity();
      await tester.pumpWidget(
        MaterialApp(
          home: HabitHome(
            testIdentity: identity,
            testOpenStore: (account) {
              if (account != HabitHome.guestAccount) {
                throw StateError('Synthetic account storage failure');
              }
              return GardenStore.open(
                p.join(root.path, '$account.sqlite'),
                account,
              );
            },
          ),
        ),
      );
      await _ready(tester, find.text('Sign in with Microsoft or Google'));
      await tester.tap(find.text('Sign in with Microsoft or Google'));
      await _ready(
        tester,
        find.textContaining('Synthetic account storage failure'),
      );
      expect(find.text('Not signed in'), findsOneWidget);
      expect(identity.account, isNull);
      expect(find.text('Plant a habit'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
    },
  );

  testWidgets(
    'failed saved-auth cleanup is visible and retryable on the profile',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bloomstep-profile-'),
      ))!;
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      final identity = _SyntheticIdentity()
        ..restoreOffline = true
        ..failSignOut = true;
      await tester.pumpWidget(
        MaterialApp(
          home: HabitHome(
            testIdentity: identity,
            testOpenStore: (account) =>
                GardenStore.open(p.join(root.path, '$account.sqlite'), account),
          ),
        ),
      );
      await _ready(tester, find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await _ready(tester, find.text('Clear saved sign-in'));
      expect(find.textContaining('could not be cleared'), findsOneWidget);
      expect(find.text('Not signed in'), findsOneWidget);
      identity.failSignOut = false;
      await _ready(tester, find.text('Sign in with Microsoft or Google'));
      await tester.tap(find.text('Clear saved sign-in'));
      await _ready(tester, find.textContaining('Saved sign-in cleared.'));
      expect(find.text('Clear saved sign-in'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
    },
  );

  testWidgets(
    'expired offline session returns to guest without deleting account',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bloomstep-profile-'),
      ))!;
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      final identity = _SyntheticIdentity()..restoreOffline = true;
      await identity.signIn();
      final owner = identity.account!;
      final owned = (await tester.runAsync(
        () => GardenStore.open(p.join(root.path, '$owner.sqlite'), owner),
      ))!;
      await tester.runAsync(() async {
        await owned.plant(
          aspiration: 'Synthetic account habit',
          anchor: 'pour my morning drink',
          behavior: 'take one slow breath',
          celebration: 'smile',
          species: 'Cosmos',
        );
        await owned.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: HabitHome(
            testIdentity: identity,
            testOpenStore: (account) =>
                GardenStore.open(p.join(root.path, '$account.sqlite'), account),
          ),
        ),
      );
      await _ready(tester, find.text('Did it'));
      identity.active = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Did it'), findsNothing);
      await _ready(tester, find.text('Not signed in'));
      expect(find.textContaining('offline session ended'), findsOneWidget);
      expect(find.text('Synthetic account habit'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final saved = await GardenStore.open(
          p.join(root.path, '$owner.sqlite'),
          owner,
        );
        expect(await saved.habits(), hasLength(1));
        await saved.close();
      });
    },
  );
}

Future<void> _screenshot(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final output = Platform.environment['BLOOMSTEP_SCREENSHOTS'];
  if (output == null) return;
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File(p.join(output, name)).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
