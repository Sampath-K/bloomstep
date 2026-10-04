import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'rules.dart';
import 'event_registry.g.dart' as registry;

class GardenStore {
  GardenStore._(this._db, this._account);
  final Database _db;
  String _account;
  String get account => _account;
  int _syncGeneration = 0;
  int get syncGeneration => _syncGeneration;
  static const _uuid = Uuid();

  static Future<GardenStore> open(String path, String account) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE settings ADD COLUMN updated TEXT NOT NULL DEFAULT '1970-01-01T00:00:00.000Z'",
            );
          }
          if (oldVersion < 3) await _createSyncState(db);
          if (oldVersion < 4) {
            await db.execute('ALTER TABLE events ADD COLUMN properties TEXT');
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
            'CREATE TABLE events (id TEXT PRIMARY KEY, account TEXT NOT NULL, name TEXT NOT NULL, ts TEXT NOT NULL, properties TEXT)',
          );
          await _createSyncState(db);
        },
      ),
    );
    return GardenStore._(db, account);
  }

  static Future<void> _createSyncState(DatabaseExecutor db) => db.execute(
    'CREATE TABLE sync_state (account TEXT NOT NULL, tableName TEXT NOT NULL, recordId TEXT NOT NULL, fingerprint TEXT NOT NULL, PRIMARY KEY(account,tableName,recordId))',
  );

  Future<void> switchAccount(String account) async {
    _syncGeneration++;
    _account = account;
  }

  void requireSyncSession(String account, int generation) {
    if (_account != account || _syncGeneration != generation) {
      throw StateError(
        'The signed-in garden changed during sync. Retry safely.',
      );
    }
  }

  Future<void> close() => _db.close();

  Future<Habit> plant({
    required String aspiration,
    required String anchor,
    required String behavior,
    required String celebration,
    required String species,
    String? templateCategory,
    bool celebrationPracticed = false,
  }) async {
    final fields = [aspiration, anchor, behavior, celebration];
    if (fields.any((s) => s.trim().isEmpty || s.length > 200) ||
        !['Cosmos', 'Sunflower', 'Fern'].contains(species)) {
      throw ArgumentError(
        'Complete each recipe field (maximum 200 characters).',
      );
    }
    final id = _uuid.v4();
    final properties = <String, Object?>{
      'habitId': id,
      'templateCategory': ?templateCategory,
      'localDay': localDate(DateTime.now()),
      'platform': telemetryPlatform,
    };
    _validateEventProperties('recipe_created', properties);
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
    await track('recipe_created', properties: properties);
    if (celebrationPracticed) {
      await track(
        'celebration_practiced',
        properties: {
          'habitId': id,
          'localDay': localDate(DateTime.now()),
          'platform': telemetryPlatform,
        },
      );
    }
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
    String habitId, {
    String? account,
  }) async {
    final rows = await db.query(
      'checkins',
      where: 'account = ? AND habitId = ?',
      whereArgs: [account ?? _account, habitId],
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
    final account = _account;
    final changed = await _db.transaction((txn) async {
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
        return false;
      }
      final first =
          result != null &&
          result != 'notToday' &&
          (await txn.query(
            'checkins',
            columns: ['id'],
            where: "account = ? AND result IN ('did','didMore')",
            whereArgs: [account],
            limit: 1,
          )).isEmpty;
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
      final properties = <String, Object?>{
        'habitId': habitId,
        'result': result ?? 'undo',
        'localDay': day,
        'platform': telemetryPlatform,
      };
      await _trackWith(txn, account, 'checkin', properties: properties);
      if (first) {
        await _trackWith(txn, account, 'first_checkin', properties: properties);
      }
      return true;
    });
    if (!changed) return;
    await recordInteraction(
      now: now,
      practiced: result != null && result != 'notToday',
    );
  }

  Future<void> recordInteraction({
    DateTime? now,
    bool practiced = false,
    bool positiveReturn = false,
  }) async {
    final date = now ?? DateTime.now();
    final account = _account;
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'settings',
        where: 'account = ?',
        whereArgs: [account],
      );
      final values = {
        for (final row in rows) row['key']: row['value'] as String,
      };
      final stamp = date.toUtc().toIso8601String();
      Future<void> write(String key, String value) async {
        await txn.insert('settings', {
          'account': account,
          'key': key,
          'value': value,
          'updated': stamp,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      if (practiced || positiveReturn) {
        final last = DateTime.tryParse(values['lastInteraction'] ?? '');
        if (last != null && date.toUtc().difference(last).inDays >= 3) {
          final count = int.tryParse(values['ratingComebacks'] ?? '') ?? 0;
          await write('ratingComebacks', '${count + 1}');
          await _trackWith(
            txn,
            account,
            'comeback',
            properties: {
              'localDay': localDate(date),
              'platform': telemetryPlatform,
            },
          );
        }
      }
      await write('lastInteraction', stamp);
      await write('reconnectCount', '0');
    });
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
    if (habit.status != 'graduated' &&
        canGraduate(
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
      await track(
        'habit_graduated',
        properties: {
          'habitId': habitId,
          'score': score,
          'localDay': localDate(date),
          'platform': telemetryPlatform,
        },
      );
    } else if (habit.practiceCount >= 30 && score >= 4) {
      await _db.update(
        'habits',
        {'stage': 4, 'updated': date.toUtc().toIso8601String()},
        where: 'id = ? AND account = ?',
        whereArgs: [habitId, _account],
      );
    }
    await track(
      'automaticity_score',
      properties: {
        'habitId': habitId,
        'score': score,
        'localDay': localDate(date),
        'platform': telemetryPlatform,
      },
    );
  }

  Future<DateTime?> naturalnessAvailableAt(String habitId) async {
    await _owned(habitId, _db);
    final rows = await _db.query(
      'reflections',
      where: 'account = ? AND habitId = ?',
      whereArgs: [_account, habitId],
      orderBy: 'ts DESC',
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : DateTime.parse(rows.single['ts'] as String)
              .add(const Duration(days: 14));
  }

  Future<bool> weeklyReflectionDue({DateTime? now}) async {
    final last = DateTime.tryParse(await setting('weeklyLast') ?? '');
    return last == null ||
        (now ?? DateTime.now()).toUtc().difference(last) >=
            const Duration(days: 7);
  }

  Future<String> weeklyRecommendation(String habitId, {DateTime? now}) async {
    await _owned(habitId, _db);
    final date = now ?? DateTime.now();
    final end = localDate(date);
    final start = localDate(
      DateTime(
        date.year,
        date.month,
        date.day,
      ).subtract(const Duration(days: 6)),
    );
    final counts = {'too hard': 0, 'anchor': 0, 'forgot': 0, 'motivation': 0};
    for (final row in await _current(_db, habitId)) {
      if (row['result'] == 'notToday' &&
          (row['day'] as String).compareTo(start) >= 0 &&
          (row['day'] as String).compareTo(end) <= 0 &&
          counts.containsKey(row['reason'])) {
        final reason = row['reason'] as String;
        counts[reason] = counts[reason]! + 1;
      }
    }
    String? reason;
    var most = 0;
    // Stable ties prioritize reducing effort, then reliability, then specificity.
    for (final entry in counts.entries) {
      if (entry.value > most) {
        reason = entry.key;
        most = entry.value;
      }
    }
    return reason == null
        ? 'Keep what feels easy. If you want to experiment, choose a more specific anchor, a smaller step, or a celebration you enjoy. No change is required.'
        : recipeDoctor(reason);
  }

  Future<void> completeWeeklyReflection(String habitId, {DateTime? now}) async {
    await _owned(habitId, _db);
    await setSetting(
      'weeklyLast',
      (now ?? DateTime.now()).toUtc().toIso8601String(),
    );
    await track(
      'weekly_reflection',
      properties: {
        'habitId': habitId,
        'localDay': localDate(now ?? DateTime.now()),
        'platform': telemetryPlatform,
      },
    );
  }

  /// Call only after a successful positive moment, never on load or a miss.
  /// Claim before displaying; dismissing or snoozing retains the same cooldown.
  Future<bool> claimRatingPrompt({
    DateTime? now,
    bool positiveMoment = true,
  }) async {
    if (!positiveMoment) return false;
    final date = (now ?? DateTime.now()).toUtc();
    final account = _account;
    return _db.transaction((txn) async {
      final settings = await txn.query(
        'settings',
        where: 'account = ?',
        whereArgs: [account],
      );
      final values = {for (final r in settings) r['key']: r['value'] as String};
      final last = DateTime.tryParse(values['ratingPromptedAt'] ?? '');
      if (last != null && date.difference(last) < const Duration(days: 120)) {
        return false;
      }
      final rows = await txn.query(
        'habits',
        where: 'account = ?',
        whereArgs: [account],
      );
      final days = <String>{};
      for (final h in rows) {
        for (final row in await _current(
          txn,
          h['id'] as String,
          account: account,
        )) {
          if (row['result'] != 'notToday' &&
              (row['day'] as String).compareTo(localDate(date.toLocal())) <=
                  0) {
            days.add(row['day'] as String);
          }
        }
      }
      if (!rows.any((h) => h['status'] == 'graduated') &&
          days.length < 30 &&
          (int.tryParse(values['ratingComebacks'] ?? '') ?? 0) < 3) {
        return false;
      }
      await txn.insert('settings', {
        'account': account,
        'key': 'ratingPromptedAt',
        'value': date.toIso8601String(),
        'updated': date.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _trackWith(
        txn,
        account,
        'rating_prompted',
        properties: {
          'localDay': localDate(date.toLocal()),
          'platform': telemetryPlatform,
        },
      );
      return true;
    });
  }

  Future<String?> setting(String key) async {
    final rows = await _db.query(
      'settings',
      where: 'account = ? AND key = ?',
      whereArgs: [_account, key],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final account = _account;
    await _db.transaction((txn) async {
      final previous = key == 'analytics'
          ? await txn.query(
              'settings',
              where: 'account = ? AND key = ?',
              whereArgs: [account, key],
            )
          : <Map<String, Object?>>[];
      await txn.insert('settings', {
        'account': account,
        'key': key,
        'value': value,
        'updated': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (key == 'analytics' && value != 'true') {
        await txn.delete('events', where: 'account = ?', whereArgs: [account]);
        await txn.delete(
          'sync_state',
          where: 'account = ? AND tableName = ?',
          whereArgs: [account, 'events'],
        );
      } else if (key == 'analytics' &&
          value == 'true' &&
          (previous.isEmpty || previous.single['value'] != 'true')) {
        await _trackWith(
          txn,
          account,
          'analytics_consent',
          properties: {'platform': telemetryPlatform},
        );
      }
    });
  }

  Future<void> saveInvitationState(
    String value, {
    String? acceptedChannel,
  }) async {
    final account = _account;
    await _db.transaction((txn) async {
      await txn.insert('settings', {
        'account': account,
        'key': 'invitationState',
        'value': value,
        'updated': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (acceptedChannel != null) {
        await _trackWith(
          txn,
          account,
          'invite_accepted',
          properties: {
            // Current registry lacks qr/native enums; do not invent taxonomy.
            'channel': ['link', 'email'].contains(acceptedChannel)
                ? acceptedChannel
                : 'invite',
            'platform': telemetryPlatform,
          },
        );
      }
    });
  }

  Future<void> track(String name, {Map<String, Object?>? properties}) async {
    _validateEventProperties(name, properties);
    final copy = properties == null
        ? null
        : Map<String, Object?>.from(properties);
    final account = _account;
    await _db.transaction((txn) async {
      await _trackWith(txn, account, name, properties: copy);
    });
  }

  static Future<void> _trackWith(
    DatabaseExecutor txn,
    String account,
    String name, {
    Map<String, Object?>? properties,
  }) async {
    _validateEventProperties(name, properties);
    final consent = await txn.query(
      'settings',
      where: 'account = ? AND key = ?',
      whereArgs: [account, 'analytics'],
    );
    if (consent.isEmpty || consent.single['value'] != 'true') return;
    await txn.insert('events', {
      'id': _uuid.v4(),
      'account': account,
      'name': name,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'properties': properties == null ? null : jsonEncode(properties),
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
        (body.trim().isEmpty && kind != 'Rating') ||
        body.length > 2000 ||
        (kind == 'Rating' && rating == null) ||
        (rating != null && (rating < 1 || rating > 5))) {
      throw ArgumentError(
        'Enter feedback (1-2000 characters) and a valid rating.',
      );
    }
    final id = _uuid.v4();
    await _db.insert('voice', {
      'id': id,
      'account': _account,
      'kind': kind,
      'body': body.trim(),
      'rating': rating,
      'status': 'queued',
      'replies': '[]',
      'ts': DateTime.now().toUtc().toIso8601String(),
    });
    await track(
      'feedback_submitted',
      properties: {
        'feedbackId': id,
        'kind': kind,
        'platform': telemetryPlatform,
      },
    );
    if (kind == 'Rating') {
      await track(
        'rated',
        properties: {
          'rating': rating,
          'localDay': localDate(DateTime.now()),
          'platform': telemetryPlatform,
        },
      );
    }
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
    final invitations = await setting('invitationState');
    if (invitations != null) {
      final state = jsonDecode(invitations) as Map<String, dynamic>;
      data['invitationReceipts'] = {
        'version': state['version'],
        'creations': [
          for (final row in state['creations'] as List)
            {
              'requestId': row['payload']['requestId'],
              'channel': row['payload']['channel'],
              if (row['receipt'] != null)
                'receipt': {...row['receipt'] as Map}..remove('token'),
            },
        ],
        'redemptionReceipt': state['redemption']?['receipt'],
        'status': state['status'],
      };
    }
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
      if (table == 'settings') {
        data[table] = (data[table] as List)
            .where((row) => row['key'] != 'invitationState')
            .toList();
      }
    }
    return data;
  }

  Future<void> deleteLocalAccount() async {
    _syncGeneration++;
    final account = _account;
    await _db.transaction((txn) async {
      for (final table in [
        'habits',
        'checkins',
        'reflections',
        'voice',
        'settings',
        'events',
        'sync_state',
      ]) {
        await txn.delete(table, where: 'account = ?', whereArgs: [account]);
      }
    });
  }

  static const syncTables = [
    'habits',
    'checkins',
    'reflections',
    'voice',
    'events',
    'settings',
  ];

  static Map<String, Object?> _wireRow(String table, Map<String, Object?> raw) {
    final row = Map<String, Object?>.from(raw)..remove('account');
    if (table == 'voice') {
      row.remove('status');
      row.remove('replies');
    }
    if (table == 'events') {
      final properties = row['properties'];
      if (properties == null) {
        row.remove('properties');
      } else {
        final decoded = properties is String
            ? jsonDecode(properties)
            : properties;
        if (decoded is! Map) {
          throw const FormatException('Invalid telemetry properties.');
        }
        final values = Map<String, Object?>.from(decoded);
        _validateEventProperties(row['name'] as String, values);
        final keys = values.keys.toList()..sort();
        row['properties'] = {for (final key in keys) key: values[key]};
      }
    }
    return row;
  }

  static String get telemetryPlatform =>
      kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

  static const eventNames = registry.eventNames;

  static void _validateEventProperties(
    String name,
    Map<String, Object?>? properties,
  ) {
    if (!registry.isValidEventProperties(name, properties ?? const {})) {
      throw ArgumentError('Unregistered telemetry event or invalid metadata.');
    }
  }

  static String _recordId(String table, Map<String, Object?> row) =>
      row[table == 'settings' ? 'key' : 'id'] as String;

  static String _fingerprint(String table, Map<String, Object?> raw) {
    final row = _wireRow(table, raw);
    final keys = row.keys.toList()..sort();
    return sha256
        .convert(
          utf8.encode(jsonEncode({for (final key in keys) key: row[key]})),
        )
        .toString();
  }

  static Future<void> _rememberSync(
    DatabaseExecutor db,
    String account,
    String table,
    Map<String, Object?> row,
  ) async {
    await db.insert('sync_state', {
      'account': account,
      'tableName': table,
      'recordId': _recordId(table, row),
      'fingerprint': _fingerprint(table, row),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// A transaction snapshots each pending record; acknowledgment compares that
  /// exact snapshot so edits made during the HTTP request remain pending.
  Future<Map<String, Object?>> syncPayload() async {
    final account = _account;
    final generation = _syncGeneration;
    return _db.transaction((txn) async {
      requireSyncSession(account, generation);
      final state = await txn.query(
        'sync_state',
        where: 'account = ?',
        whereArgs: [account],
      );
      final known = {
        for (final row in state)
          '${row['tableName']}:${row['recordId']}': row['fingerprint'],
      };
      final payload = <String, Object?>{};
      for (final table in syncTables) {
        final rows = await txn.query(
          table,
          where: 'account = ?',
          whereArgs: [account],
          orderBy: table == 'settings' ? 'key ASC' : 'id ASC',
        );
        payload[table] = rows
            .where(
              (row) =>
                  table != 'settings' || syncedSettings.contains(row['key']),
            )
            .where(
              (row) =>
                  known['$table:${_recordId(table, row)}'] !=
                  _fingerprint(table, row),
            )
            .map((row) => _wireRow(table, row))
            .toList();
      }
      requireSyncSession(account, generation);
      return payload;
    });
  }

  Future<void> acknowledgeSync(
    Map<String, Object?> submitted, {
    String? account,
    int? generation,
  }) async {
    final owner = account ?? _account;
    final session = generation ?? _syncGeneration;
    await _db.transaction((txn) async {
      requireSyncSession(owner, session);
      for (final table in syncTables) {
        for (final raw in submitted[table] as List? ?? []) {
          final row = Map<String, Object?>.from(raw as Map);
          final current = await txn.query(
            table,
            where: '${table == 'settings' ? 'key' : 'id'} = ? AND account = ?',
            whereArgs: [_recordId(table, row), owner],
          );
          if (current.isNotEmpty &&
              _fingerprint(table, current.single) == _fingerprint(table, row)) {
            await _rememberSync(txn, owner, table, row);
          }
        }
      }
      requireSyncSession(owner, session);
    });
  }

  static const syncedSettings = {
    'reducedMotion',
    'reminderMinute',
    'quietStart',
    'quietEnd',
    'fewerReminders',
    'weeklyLast',
    'ratingPromptedAt',
  };

  Future<void> mergeSync(
    Map<String, dynamic> data, {
    String? account,
    int? generation,
  }) async {
    final owner = account ?? _account;
    final session = generation ?? _syncGeneration;
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
      requireSyncSession(owner, session);
      for (final entry in columns.entries) {
        final rows = data[entry.key];
        if (rows is! List) {
          throw const FormatException('Invalid sync response.');
        }
        for (final raw in rows) {
          if (raw is! Map || entry.value.any((key) => !raw.containsKey(key))) {
            throw const FormatException('Incomplete sync record.');
          }
          final row = <String, Object?>{'account': owner};
          for (final key in entry.value) {
            final value = raw[key];
            if (value != null && value is! String && value is! num) {
              throw const FormatException('Invalid sync field.');
            }
            row[key] = value;
          }
          final received = Map<String, Object?>.from(row);
          final existing = await txn.query(
            entry.key,
            where: 'id = ? AND account = ?',
            whereArgs: [row['id'], owner],
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
                whereArgs: [row['id'], owner],
              );
            } else {
              await txn.update(
                entry.key,
                {'stage': stage},
                where: 'id = ? AND account = ?',
                whereArgs: [row['id'], owner],
              );
            }
          } else if (entry.key == 'voice') {
            await txn.update(
              entry.key,
              {'status': row['status'], 'replies': row['replies']},
              where: 'id = ? AND account = ?',
              whereArgs: [row['id'], owner],
            );
          }
          await _rememberSync(txn, owner, entry.key, received);
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
          'account': owner,
          'key': raw['key'],
          'value': raw['value'],
          'updated': raw['updated'],
        };
        final previous = await txn.query(
          'settings',
          where: 'account = ? AND key = ?',
          whereArgs: [owner, row['key']],
        );
        if (row['key'] == 'weeklyLast' || row['key'] == 'ratingPromptedAt') {
          final stamp = DateTime.tryParse(row['value'] as String);
          if (stamp == null || !(row['value'] as String).endsWith('Z')) {
            throw const FormatException('Invalid cadence timestamp.');
          }
          final old = previous.isEmpty
              ? null
              : DateTime.tryParse(previous.single['value'] as String);
          if (old != null && old.isAfter(stamp)) continue;
        }
        if (previous.isEmpty ||
            newerVersionedRecord(row, previous.single, ['value'])) {
          await txn.insert(
            'settings',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await _rememberSync(txn, owner, 'settings', row);
      }
      for (final id in (data['acknowledgedEvents'] as List? ?? [])) {
        await txn.delete(
          'events',
          where: 'id = ? AND account = ?',
          whereArgs: [id, owner],
        );
        await txn.delete(
          'sync_state',
          where: 'account = ? AND tableName = ? AND recordId = ?',
          whereArgs: [owner, 'events', id],
        );
      }
      final recipes = await txn.query(
        'habits',
        where: 'account = ?',
        whereArgs: [owner],
      );
      for (final habit in recipes) {
        final current = await _current(
          txn,
          habit['id'] as String,
          account: owner,
        );
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
            whereArgs: [habit['id'], owner],
          );
        }
      }
      requireSyncSession(owner, session);
    });
  }
}
