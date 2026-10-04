import 'package:bloomstep/core/rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quiet hours wrap midnight; caps and ignored reminders apply', () {
    expect(ReminderRules.inQuietHours(22 * 60), isTrue);
    expect(ReminderRules.inQuietHours(7 * 60), isTrue);
    expect(ReminderRules.inQuietHours(12 * 60), isFalse);
    expect(
      ReminderRules.allowed(
        minute: 600,
        totalToday: 3,
        habitToday: 0,
        ignored: 0,
      ),
      isFalse,
    );
    expect(
      ReminderRules.allowed(
        minute: 600,
        totalToday: 0,
        habitToday: 1,
        ignored: 0,
      ),
      isFalse,
    );
    expect(
      ReminderRules.allowed(
        minute: 600,
        totalToday: 0,
        habitToday: 0,
        ignored: 7,
      ),
      isFalse,
    );
  });
  test('graduation needs two scores and 60 percent practice over 28 days', () {
    expect(canGraduate([6, 6], 17), isTrue);
    expect(canGraduate([6], 28), isFalse);
    expect(canGraduate([6, 4], 28), isFalse);
    expect(canGraduate([6, 6], 16), isFalse);
  });
  test('doctor suggestions are deterministic, explained and non-punitive', () {
    expect(recipeDoctor('too hard'), contains('smaller'));
    expect(recipeDoctor('anchor'), contains('reliable'));
  });
  test('remote experiment is stable and bounded', () {
    expect(experimentBucket('a'), experimentBucket('a'));
    expect(experimentBucket('a'), inInclusiveRange(0, 99));
  });
}
