import 'package:bloomstep/services/identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'offline authentication expires at exactly 30 days, not rounded day 31',
    () {
      final authenticated = DateTime.utc(2026, 9, 1);
      expect(
        IdentityService.offlineSessionValid(
          authenticated,
          now: authenticated.add(const Duration(days: 29, hours: 23)),
        ),
        isTrue,
      );
      expect(
        IdentityService.offlineSessionValid(
          authenticated,
          now: authenticated.add(const Duration(days: 30)),
        ),
        isFalse,
      );
      expect(
        IdentityService.offlineSessionValid(
          authenticated,
          now: authenticated.add(const Duration(days: 30, seconds: 1)),
        ),
        isFalse,
      );
    },
  );
  test('a large backward clock change cannot extend the offline session', () {
    final authenticated = DateTime.utc(2026, 9, 1);
    expect(
      IdentityService.offlineSessionValid(
        authenticated,
        now: authenticated.subtract(const Duration(minutes: 6)),
      ),
      isFalse,
    );
    expect(
      IdentityService.offlineSessionValid(
        authenticated,
        now: authenticated.subtract(const Duration(minutes: 2)),
      ),
      isTrue,
    );
  });
}
