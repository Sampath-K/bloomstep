import 'dart:convert';

import 'package:crypto/crypto.dart';

class ReminderRules {
  static bool inQuietHours(int minute, {int start = 1290, int end = 450}) =>
      start == end ||
      (start > end
          ? minute >= start || minute < end
          : minute >= start && minute < end);

  static bool allowed({
    required int minute,
    required int totalToday,
    required int habitToday,
    required int ignored,
    int quietStart = 1290,
    int quietEnd = 450,
  }) =>
      !inQuietHours(minute, start: quietStart, end: quietEnd) &&
      totalToday < 3 &&
      habitToday == 0 &&
      ignored < 7;

  static int timing(
    List<int> minutes,
    int fallback, {
    int quietStart = 1290,
    int quietEnd = 450,
  }) {
    var preferred = fallback;
    if (minutes.length >= 5) {
      final sorted = minutes.take(14).toList()..sort();
      final middle = sorted.length ~/ 2;
      final median = sorted.length.isOdd
          ? sorted[middle].toDouble()
          : (sorted[middle - 1] + sorted[middle]) / 2;
      preferred = ((median / 15).round() * 15).clamp(0, 1439);
    }
    return inQuietHours(preferred, start: quietStart, end: quietEnd)
        ? quietEnd
        : preferred;
  }
}

bool reconnectDue(int absenceDays, int sent) =>
    sent == 0 && absenceDays >= 3 || sent == 1 && absenceDays >= 7;

bool newerVersionedRecord(
  Map<String, Object?> incoming,
  Map<String, Object?> existing,
  List<String> fields,
) {
  final time = DateTime.parse(incoming['updated'] as String)
      .compareTo(DateTime.parse(existing['updated'] as String));
  if (time != 0) return time > 0;
  return jsonEncode(fields.map((key) => incoming[key]).toList())
          .compareTo(jsonEncode(fields.map((key) => existing[key]).toList())) >
      0;
}

bool canGraduate(List<double> recentScores, int practiceDays) =>
    recentScores.length >= 2 &&
    recentScores.take(2).every((score) => score >= 5.5) &&
    practiceDays >= 17;

String recipeDoctor(String reason) => switch (reason) {
  'too hard' => 'Try something smaller: just the first movement, one word, or one breath. Why: reducing effort makes starting easier.',
  'anchor' => 'Choose a reliable anchor that happens most days. Why: your previous anchor did not happen.',
  'motivation' => 'Revisit what matters to you and choose a celebration that feels good. Why: this recipe may not fit your aspiration.',
  _ => 'Attach your tiny step to a specific existing routine. Why: a clear anchor helps you remember.',
};

int experimentBucket(String account) =>
    int.parse(
      sha256.convert(utf8.encode(account)).toString().substring(0, 8),
      radix: 16,
    ) %
    100;
