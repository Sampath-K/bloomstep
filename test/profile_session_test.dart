import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:budlark/app/budlark_app.dart';
import 'package:budlark/app/theme.dart';
import 'package:budlark/core/garden_store.dart';
import 'package:budlark/core/measurement_receipt.dart';
import 'package:budlark/services/identity.dart';
import 'package:budlark/services/installer_measurement.dart';
import 'package:budlark/services/auth_observations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/dialog_copy_contract.dart';
import 'first_habit_invitation_test.dart' as first_habit;

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

Future<void> _ready(WidgetTester tester, Finder finder) =>
    first_habit.ready(tester, finder, dismissRecipeBuilder: true);

Future<void> _tapTextButton(WidgetTester tester, String label) =>
    tester.tap(find.widgetWithText(TextButton, label));

void main() {
  for (final scenario in [
    'no receipt',
    'consented guest',
    'restored account',
  ]) {
    testWidgets('legacy view consent: $scenario', (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('budlark-profile-'),
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
        find.text(scenario == 'restored account' ? 'ST' : 'Not signed in'),
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
      () => Directory.systemTemp.createTemp('budlark-profile-'),
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
    await _tapTextButton(tester, 'Done');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plant a habit'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in securely'), findsNothing);
    expect(find.text('Plant a Seed').hitTestable(), findsOneWidget);
    expect(find.text('coffee'), findsOneWidget);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('I practiced my celebration'));
    await tester.tap(find.text('I practiced my celebration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plant a Seed'));
    await _ready(tester, find.text('See my garden'));
    await tester.tap(find.text('See my garden'));
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
      () => Directory.systemTemp.createTemp('budlark-profile-'),
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
    var failDeviceRead = false;
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
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: BudlarkTheme.light(),
          home: HabitHome(
            testIdentity: identity,
            testOpenStore: (account) {
              if (failDeviceRead && account == HabitHome.guestAccount) {
                throw StateError('Synthetic device reader unavailable');
              }
              return GardenStore.open(
                p.join(root.path, '$account.sqlite'),
                account,
              );
            },
          ),
        ),
      ),
    );
    await _ready(tester, find.text('Did it'));
    expect(find.byTooltip('Settings and privacy'), findsOneWidget);
    await _screenshot(tester, boundaryKey, 'profile-signed-out.png');
    await _ready(tester, find.text('Sign in with Microsoft or Google'));
    await _tapTextButton(tester, 'Sign in with Microsoft or Google');
    await _ready(tester, find.widgetWithText(TextButton, 'Sign out'));
    expect(find.text('Signed in'), findsNothing);
    expect(find.text('Synthetic Garden Tester'), findsOneWidget);
    expect(find.textContaining('synthetic@example.invalid'), findsNothing);
    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('unknown'), findsNothing);
    expect(find.text('ST'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget);
    expect(find.text('Did it'), findsNothing);
    expect(find.textContaining('Device garden stays separate'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('Device garden stays separate'), findsOneWidget);
    expect(find.text('Copy device habits to this account'), findsOneWidget);
    await _screenshot(
      tester,
      boundaryKey,
      'profile-signed-in-before-copy-SYNTHETIC.png',
    );
    await _tapTextButton(tester, 'Copy device habits to this account');
    await tester.pumpAndSettle();
    const copyDisclosure =
        'Device habits, check-ins, and reflections copy to your account and may '
        'sync. Originals stay on this device; existing account habits are '
        'unchanged.';
    expect(find.text('Copy to your account?'), findsOneWidget);
    expect(find.text(copyDisclosure), findsOneWidget);
    expectConciseDialogCopy(copyDisclosure);
    await _screenshot(
      tester,
      boundaryKey,
      'device-copy-confirmation-SYNTHETIC.png',
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Did it'), findsNothing);
    await _ready(tester, find.text('View device garden'));
    await _tapTextButton(tester, 'View device garden');
    await _ready(tester, find.text('Viewing your device garden.'));
    await _ready(tester, find.text('Did it'));
    expect(identity.active, isTrue);
    await _screenshot(tester, boundaryKey, 'profile-view-device-SYNTHETIC.png');
    await _ready(tester, find.text('Return to account garden'));
    await _tapTextButton(tester, 'Return to account garden');
    await _ready(tester, find.text('ST'));
    expect(find.text('Did it'), findsNothing);
    failDeviceRead = true;
    await _ready(tester, find.text('Copy device habits to this account'));
    await _tapTextButton(tester, 'Copy device habits to this account');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Copy'));
    await _ready(tester, find.textContaining("Couldn't copy device habits"));
    expect(find.text('Did it'), findsNothing);
    expect(find.textContaining('No changes were saved.'), findsOneWidget);
    failDeviceRead = false;
    await _ready(tester, find.text('Copy device habits to this account'));
    await _tapTextButton(tester, 'Copy device habits to this account');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Copy'));
    await _ready(tester, find.text('Did it'));
    await _ready(tester, find.textContaining('Copied 1 habit'));
    expect(find.textContaining('Copied 1 habit'), findsOneWidget);
    await _ready(tester, find.text('Copy device habits to this account'));
    await _tapTextButton(tester, 'Copy device habits to this account');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Copy'));
    await _ready(tester, find.textContaining('Copied 0 habits'));
    expect(find.textContaining('Copied 0 habits'), findsOneWidget);
    expect(find.text('Did it'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _screenshot(tester, boundaryKey, 'profile-signed-in-SYNTHETIC.png');
    final account = identity.account!;
    await _ready(tester, find.text('Sign out'));
    await _tapTextButton(tester, 'Sign out');
    await tester.pumpAndSettle();
    await _tapTextButton(tester, 'Cancel');
    await tester.pumpAndSettle();
    await _ready(tester, find.text('ST'));
    expect(find.text('ST'), findsOneWidget);
    expect(identity.account, account);
    await _ready(tester, find.text('Sign out'));
    await _tapTextButton(tester, 'Sign out');
    await tester.pumpAndSettle();
    const signOutDisclosure =
        'Unsynced account data is removed from this device; your separate '
        'device garden stays here. Export it first if you need a copy.';
    expect(find.text('Sign out?'), findsOneWidget);
    expect(find.text(signOutDisclosure), findsOneWidget);
    expectConciseDialogCopy(signOutDisclosure);
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

  testWidgets(
    'signed-in HabitHome retains export deletion and consent settings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('budlark-profile-'),
      ))!;
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      await tester.pumpWidget(
        MaterialApp(
          home: HabitHome(
            testIdentity: _SyntheticIdentity()..restoreOffline = true,
            testOpenStore: (account) =>
                GardenStore.open(p.join(root.path, '$account.sqlite'), account),
          ),
        ),
      );
      await _ready(tester, find.byTooltip('Settings and privacy').hitTestable());
      expect(find.byTooltip('Settings and privacy'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings and privacy'));
      await _ready(tester, find.text('Garden & data'));
      await tester.ensureVisible(find.text('Garden & data'));
      await tester.tap(find.text('Garden & data').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Export my data (JSON)'), findsOneWidget);
      expect(find.text('Delete local garden'), findsOneWidget);
      expect(find.text('Delete account data everywhere'), findsOneWidget);
      await tester.tap(find.text('Garden & data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy & measurement'));
      await tester.pumpAndSettle();
      final consent = find.widgetWithText(
        SwitchListTile,
        'Share product event counts',
      );
      expect(tester.widget<SwitchListTile>(consent).onChanged, isNotNull);
      await _tapTextButton(tester, 'Done');
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
    },
  );

  testWidgets('copy confirmation is scrollable at compact 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('budlark-copy-compact-'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    await tester.runAsync(() async {
      final guest = await GardenStore.open(
        p.join(root.path, '${HabitHome.guestAccount}.sqlite'),
        HabitHome.guestAccount,
      );
      await guest.plant(
        aspiration: 'Device habit',
        anchor: 'coffee',
        behavior: 'breathe',
        celebration: 'smile',
        species: 'Cosmos',
      );
      await guest.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: const Size(360, 600),
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: HabitHome(
          testIdentity: _SyntheticIdentity()..restoreOffline = true,
          testOpenStore: (account) =>
              GardenStore.open(p.join(root.path, '$account.sqlite'), account),
        ),
      ),
    );
    await _ready(tester, find.text('Copy device habits to this account'));
    await tester.ensureVisible(find.text('Copy device habits to this account'));
    await _tapTextButton(tester, 'Copy device habits to this account');
    await tester.pumpAndSettle();
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
      isTrue,
    );
    await tester.ensureVisible(find.text('Not now'));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
  });

  for (final category in ['cancelled', 'network', 'validation']) {
    testWidgets('$category sign-in leaves guest editable and unchanged', (
      tester,
    ) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('budlark-profile-'),
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
      await _tapTextButton(tester, 'Sign in with Microsoft or Google');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Plant a habit'), findsOneWidget);
      identity.pending!.complete();
      await _ready(
        tester,
        find.text('Sign-in didn’t complete. Your device garden is unchanged.'),
      );
      expect(find.text('Not signed in'), findsOneWidget);
      expect(identity.account, isNull);
      await _tapTextButton(tester, 'Done');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plant a habit'));
      await tester.pumpAndSettle();
      expect(find.text('Plant a Seed').hitTestable(), findsOneWidget);
      expect(find.text('coffee'), findsOneWidget);
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
        () => Directory.systemTemp.createTemp('budlark-profile-'),
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
      await _ready(tester, find.text('ST'));
      expect(find.text('Signed in'), findsNothing);
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
        () => Directory.systemTemp.createTemp('budlark-profile-'),
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
      await _tapTextButton(tester, 'Sign in with Microsoft or Google');
      await _ready(
        tester,
        find.text(
          'Couldn’t open your account garden. Your device garden is unchanged.',
        ),
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
        () => Directory.systemTemp.createTemp('budlark-profile-'),
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
      await _tapTextButton(tester, 'Sign out');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await _ready(tester, find.text('Clear saved sign-in'));
      await _ready(
        tester,
        find.textContaining('Couldn’t finish sign-out'),
      );
      await _ready(tester, find.text('Not signed in'));
      expect(find.text('Not signed in'), findsOneWidget);
      identity.failSignOut = false;
      await _ready(tester, find.text('Clear saved sign-in'));
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
        () => Directory.systemTemp.createTemp('budlark-profile-'),
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
      await _ready(
        tester,
        find.textContaining('offline session ended'),
      );
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
  testWidgets(
    'session expiry while viewing device preserves the live device store',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('budlark-device-expiry-'),
      ))!;
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      await tester.runAsync(() async {
        final guest = await GardenStore.open(
          p.join(root.path, '${HabitHome.guestAccount}.sqlite'),
          HabitHome.guestAccount,
        );
        await guest.plant(
          aspiration: 'Saved device habit',
          anchor: 'coffee',
          behavior: 'breathe',
          celebration: 'smile',
          species: 'Cosmos',
        );
        await guest.close();
      });
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
      await _ready(tester, find.text('View device garden'));
      await _tapTextButton(tester, 'View device garden');
      await _ready(tester, find.text('Viewing your device garden.'));
      identity.active = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _ready(tester, find.text('Not signed in'));
      expect(find.text('Did it'), findsOneWidget);
      expect(find.text('Return to account garden'), findsNothing);
      expect(find.byTooltip('Settings and privacy'), findsOneWidget);
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
        await guest.close();
      });
    },
  );
}

Future<void> _screenshot(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final output = Platform.environment['BUDLARK_SCREENSHOTS'];
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
