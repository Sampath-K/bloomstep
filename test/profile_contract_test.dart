import 'package:bloomstep/features/garden/profile_section.dart';
import 'package:bloomstep/services/identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'profile uses returned claims, not account hashes or invented identity',
    () {
      final profile = IdentityProfile.fromClaims({
        'name': 'Synthetic Garden Tester',
        'emails': ['synthetic@example.invalid'],
        'idp': 'https://login.live.com',
      });
      expect(profile.displayName, 'Synthetic Garden Tester');
      expect(profile.email, 'synthetic@example.invalid');
      expect(profile.provider, 'Microsoft personal account');
      final absent = IdentityProfile.fromClaims({'sub': 'private-subject'});
      expect(absent.displayName, isNull);
      expect(absent.email, isNull);
      expect(absent.provider, isNull);
      expect(
        IdentityProfile.fromClaims({'idp': 'google.com'}).provider,
        'Google',
      );
      expect(
        IdentityProfile.fromClaims({'iss': 'https://broker.example'}).provider,
        'https://broker.example',
      );
    },
  );

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
    expect(
      find.textContaining('Microsoft hosts Bloomstep sign-in at ciamlogin.com'),
      findsOneWidget,
    );
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

  testWidgets('signed-in profile shows genuine fields and sign-out inline', (
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
    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text('Synthetic Garden Tester'), findsOneWidget);
    expect(find.text('synthetic@example.invalid'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Sign in with Microsoft or Google'), findsNothing);
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(signedOut, isTrue);
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
