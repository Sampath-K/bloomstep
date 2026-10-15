part of 'garden_store.dart';

extension GardenExperienceStore on GardenStore {
  static const _stateKey = 'experienceExperimentState';

  void configureExperiences(
    ExperienceConfig config,
    ExperienceAssignmentProvider provider,
  ) {
    if (_experienceConfig.key == config.key &&
        _experienceConfig.enabled == config.enabled &&
        _experienceProvider?.id == provider.id) {
      return;
    }
    _experienceConfig = config;
    _experienceProvider = provider;
    experienceChanges.value++;
  }

  Future<Map<String, dynamic>?> _experienceState(
    DatabaseExecutor txn,
    String owner,
  ) async {
    final raw = await GardenStore._valueWith(txn, owner, _stateKey);
    if (raw == null) return null;
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic> ||
        json['schemaVersion'] != 1 ||
        json['policyHash'] != experiencePolicyHash ||
        !RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch('${json['cohortId']}') ||
        !RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch('${json['consentEpoch']}') ||
        json['configKey'] is! String ||
        json['provider'] is! String ||
        json['events'] is! List ||
        !(json['events'] as List).every(
          (e) => const {
            'rendered',
            'task_completed',
            'followup',
            'practice',
            'error',
            'burden',
          }.contains(e),
        ) ||
        json['configVersion'] is! int ||
        DateTime.tryParse('${json['lastAt']}') == null ||
        (json['exposedAt'] != null &&
            DateTime.tryParse('${json['exposedAt']}') == null) ||
        !ExperienceSurface.values.any((s) => s.name == json['surface'])) {
      throw const FormatException(
        'Saved experiment scope is invalid. No experiment was rendered.',
      );
    }
    return json;
  }

  Future<void> _saveExperience(
    DatabaseExecutor txn,
    String owner,
    Map<String, dynamic> state,
  ) => txn.insert('settings', {
    'account': owner,
    'key': _stateKey,
    'value': jsonEncode(state),
    'updated': _clock().toUtc().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  ExperienceAssignment _assignment(
    Map<String, dynamic> state,
    String owner,
    int generation,
    int consentGeneration,
  ) {
    final surface = ExperienceSurface.values.singleWhere(
      (s) => s.name == state['surface'],
    );
    if (state['provider'] != _experienceProvider?.id) {
      return ExperienceAssignment.control(surface);
    }
    final arm = _experienceProvider?.evaluate(
      _experienceConfig,
      '${state['consentEpoch']}:${state['cohortId']}',
    );
    if (arm == null) return ExperienceAssignment.control(surface);
    return ExperienceAssignment(
      surface: surface,
      arm: arm,
      active: true,
      cohortId: state['cohortId'] as String,
      consentEpoch: state['consentEpoch'] as String,
      owner: owner,
      generation: generation,
      consentGeneration: consentGeneration,
      configKey: state['configKey'] as String,
    );
  }

  Future<ExperienceAssignment> resolveExperience(
    ExperienceSurface surface,
    ExperienceConfig config,
    DateTime at,
  ) async {
    final owner = account,
        generation = syncGeneration,
        consentGeneration = analyticsGeneration;
    final control = ExperienceAssignment.control(surface);
    if (!config.activeAt(at) ||
        config.key != _experienceConfig.key ||
        !_experienceConfig.enabled ||
        config.surface != surface ||
        owner == 'device-guest') {
      return control;
    }
    return _db.transaction((txn) async {
      requireSyncSession(owner, generation);
      if (consentGeneration != analyticsGeneration ||
          await GardenStore._valueWith(txn, owner, 'analytics') != 'true') {
        return control;
      }
      var state = await _experienceState(txn, owner);
      if (state != null && state['configKey'] != config.key) return control;
      state ??= {
        'schemaVersion': 1,
        'policyHash': experiencePolicyHash,
        'provider': _experienceProvider?.id,
        'cohortId': GardenStore._uuid.v4(),
        'consentEpoch': GardenStore._uuid.v4(),
        'surface': surface.name,
        'configKey': config.key,
        'configVersion': config.version,
        'createdAt': at.toUtc().toIso8601String(),
        'lastAt': at.toUtc().toIso8601String(),
        'exposedAt': null,
        'events': <String>[],
      };
      if (at.toUtc().isBefore(DateTime.parse(state['lastAt'] as String))) {
        return control;
      }
      await _saveExperience(txn, owner, state);
      requireSyncSession(owner, generation);
      return _assignment(state, owner, generation, consentGeneration);
    });
  }

  Future<bool> recordExperience(
    ExperienceAssignment assignment,
    ExperienceConfig config,
    String outcome,
    DateTime at,
  ) async {
    const allowed = {'rendered', 'task_completed', 'error', 'burden'};
    if (!allowed.contains(outcome)) {
      throw ArgumentError('Unknown experience observation.');
    }
    if (!assignment.active ||
        assignment.owner != account ||
        assignment.generation != syncGeneration ||
        assignment.consentGeneration != analyticsGeneration ||
        config.key != assignment.configKey ||
        config.key != _experienceConfig.key ||
        !_experienceConfig.enabled ||
        !config.activeAt(at)) {
      return false;
    }
    return _db.transaction((txn) async {
      if (assignment.owner != account ||
          assignment.generation != syncGeneration ||
          assignment.consentGeneration != analyticsGeneration ||
          config.key != _experienceConfig.key ||
          !_experienceConfig.enabled ||
          await GardenStore._valueWith(txn, account, 'analytics') != 'true') {
        return false;
      }
      final state = await _experienceState(txn, account);
      final expected = state == null
          ? null
          : _assignment(state, account, syncGeneration, analyticsGeneration);
      if (state == null ||
          state['configKey'] != config.key ||
          state['cohortId'] != assignment.cohortId ||
          state['consentEpoch'] != assignment.consentEpoch ||
          expected?.active != true ||
          expected?.arm != assignment.arm ||
          at.toUtc().isBefore(DateTime.parse(state['lastAt'] as String))) {
        return false;
      }
      if (outcome != 'rendered' && state['exposedAt'] == null) return false;
      if (outcome == 'rendered') {
        state['exposedAt'] ??= at.toUtc().toIso8601String();
      }
      if (outcome == 'task_completed' &&
          at.toUtc().difference(DateTime.parse(state['exposedAt'] as String)) >
              ExperienceDefinition.taskWindow) {
        return false;
      }
      await _experienceEvent(txn, account, state, assignment.arm, outcome, at);
      await _saveExperience(txn, account, state);
      return true;
    });
  }

  Future<void> _experienceEvent(
    DatabaseExecutor txn,
    String owner,
    Map<String, dynamic> state,
    ExperienceArm arm,
    String outcome,
    DateTime at,
  ) async {
    final emitted = (state['events'] as List).cast<String>();
    if (emitted.contains(outcome)) return;
    final surface = ExperienceSurface.values.singleWhere(
      (s) => s.name == state['surface'],
    );
    await _trackWith(
      txn,
      owner,
      'experience_observation',
      at: at,
      properties: {
        'experienceStudy': ExperienceDefinition(surface).id,
        'experienceArm': arm.name,
        'experienceOutcome': outcome,
        'experiencePolicy': 'app_experience_v1',
        'configVersion': state['configVersion'],
        'cohortId': state['cohortId'],
        'consentEpoch': state['consentEpoch'],
        'platform': 'windows',
      },
    );
    state['events'] = [...emitted, outcome];
    state['lastAt'] = at.toUtc().toIso8601String();
  }

  Future<void> experienceTaskSaved() async {
    final owner = account, generation = syncGeneration;
    await _db.transaction((txn) async {
      requireSyncSession(owner, generation);
      if (!_experienceConfig.activeAt(_clock()) ||
          await GardenStore._valueWith(txn, owner, 'analytics') != 'true') {
        return;
      }
      final state = await _experienceState(txn, owner);
      if (state == null ||
          state['configKey'] != _experienceConfig.key ||
          state['provider'] != _experienceProvider?.id ||
          state['surface'] != ExperienceSurface.gardenPrompt.name ||
          state['exposedAt'] == null) {
        return;
      }
      final at = _clock().toUtc(),
          exposed = DateTime.parse(state['exposedAt'] as String);
      final assigned = _assignment(
        state,
        owner,
        generation,
        analyticsGeneration,
      );
      if (!assigned.active) return;
      if (at.isBefore(DateTime.parse(state['lastAt'] as String)) ||
          at.difference(exposed) > ExperienceDefinition.taskWindow) {
        return;
      }
      await _experienceEvent(
        txn,
        owner,
        state,
        assigned.arm,
        'task_completed',
        at,
      );
      await _saveExperience(txn, owner, state);
    });
  }

  Future<void> followupExperience(ExperienceConfig config, DateTime at) async {
    if (!config.enabled ||
        config.key != _experienceConfig.key ||
        !_experienceConfig.enabled) {
      return;
    }
    final owner = account, generation = syncGeneration;
    await _db.transaction((txn) async {
      requireSyncSession(owner, generation);
      if (await GardenStore._valueWith(txn, owner, 'analytics') != 'true') {
        return;
      }
      final state = await _experienceState(txn, owner);
      if (state == null ||
          config.key != _experienceConfig.key ||
          !_experienceConfig.enabled ||
          state['configKey'] != config.key ||
          state['exposedAt'] == null) {
        return;
      }
      final exposed = DateTime.parse(state['exposedAt'] as String);
      final end = exposed.add(ExperienceDefinition.followup);
      if (at.toUtc().isBefore(end) ||
          at.toUtc().isAfter(end.add(const Duration(days: 7))) ||
          at.toUtc().isBefore(DateTime.parse(state['lastAt'] as String)) ||
          (state['events'] as List).contains('followup')) {
        return;
      }
      final rows = await txn.query(
        'checkins',
        where: 'account = ?',
        whereArgs: [owner],
        orderBy: 'ts ASC, id ASC',
      );
      final effective = <String, Map<String, Object?>>{};
      for (final row in rows) {
        final ts = DateTime.parse(row['ts'] as String);
        if (ts.isBefore(exposed) || !ts.isBefore(end)) continue;
        effective['${row['habitId']}:${row['day']}'] = row;
      }
      final arm = _assignment(state, owner, generation, analyticsGeneration);
      if (!arm.active) return;
      await _experienceEvent(txn, owner, state, arm.arm, 'followup', at);
      if (effective.values.any(
        (r) => r['result'] == 'did' || r['result'] == 'didMore',
      )) {
        await _experienceEvent(txn, owner, state, arm.arm, 'practice', at);
      }
      await _saveExperience(txn, owner, state);
    });
  }
}
