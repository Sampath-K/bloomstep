import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'rules.dart';

class GardenStore {
  GardenStore._(this._db, this._account);
  final Database _db;
  String _account;
  String get account => _account;
  static const _uuid = Uuid();

  static Future<GardenStore> open(String path, String account) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE settings ADD COLUMN updated TEXT NOT NULL DEFAULT '1970-01-01T00:00:00.000Z'",
            );
          }
        },
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE habits (id TEXT PRIMARY KEY, account TEXT NOT NULL, aspiration TEXT NOT NULL, anchor TEXT NOT NULL, behavior TEXT NOT NULL, celebration TEXT NOT NULL, species TEXT NOT NULL, stage INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT \'active\', updated TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE checkins (id TEXT PRIMARY KEY, account TEXT NOT NULL, habitId TEXT NOT NULL, day TEXT NOT NULL, result TEXT, reason TEXT, ts TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX checkin_days ON checkins(account, habitId, day, ts)',
          );
          await db.execute(
            'CREATE TABLE reflections (id TEXT PRIMARY KEY, account TEXT NOT NULL, habitId TEXT NOT NULL, items TEXT NOT NULL, score REAL NOT NULL, ts TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE voice (id TEXT PRIMARY KEY, account TEXT NOT NULL, kind TEXT NOT NULL, body TEXT NOT NULL, rating INTEGER, status TEXT NOT NULL, replies TEXT NOT NULL, ts TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE settings (account TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, updated TEXT NOT NULL, PRIMARY KEY(account,key))',
          );
          await db.execute(
            'CREATE TABLE events (id TEXT PRIMARY KEY, account TEXT NOT NULL, name TEXT NOT NULL, ts TEXT NOT NULL)',
          );
        },
      ),
    );
    return GardenStore._(db, account);
  }

  Future<void> switchAccount(String account) async => _account = account;
  Future<void> close() => _db.close();

  Future<Habit> plant({
    required String aspiration,
    required String anchor,
    required String behavior,
    required String celebration,
    required String species,
  }) async {
    final fields = [aspiration, anchor, behavior, celebration];
    if (fields.any((s) => s.trim().isEmpty || s.length > 200) ||
        !['Cosmos', 'Sunflower', 'Fern'].contains(species)) {
      throw ArgumentError(
        'Complete each recipe field (maximum 200 characters).',
      );
    }
    final id = _uuid.v4();
    await _db.insert('habits', {
      'id': id,
      'account': _account,
      'aspiration': aspiration.trim(),
      'anchor': anchor.trim(),
      'behavior': behavior.trim(),
      'celebration': celebration.trim(),
      'species': species,
      'updated': DateTime.now().toUtc().toIso8601String(),
    });
    await recordInteraction();
    await track('recipe_created');
    return (await habits()).firstWhere((h) => h.id == id);
  }

  Future<Map<String, Object?>> _owned(String id, DatabaseExecutor db) async {
    final rows = await db.query(
      'habits',
      where: 'id = ? AND account = ?',
      whereArgs: [id, _account],
    );
    if (rows.isEmpty) {
      throw StateError('This habit is not in the signed-in garden.');
    }
    return rows.single;
  }

  Future<void> edit(
    Habit habit, {
    required String anchor,
    required String behavior,
    required String celebration,
  }) async {
    if ([
      anchor,
      behavior,
      celebration,
    ].any((s) => s.trim().isEmpty || s.length > 200)) {
      throw ArgumentError('Recipe fields must contain 1-200 characters.');
    }
    await _owned(habit.id, _db);
    await _db.update(
      'habits',
      {
        'anchor': anchor.trim(),
        'behavior': behavior.trim(),
        'celebration': celebration.trim(),
        'updated': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND account = ?',
      whereArgs: [habit.id, _account],
    );
  }

  Future<List<Map<String, Object?>>> _current(
    DatabaseExecutor db,
    String habitId,
  ) async {
    final rows = await db.query(
      'checkins',
      where: 'account = ? AND habitId = ?',
      whereArgs: [_account, habitId],
      orderBy: 'ts ASC, id ASC',
    );
    final byDay = <String, Map<String, Object?>>{};
    for (final row in rows) {
      byDay[row['day'] as String] = row;
    }
    return byDay.values.where((r) => r['result'] != null).toList();
  }

  Future<void> checkIn(
    String habitId,
    CheckInResult result, {
    String? reason,
    DateTime? now,
  }) => _append(habitId, result.name, reason, now ?? DateTime.now());

  Future<void> undo(String habitId, {DateTime? now}) =>
      _append(habitId, null, null, now ?? DateTime.now());

  Future<void> _append(
    String habitId,
    String? result,
    String? reason,
    DateTime now,
  ) async {
    if (reason != null &&
        !['forgot', 'too hard', 'anchor', 'motivation'].contains(reason)) {
      throw ArgumentError('Unknown check-in reason.');
    }
    await _db.transaction((txn) async {
      final habit = await _owned(habitId, txn);
      final day = localDate(now);
      final previous = await txn.query(
        'checkins',
        where: 'account = ? AND habitId = ? AND day = ?',
        whereArgs: [_account, habitId, day],
        orderBy: 'ts DESC, id DESC',
        limit: 1,
      );
      if (previous.isNotEmpty &&
          previous.first['result'] == result &&
          previous.first['reason'] == reason) {
        return;
      }
      // Monotonic event timestamps resolve fast edits even with a frozen clock.
      var timestamp = now.toUtc();
      if (previous.isNotEmpty) {
        final last = DateTime.parse(previous.first['ts'] as String);
        if (!timestamp.isAfter(last)) {
          timestamp = last.add(const Duration(microseconds: 1));
        }
      }
      final iso = timestamp.toIso8601String();
      final fixedTimestamp =
          '${iso.substring(0, iso.length - 1).padRight(26, '0')}Z';
      await txn.insert('checkins', {
        'id': _uuid.v4(),
        'account': _account,
        'habitId': habitId,
        'day': day,
        'result': result,
        'reason': reason,
        'ts': fixedTimestamp,
      });
      final current = await _current(txn, habitId);
      final practiced = current.where((r) => r['result'] != 'notToday').length;
      final scores = await txn.query(
        'reflections',
        where: 'account = ? AND habitId = ?',
        whereArgs: [_account, habitId],
        orderBy: 'ts DESC',
        limit: 1,
      );
      final score = scores.isEmpty
          ? 0.0
          : (scores.first['score'] as num).toDouble();
      final stage = practiced >= 30 && score >= 4
          ? 4
          : practiced >= 21
          ? 3
          : practiced >= 10
          ? 2
          : practiced >= 3
          ? 1
          : 0;
      await txn.update(
        'habits',
        {
          'stage': stage > (habit['stage'] as int) ? stage : habit['stage'],
          'updated': timestamp.toIso8601String(),
        },
        where: 'id = ? AND account = ?',
        whereArgs: [habitId, _account],
      );
    });
    await recordInteraction();
    await track('checkin');
  }

  Future<void> recordInteraction({DateTime? now}) async {
    await setSetting(
      'lastInteraction',
      (now ?? DateTime.now()).toUtc().toIso8601String(),
    );
    await setSetting('reconnectCount', '0');
  }

  Future<List<int>> practiceMinutes(String habitId) async {
    await _owned(habitId, _db);
    final records =
        (await _current(
            _db,
            habitId,
          )).where((row) => row['result'] != 'notToday').toList()
          ..sort((a, b) => (b['ts'] as String).compareTo(a['ts'] as String));
    return records.take(14).map((row) {
      final time = DateTime.parse(row['ts'] as String).toLocal();
      return time.hour * 60 + time.minute;
    }).toList();
  }

  Future<List<Habit>> habits({DateTime? now}) async {
    final date = now ?? DateTime.now();
    final cutoff = localDate(
      DateTime(
        date.year,
        date.month,
        date.day,
      ).subtract(const Duration(days: 27)),
    );
    final rows = await _db.query(
      'habits',
      where: 'account = ?',
      whereArgs: [_account],
      orderBy: 'updated ASC',
    );
    final result = <Habit>[];
    for (final row in rows) {
      final current = await _current(_db, row['id'] as String);
      final practiced = current.where((r) => r['result'] != 'notToday');
      final today = current.where((r) => r['day'] == localDate(date));
      final reasons = current.where((r) => r['reason'] != null).toList();
      result.add(
        Habit(
          id: row['id'] as String,
          aspiration: row['aspiration'] as String,
          anchor: row['anchor'] as String,
          behavior: row['behavior'] as String,
          celebration: row['celebration'] as String,
          species: row['species'] as String,
          stage: GrowthStage.values[row['stage'] as int],
          status: row['status'] as String,
          practiceCount: practiced.length,
          recentPractice: practiced
              .where(
                (r) =>
                    (r['day'] as String).compareTo(cutoff) >= 0 &&
                    (r['day'] as String).compareTo(localDate(date)) <= 0,
              )
              .length,
          today: today.isEmpty
              ? null
              : CheckInResult.values.byName(today.single['result'] as String),
          lastReason: reasons.isEmpty
              ? null
              : reasons.last['reason'] as String?,
        ),
      );
    }
    return result;
  }

  Future<void> reflect(String habitId, List<int> items, {DateTime? now}) async {
    if (items.length != 4 || items.any((v) => v < 1 || v > 7)) {
      throw ArgumentError('Four scores from 1 to 7 are required.');
    }
    final date = now ?? DateTime.now();
    await _owned(habitId, _db);
    final previous = await _db.query(
      'reflections',
      where: 'account = ? AND habitId = ?',
      whereArgs: [_account, habitId],
      orderBy: 'ts DESC',
      limit: 1,
    );
    if (previous.isNotEmpty &&
        date
                .toUtc()
                .difference(DateTime.parse(previous.first['ts'] as String))
                .inDays <
            14) {
      throw StateError(
        'Your next naturalness check is available 14 days after the previous one.',
      );
    }
    final score = items.reduce((a, b) => a + b) / 4;
    await _db.insert('reflections', {
      'id': _uuid.v4(),
      'account': _account,
      'habitId': habitId,
      'items': jsonEncode(items),
      'score': score,
      'ts': date.toUtc().toIso8601String(),
    });
    final scores = await _db.query(
      'reflections',
      where: 'account = ? AND habitId = ?',
      whereArgs: [_account, habitId],
      orderBy: 'ts DESC',
      limit: 2,
    );
    final habit = (await habits(now: date)).firstWhere((h) => h.id == habitId);
    if (canGraduate(
      scores.map((r) => (r['score'] as num).toDouble()).toList(),
      habit.recentPractice,
    )) {
      await _db.update(
        'habits',
        {
          'status': 'graduated',
          'stage': 4,
          'updated': date.toUtc().toIso8601String(),
        },
        where: 'id = ? AND account = ?',
        whereArgs: [habitId, _account],
      );
      await track('habit_graduated');
    } else if (habit.practiceCount >= 30 && score >= 4) {
      await _db.update(
        'habits',
        {'stage': 4, 'updated': date.toUtc().toIso8601String()},
        where: 'id = ? AND account = ?',
        whereArgs: [habitId, _account],
      );
    }
    await track('reflection');
  }

  Future<String?> setting(String key) async {
    final rows = await _db.query(
      'settings',
      where: 'account = ? AND key = ?',
      whereArgs: [_account, key],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> setSetting(String key, String value) => _db
      .insert('settings', {
        'account': _account,
        'key': key,
        'value': value,
        'updated': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});

  static const eventNames = {
    'recipe_created',
    'checkin',
    'reflection',
    'habit_graduated',
    'feedback_submitted',
    'share_initiated',
    'reminder_sent',
    'signin_succeeded',
  };
  Future<void> track(String name) async {
    if (!eventNames.contains(name)) {
      throw ArgumentError('Unregistered telemetry event.');
    }
    if (await setting('analytics') != 'true') return;
    await _db.insert('events', {
      'id': _uuid.v4(),
      'account': _account,
      'name': name,
      'ts': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> submitVoice(String kind, String body, {int? rating}) async {
    if (![
          'Idea',
          'Bug',
          'Question',
          'Praise',
          'This felt wrong',
          'Rating',
        ].contains(kind) ||
        body.trim().isEmpty ||
        body.length > 2000 ||
        (rating != null && (rating < 1 || rating > 5))) {
      throw ArgumentError(
        'Enter feedback (1-2000 characters) and a valid rating.',
      );
    }
    await _db.insert('voice', {
      'id': _uuid.v4(),
      'account': _account,
      'kind': kind,
      'body': body.trim(),
      'rating': rating,
      'status': 'queued',
      'replies': '[]',
      'ts': DateTime.now().toUtc().toIso8601String(),
    });
    await track('feedback_submitted');
  }

  Future<List<Map<String, Object?>>> voice() => _db.query(
    'voice',
    where: 'account = ?',
    whereArgs: [_account],
    orderBy: 'ts DESC',
  );
  Future<int> eventCount() async =>
      (await _db.rawQuery(
            'SELECT count(*) AS n FROM checkins WHERE account = ?',
            [_account],
          )).single['n']
          as int;

  Future<Map<String, Object?>> export() async {
    final data = <String, Object?>{'schemaVersion': 1};
    for (final table in [
      'habits',
      'checkins',
      'reflections',
      'voice',
      'settings',
      'events',
    ]) {
      data[table] = await _db.query(
        table,
        where: 'account = ?',
        whereArgs: [_account],
      );
    }
    return data;
  }

  Future<void> deleteLocalAccount() async {
    await _db.transaction((txn) async {
      for (final table in [
        'habits',
        'checkins',
        'reflections',
        'voice',
        'settings',
        'events',
      ]) {
        await txn.delete(table, where: 'account = ?', whereArgs: [_account]);
      }
    });
  }

  Future<Map<String, Object?>> syncPayload() async {
    final data = await export();
    final payload = <String, Object?>{};
    for (final table in [
      'habits',
      'checkins',
      'reflections',
      'voice',
      'events',
    ]) {
      payload[table] = (data[table] as List).map((raw) {
        final row = Map<String, Object?>.from(raw as Map)..remove('account');
        if (table == 'voice') {
          row.remove('status');
          row.remove('replies');
        }
        return row;
      }).toList();
    }
    payload['settings'] = (data['settings'] as List)
        .map((raw) => Map<String, Object?>.from(raw as Map)..remove('account'))
        .where((row) => syncedSettings.contains(row['key']))
        .toList();
    return payload;
  }

  static const syncedSettings = {
    'reducedMotion',
    'reminderMinute',
    'quietStart',
    'quietEnd',
    'fewerReminders',
  };

  Future<void> mergeSync(Map<String, dynamic> data) async {
    final columns = {
      'habits': [
        'id',
        'aspiration',
        'anchor',
        'behavior',
        'celebration',
        'species',
        'stage',
        'status',
        'updated',
      ],
      'checkins': ['id', 'habitId', 'day', 'result', 'reason', 'ts'],
      'reflections': ['id', 'habitId', 'items', 'score', 'ts'],
      'voice': ['id', 'kind', 'body', 'rating', 'status', 'replies', 'ts'],
    };
    await _db.transaction((txn) async {
      for (final entry in columns.entries) {
        final rows = data[entry.key];
        if (rows is! List) {
          throw const FormatException('Invalid sync response.');
        }
        for (final raw in rows) {
          if (raw is! Map || entry.value.any((key) => !raw.containsKey(key))) {
            throw const FormatException('Incomplete sync record.');
          }
          final row = <String, Object?>{'account': _account};
          for (final key in entry.value) {
            final value = raw[key];
            if (value != null && value is! String && value is! num) {
              throw const FormatException('Invalid sync field.');
            }
            row[key] = value;
          }
          final existing = await txn.query(
            entry.key,
            where: 'id = ? AND account = ?',
            whereArgs: [row['id'], _account],
          );
          if (existing.isEmpty) {
            await txn.insert(entry.key, row);
          } else if (entry.key == 'habits') {
            final old = existing.single;
            final stage = (row['stage'] as int) > (old['stage'] as int)
                ? row['stage']
                : old['stage'];
            if (newerVersionedRecord(row, old, [
              'aspiration',
              'anchor',
              'behavior',
              'celebration',
              'species',
              'status',
            ])) {
              row['stage'] = stage;
              await txn.update(
                entry.key,
                row,
                where: 'id = ? AND account = ?',
                whereArgs: [row['id'], _account],
              );
            } else {
              await txn.update(
                entry.key,
                {'stage': stage},
                where: 'id = ? AND account = ?',
                whereArgs: [row['id'], _account],
              );
            }
          } else if (entry.key == 'voice') {
            await txn.update(
              entry.key,
              {'status': row['status'], 'replies': row['replies']},
              where: 'id = ? AND account = ?',
              whereArgs: [row['id'], _account],
            );
          }
        }
      }
      final settings = data['settings'] ?? [];
      if (settings is! List) {
        throw const FormatException('Invalid settings response.');
      }
      for (final raw in settings) {
        if (raw is! Map ||
            !syncedSettings.contains(raw['key']) ||
            raw['value'] is! String ||
            raw['updated'] is! String) {
          throw const FormatException('Invalid synced preference.');
        }
        final row = <String, Object?>{
          'account': _account,
          'key': raw['key'],
          'value': raw['value'],
          'updated': raw['updated'],
        };
        final previous = await txn.query(
          'settings',
          where: 'account = ? AND key = ?',
          whereArgs: [_account, row['key']],
        );
        if (previous.isEmpty ||
            newerVersionedRecord(row, previous.single, ['value'])) {
          await txn.insert(
            'settings',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      for (final id in (data['acknowledgedEvents'] as List? ?? [])) {
        await txn.delete(
          'events',
          where: 'id = ? AND account = ?',
          whereArgs: [id, _account],
        );
      }
      final recipes = await txn.query(
        'habits',
        where: 'account = ?',
        whereArgs: [_account],
      );
      for (final habit in recipes) {
        final current = await _current(txn, habit['id'] as String);
        final count = current.where((r) => r['result'] != 'notToday').length;
        final stage = count >= 21
            ? 3
            : count >= 10
            ? 2
            : count >= 3
            ? 1
            : 0;
        if (stage > (habit['stage'] as int)) {
          await txn.update(
            'habits',
            {'stage': stage},
            where: 'id = ? AND account = ?',
            whereArgs: [habit['id'], _account],
          );
        }
      }
    });
  }
}
