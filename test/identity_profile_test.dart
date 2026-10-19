import 'package:budlark/services/identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('identity display names', () {
    test('verified token name wins over component and account claims', () {
      expect(
        IdentityProfile.fromClaims({
          'name': '  Ada Lovelace  ',
          'given_name': 'Other',
          'family_name': 'Name',
          'preferred_username': 'ada@example.invalid',
          'email': 'other@example.invalid',
        }).displayName,
        'Ada Lovelace',
      );
    });

    test('blank, non-string and unknown names allow component names', () {
      for (final name in [null, '', '  ', 42, ' UnKnOwN ']) {
        expect(
          IdentityProfile.fromClaims({
            'name': name,
            'given_name': ' Ada ',
            'family_name': ' Lovelace ',
          }).displayName,
          'Ada Lovelace',
        );
      }
      expect(
        IdentityProfile.fromClaims({'given_name': 'Ada'}).displayName,
        'Ada',
      );
      expect(
        IdentityProfile.fromClaims({'family_name': 'Lovelace'}).displayName,
        'Lovelace',
      );
    });

    test('preferred username precedes email and CIAM emails fallback', () {
      expect(
        IdentityProfile.fromClaims({
          'preferred_username': ' ada@example.invalid ',
          'email': 'other@example.invalid',
        }).displayName,
        'ada@example.invalid',
      );
      expect(
        IdentityProfile.fromClaims({
          'preferred_username': 'Unknown',
          'email': ' ada@example.invalid ',
        }).displayName,
        'ada@example.invalid',
      );
      expect(
        IdentityProfile.fromClaims({
          'emails': [null, 42, ' ', 'ada@example.invalid'],
        }).displayName,
        'ada@example.invalid',
      );
    });

    test('opaque identifiers and invalid claim types are not display names', () {
      expect(
        IdentityProfile.fromClaims({
          'sub': 'private-subject',
          'oid': 'private-object',
          'name': ['Ada'],
          'given_name': 42,
          'family_name': 'unknown',
          'preferred_username': {},
          'email': false,
          'emails': 'not-an-array',
        }).displayName,
        isNull,
      );
    });
  });

  group('subject-bound userinfo', () {
    const claims = {
      'sub': 'synthetic-subject',
      'preferred_username': 'ada@example.invalid',
    };

    test('userinfo name replaces account fallback, not verified token name', () {
      const userInfo = {'sub': 'synthetic-subject', 'name': 'Ada Lovelace'};
      expect(
        IdentityProfile.fromClaims(claims, userInfo: userInfo).displayName,
        'Ada Lovelace',
      );
      expect(
        IdentityProfile.fromClaims({
          ...claims,
          'name': 'Token Name',
        }, userInfo: userInfo).displayName,
        'Token Name',
      );
    });

    test('matching userinfo supplies missing name parts and email', () {
      expect(
        IdentityProfile.fromClaims({
          ...claims,
          'given_name': 'Ada',
        }, userInfo: {
          'sub': 'synthetic-subject',
          'family_name': 'Lovelace',
        }).displayName,
        'Ada Lovelace',
      );
      expect(
        IdentityProfile.fromClaims(
          {'sub': 'synthetic-subject'},
          userInfo: {
            'sub': 'synthetic-subject',
            'email': 'ada@example.invalid',
          },
        ).displayName,
        'ada@example.invalid',
      );
    });

    test('userinfo cannot erase usable token claims with blank values', () {
      expect(
        IdentityProfile.fromClaims({
          ...claims,
          'given_name': 'Ada',
          'family_name': 'Lovelace',
        }, userInfo: {
          'sub': 'synthetic-subject',
          'name': 'Unknown',
          'given_name': ' ',
          'family_name': false,
        }).displayName,
        'Ada Lovelace',
      );
    });

    test('missing, malformed and different userinfo subjects are ignored', () {
      for (final subject in [null, '', 42, 'another-subject']) {
        final profile = IdentityProfile.fromClaims(
          claims,
          userInfo: {
            'sub': subject,
            'name': 'Wrong Account',
            'picture': 'https://images.example.invalid/wrong.png',
          },
        );
        expect(profile.displayName, 'ada@example.invalid');
        expect(profile.photoUrl, isNull);
      }
      expect(
        IdentityProfile.fromClaims(
          {},
          userInfo: {'name': 'Unbound Name'},
        ).displayName,
        isNull,
      );
    });

    test('userinfo enrichment preserves HTTPS-only photo filtering', () {
      for (final picture in [
        'http://images.example.invalid/photo.png',
        'https://user:password@images.example.invalid/photo.png',
        'javascript:alert(1)',
      ]) {
        expect(
          IdentityProfile.fromClaims(
            claims,
            userInfo: {'sub': 'synthetic-subject', 'picture': picture},
          ).photoUrl,
          isNull,
        );
      }
    });
  });
}
