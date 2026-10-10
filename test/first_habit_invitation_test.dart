import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/app/bloomstep_app.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/features/garden/recipe_builder.dart';
import 'package:bloomstep/services/identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _RestoringIdentity extends IdentityService {
  final restored = Completer<bool>();
  bool active = false;
  @override
  bool get configured => true;
  @override
  bool get hasValidSession => active;
  @override
  IdentityProfile? get profile => null;
  @override
  DateTime? get sessionExpiresAt => DateTime.now().add(const Duration(days: 1));
  @override
  Future<void> checkpoint() async {}
  @override
  Future<bool> restore() => restored.future;
  @override
  Future<void> signIn() async {
    active = true;
    account = List.filled(64, 'a').join();
  }

  @override
  Future<void> signOut() async {
    active = false;
    account = null;
  }
}

Future<void> ready(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

void main() {
  testWidgets('app waits for restoration and presents first empty guest once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('bloomstep-first-habit-'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final identity = _RestoringIdentity();
    final openRequested = Completer<void>();
    final delayedOpen = Completer<GardenStore>();
    final screenshotKey = GlobalKey();
    if (Platform.isWindows) {
      await tester.runAsync(() async {
        final font = await File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytes();
        await (FontLoader(
          'Segoe UI',
        )..addFont(Future.value(ByteData.sublistView(font)))).load();
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
    Future<GardenStore> open(String account) {
      if (!openRequested.isCompleted) {
        openRequested.complete();
        return delayedOpen.future;
      }
      return GardenStore.open(p.join(root.path, '$account.sqlite'), account);
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: BloomstepTheme.light(),
          home: HabitHome(testIdentity: identity, testOpenStore: open),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(RecipeBuilder), findsNothing);
    identity.restored.complete(false);
    await openRequested.future;
    await tester.pump();
    expect(find.byType(RecipeBuilder), findsNothing);
    delayedOpen.complete(
      (await tester.runAsync(
        () => GardenStore.open(
          p.join(root.path, '${HabitHome.guestAccount}.sqlite'),
          HabitHome.guestAccount,
        ),
      ))!,
    );
    await ready(tester, find.byType(RecipeBuilder));
    expect(find.text('Plant one tiny step'), findsOneWidget);
    await captureFirstHabitScreen(tester, screenshotKey);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeBuilder), findsNothing);
    expect(find.text('Plant a habit'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    final returning = _RestoringIdentity()..restored.complete(false);
    await tester.pumpWidget(
      MaterialApp(
        home: HabitHome(testIdentity: returning, testOpenStore: open),
      ),
    );
    await ready(tester, find.byType(RecipeBuilder));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeBuilder), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });

  testWidgets('restored account with habits never creates or invites a guest', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('bloomstep-first-habit-'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final identity = _RestoringIdentity()
      ..active = true
      ..account = List.filled(64, 'a').join()
      ..restored.complete(true);
    Future<GardenStore> open(String account) =>
        GardenStore.open(p.join(root.path, '$account.sqlite'), account);
    await tester.runAsync(() async {
      final store = await open(identity.account!);
      await store.plant(
        aspiration: 'Calm',
        anchor: 'pour my drink',
        behavior: 'take one breath',
        celebration: 'smile',
        species: 'Cosmos',
      );
      await store.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: HabitHome(testIdentity: identity, testOpenStore: open),
      ),
    );
    await ready(tester, find.text('Did it'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeBuilder), findsNothing);
    expect(
      await tester.runAsync(
        () => File(p.join(root.path, 'device-guest.sqlite')).exists(),
      ),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });

  testWidgets('pending first invitation does not open above another route', (
    tester,
  ) async {
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'device-guest'),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    final navigator = GlobalKey<NavigatorState>();
    final allow = ValueNotifier(false);
    addTearDown(allow.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: ValueListenableBuilder<bool>(
          valueListenable: allow,
          builder: (_, value, _) => GardenScreen(
            store: store,
            deviceGuest: true,
            autoInviteFirstHabit: true,
            firstHabitInvitationReady: value,
          ),
        ),
      ),
    );
    await ready(tester, find.text('A little is enough.'));
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other owned route')),
        ),
      ),
    );
    allow.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Other owned route'), findsOneWidget);
    expect(find.byType(RecipeBuilder), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'first invitation claim is durable, empty-only and single-winner',
    () async {
      final store = await GardenStore.open(':memory:', 'device-guest');
      addTearDown(store.close);
      expect(
        await Future.wait([
          store.claimFirstHabitInvitation(),
          store.claimFirstHabitInvitation(),
        ]),
        [true, false],
      );
      expect(await store.claimFirstHabitInvitation(), isFalse);
      await store.deleteLocalAccount();
      expect(await store.claimFirstHabitInvitation(), isFalse);
    },
  );

  for (final prior in ['visit', 'habit']) {
    test('existing $prior never qualifies as first run', () async {
      final store = await GardenStore.open(':memory:', 'device-guest');
      addTearDown(store.close);
      if (prior == 'visit') {
        await store.recordInteraction();
      } else {
        await store.plant(
          aspiration: 'Calm',
          anchor: 'pour my drink',
          behavior: 'take one breath',
          celebration: 'smile',
          species: 'Cosmos',
        );
      }
      expect(await store.claimFirstHabitInvitation(), isFalse);
    });
  }

  testWidgets(
    'first empty guest opens builder without a click; cancel stays dismissed',
    (tester) async {
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'device-guest'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      final eligible = (await tester.runAsync(
        store.claimFirstHabitInvitation,
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(
            store: store,
            deviceGuest: true,
            autoInviteFirstHabit: eligible,
          ),
        ),
      );
      await ready(tester, find.byType(RecipeBuilder));
      expect(find.text('pour my morning drink'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeBuilder), findsNothing);
      expect(find.text('Plant a habit'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      final again = (await tester.runAsync(store.claimFirstHabitInvitation))!;
      expect(again, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(
            store: store,
            deviceGuest: true,
            autoInviteFirstHabit: again,
          ),
        ),
      );
      await ready(tester, find.text('A little is enough.'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeBuilder), findsNothing);
      await tester.tap(find.text('Plant a habit'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeBuilder), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'auth initialization gates invitation and route replacement cancels it',
    (tester) async {
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'device-guest'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      Widget app(bool readyToInvite, {bool guest = true}) => MaterialApp(
        home: GardenScreen(
          key: const ValueKey('garden'),
          store: store,
          deviceGuest: guest,
          autoInviteFirstHabit: true,
          firstHabitInvitationReady: readyToInvite,
        ),
      );
      await tester.pumpWidget(app(false));
      await ready(tester, find.text('A little is enough.'));
      expect(find.byType(RecipeBuilder), findsNothing);
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeBuilder), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(true, guest: false));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeBuilder), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('empty account garden also opens the builder automatically', (
    tester,
  ) async {
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'account-only'),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.pumpWidget(
      MaterialApp(home: GardenScreen(store: store, autoInviteFirstHabit: true)),
    );
    await ready(tester, find.byType(RecipeBuilder));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeBuilder), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final signedIn in [false, true]) {
    testWidgets(
      'returning empty ${signedIn ? 'account' : 'device'} ignores old dismissal and history',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 920));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('bloomstep-returning-empty-'),
        ))!;
        addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
        final identity = _RestoringIdentity()
          ..active = signedIn
          ..account = signedIn ? List.filled(64, 'a').join() : null
          ..restored.complete(signedIn);
        final account = identity.account ?? HabitHome.guestAccount;
        Future<GardenStore> open(String owner) =>
            GardenStore.open(p.join(root.path, '$owner.sqlite'), owner);
        await tester.runAsync(() async {
          final store = await open(account);
          await store.claimFirstHabitInvitation();
          await store.recordInteraction();
          await store.close();
        });
        final screenshotKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: screenshotKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: BloomstepTheme.light(),
              home: HabitHome(testIdentity: identity, testOpenStore: open),
            ),
          ),
        );
        await ready(tester, find.byType(RecipeBuilder));
        await captureFirstHabitScreen(
          tester,
          screenshotKey,
          name: 'first-habit-returning-${signedIn ? 'account' : 'device'}.png',
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(RecipeBuilder), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        expect(find.byType(RecipeBuilder), findsNothing);
        expect(find.text('Plant a habit'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      },
    );
  }

  testWidgets(
    'sign-in opens empty account builder once after ownership changes',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bloomstep-signin-empty-'),
      ))!;
      addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
      Future<GardenStore> open(String account) =>
          GardenStore.open(p.join(root.path, '$account.sqlite'), account);
      await tester.runAsync(() async {
        final guest = await open(HabitHome.guestAccount);
        await guest.plant(
          aspiration: 'Calm',
          anchor: 'pour my drink',
          behavior: 'take one breath',
          celebration: 'smile',
          species: 'Cosmos',
        );
        await guest.close();
        final account = await open(List.filled(64, 'a').join());
        await account.claimFirstHabitInvitation();
        await account.recordInteraction();
        await account.close();
      });
      final identity = _RestoringIdentity()..restored.complete(false);
      await tester.pumpWidget(
        MaterialApp(
          home: HabitHome(testIdentity: identity, testOpenStore: open),
        ),
      );
      await ready(tester, find.text('Did it'));
      expect(find.byType(RecipeBuilder), findsNothing);
      await tester.tap(find.text('Sign in with Microsoft or Google'));
      await ready(tester, find.byType(RecipeBuilder));
      expect(identity.hasValidSession, isTrue);
      expect(find.text('Did it'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeBuilder), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(RecipeBuilder), findsNothing);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await ready(tester, find.text('Did it'));
      await tester.tap(find.text('Sign in with Microsoft or Google'));
      await ready(tester, find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeBuilder), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    },
  );
}

Future<void> captureFirstHabitScreen(
  WidgetTester tester,
  GlobalKey key, {
  String name = 'first-habit-auto-open.png',
}) async {
  final output = Platform.environment['BLOOMSTEP_SCREENSHOTS'];
  if (output == null) return;
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File(p.join(output, name))
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
