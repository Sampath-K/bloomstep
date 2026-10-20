import 'package:budlark/services/identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('verified current sign-in provider, not linked-provider inventory', () {
    test('recognizes standard upstream identity-provider claims only', () {
      for (final idp in ['google.com', 'https://accounts.google.com']) {
        expect(
          IdentityProfile.fromClaims({'idp': idp}).signInProvider,
          'Google',
        );
      }
      for (final idp in ['live.com', 'https://login.live.com']) {
        expect(
          IdentityProfile.fromClaims({'idp': idp}).signInProvider,
          'Microsoft',
        );
      }
    });

    test('does not infer provider from email, userinfo or unknown CIAM issuer', () {
      for (final claims in [
        {'email': 'person@gmail.com'},
        {'preferred_username': 'person@outlook.com'},
        {'iss': 'https://example.ciamlogin.com/tenant/v2.0'},
        {'idp': 'https://accounts.google.com.attacker.invalid'},
        {'idp': ['google.com']},
      ]) {
        expect(IdentityProfile.fromClaims(claims).signInProvider, isNull);
      }
      expect(
        IdentityProfile.fromClaims(
          {'sub': 'subject'},
          userInfo: {'sub': 'subject', 'idp': 'google.com'},
        ).signInProvider,
        isNull,
      );
    });

    test('recognizes direct Google issuer without claiming linked accounts', () {
      expect(
        IdentityProfile.fromClaims({
          'iss': 'https://accounts.google.com',
        }).signInProvider,
        'Google',
      );
    });

    test('a generic workforce issuer does not prove the upstream method', () {
      expect(
        IdentityProfile.fromClaims({
          'tid': '11111111-2222-4333-8444-555555555555',
          'iss':
              'https://login.microsoftonline.com/'
              '11111111-2222-4333-8444-555555555555/v2.0',
        }).signInProvider,
        isNull,
      );
    });
  });

  group('already-authorized Microsoft Graph profile fallback', () {
    const claims = {
      'iss':
          'https://login.microsoftonline.com/'
          '9188040d-6c67-4c5b-b112-36a304b66dad/v2.0',
      'tid': '9188040d-6c67-4c5b-b112-36a304b66dad',
      'oid': '11111111-2222-4333-8444-555555555555',
      'sub': 'signed-in-subject',
    };
    const tokenResponse = {
      'access_token': 'synthetic-opaque-graph-token',
      'token_type': 'Bearer',
      'scope': 'https://graph.microsoft.com/User.Read',
    };

    test('requests only fixed /me endpoint with existing delegated token', () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://graph.microsoft.com/v1.0/me'
          '?\$select=id,displayName,givenName,surname',
        );
        expect(request.followRedirects, isFalse);
        expect(
          request.headers['Authorization'],
          'Bearer synthetic-opaque-graph-token',
        );
        return http.Response(
          '{"id":"${claims['oid']}","displayName":"Graph Name",'
          '"givenName":"Ada","surname":"Lovelace"}',
          200,
        );
      });
      final info = await IdentityProfile.microsoftGraphUserInfo(
        verifiedClaims: claims,
        tokenResponse: tokenResponse,
        client: client,
      );
      expect(info, {
        'sub': 'signed-in-subject',
        'name': 'Graph Name',
        'given_name': 'Ada',
        'family_name': 'Lovelace',
      });
      expect(
        IdentityProfile.fromClaims(claims, userInfo: info).displayName,
        'Graph Name',
      );
      expect(
        IdentityProfile.fromClaims({
          ...claims,
          'name': 'Token Name',
        }, userInfo: info).displayName,
        'Token Name',
      );
      expect(IdentityProfile.fromClaims(claims).signInProvider, 'Microsoft');
    });

    test('Graph givenName/surname work without displayName', () async {
      final info = await IdentityProfile.microsoftGraphUserInfo(
        verifiedClaims: claims,
        tokenResponse: tokenResponse,
        client: MockClient(
          (_) async => http.Response(
            '{"id":"${claims['oid']}","givenName":"Ada","surname":"Lovelace"}',
            200,
          ),
        ),
      );
      expect(
        IdentityProfile.fromClaims(claims, userInfo: info).displayName,
        'Ada Lovelace',
      );
    });

    test('CIAM identity and non-Graph tokens never cause a Graph request', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('', 401);
      });
      for (final token in [
        {...tokenResponse, 'scope': 'api://budlark/sync'},
        {...tokenResponse, 'scope': 'User.Read'},
        {...tokenResponse, 'scope': 'https://graph.microsoft.com/User.Read.All'},
        {...tokenResponse, 'token_type': 'not-bearer'},
        {...tokenResponse, 'access_token': ''},
      ]) {
        expect(
          await IdentityProfile.microsoftGraphUserInfo(
            verifiedClaims: claims,
            tokenResponse: token,
            client: client,
          ),
          isEmpty,
        );
      }
      expect(
        await IdentityProfile.microsoftGraphUserInfo(
          verifiedClaims: {
            ...claims,
            'iss': 'https://example.ciamlogin.com/tenant/v2.0',
          },
          tokenResponse: tokenResponse,
          client: client,
        ),
        isEmpty,
      );
      expect(requests, 0);
    });

    test('wrong account, redirects, errors and malformed responses are optional', () async {
      for (final response in [
        http.Response('{"id":"another-account","displayName":"Wrong"}', 200),
        http.Response('{"displayName":"Missing account"}', 200),
        http.Response('not json', 200),
        http.Response('[]', 200),
        http.Response('', 302, headers: {'location': 'https://other.invalid'}),
        http.Response('', 401),
        http.Response('', 403),
        http.Response('', 404),
        http.Response('x' * (64 * 1024 + 1), 200),
      ]) {
        expect(
          await IdentityProfile.microsoftGraphUserInfo(
            verifiedClaims: claims,
            tokenResponse: tokenResponse,
            client: MockClient((_) async => response),
          ),
          isEmpty,
        );
      }
      expect(
        await IdentityProfile.microsoftGraphUserInfo(
          verifiedClaims: claims,
          tokenResponse: tokenResponse,
          client: MockClient((_) async => throw http.ClientException('offline')),
        ),
        isEmpty,
      );
    });
  });

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
