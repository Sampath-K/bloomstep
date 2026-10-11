import 'package:bloomstep/features/garden/profile_section.dart';
import 'package:bloomstep/services/identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile uses only name and a safe standard OIDC photo claim', () {
    final profile = IdentityProfile.fromClaims({
      'name': 'Synthetic Garden Tester',
      'emails': ['synthetic@example.invalid'],
      'idp': 'https://login.live.com',
      'picture': 'https://images.example.invalid/profile.png',
    });
    expect(profile.displayName, 'Synthetic Garden Tester');
    expect(profile.photoUrl, 'https://images.example.invalid/profile.png');
    final absent = IdentityProfile.fromClaims({'sub': 'private-subject'});
    expect(absent.displayName, isNull);
    expect(absent.photoUrl, isNull);
    for (final picture in [
      'http://images.example.invalid/profile.png',
      'javascript:alert(1)',
      'not a URL',
    ]) {
      expect(IdentityProfile.fromClaims({'picture': picture}).photoUrl, isNull);
    }
  });

  testWidgets('signed-out profile is small and preserves provider choices', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSection(
            signedIn: false,
            configured: true,
            busy: false,
            onSignIn: () async => attempts++,
            onSignOut: () async {},
          ),
        ),
      ),
    );
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Sign in with Microsoft or Google'), findsOneWidget);
    expect(find.text('Sign in securely'), findsNothing);
    expect(find.textContaining('ciamlogin.com'), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    await tester.tap(find.text('Sign in with Microsoft or Google'));
    await tester.pump();
    expect(attempts, 1);
  });

  testWidgets('signing in stays inline and cannot be started twice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSection(
            signedIn: false,
            configured: true,
            busy: true,
            onSignIn: () async {},
            onSignOut: () async {},
          ),
        ),
      ),
    );
    expect(find.text('Complete sign-in in your browser'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton).first).onPressed,
      isNull,
    );
  });

  testWidgets('signed-in profile is minimal and keeps sign-out inline', (
    tester,
  ) async {
    var signedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSection(
            signedIn: true,
            profile: IdentityProfile.fromClaims({
              'name': 'Synthetic Garden Tester',
              'email': 'synthetic@example.invalid',
              'idp': 'google.com',
            }),
            configured: true,
            busy: false,
            onSignIn: () async {},
            onSignOut: () async => signedOut = true,
          ),
        ),
      ),
    );
    expect(find.text('Signed in'), findsNothing);
    expect(find.text('Synthetic Garden Tester'), findsNothing);
    expect(find.textContaining('synthetic@example.invalid'), findsNothing);
    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('login.live.com'), findsNothing);
    expect(find.textContaining('unknown'), findsNothing);
    expect(find.text('ST'), findsOneWidget);
    expect(find.text('Sign in with Microsoft or Google'), findsNothing);
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(signedOut, isTrue);
  });

  testWidgets('missing picture uses a name-derived initials avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSection(
            signedIn: true,
            profile: IdentityProfile.fromClaims({'name': 'Ada Lovelace'}),
            configured: true,
            busy: false,
            onSignIn: () async {},
            onSignOut: () async {},
          ),
        ),
      ),
    );
    expect(find.text('Ada Lovelace'), findsNothing);
    expect(find.text('AL'), findsOneWidget);
    expect(find.text('Signed in'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('unavailable claimed photo leaves the initials fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSection(
            signedIn: true,
            profile: IdentityProfile.fromClaims({
              'name': 'Ada Lovelace',
              'picture': 'https://images.example.invalid/profile.png',
            }),
            configured: true,
            busy: false,
            onSignIn: () async {},
            onSignOut: () async {},
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('AL'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('AL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final message in [
    'Sign-in was cancelled. Your device garden is unchanged.',
    'Sign-in could not reach the identity service.',
    'Sign-in did not complete.',
  ]) {
    testWidgets('failure stays signed out: $message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileSection(
              signedIn: false,
              configured: true,
              busy: false,
              error: message,
              onSignIn: () async {},
              onSignOut: () async {},
            ),
          ),
        ),
      );
      expect(find.text(message), findsOneWidget);
      expect(find.text('Signed in'), findsNothing);
      expect(find.text('Sign in with Microsoft or Google'), findsOneWidget);
    });
  }
}
