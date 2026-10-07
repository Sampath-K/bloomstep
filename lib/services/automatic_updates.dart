import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'update_service.dart';

class AutomaticUpdates extends ChangeNotifier {
  AutomaticUpdates({
    required this.preferences,
    UpdateService? discovery,
    this.interval = const Duration(hours: 24),
  }) : discovery = discovery ?? UpdateService();

  final File preferences;
  final UpdateService discovery;
  final Duration interval;
  Timer? _timer;
  bool _disposed = false;
  bool _started = false;
  bool savingPreference = false;
  bool enabled = true;
  bool checking = false;
  String status = 'Automatic update check has not run yet.';
  UpdateInfo? available;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    try {
      if (await preferences.exists()) {
        final raw = jsonDecode(await preferences.readAsString());
        if (raw is! Map || raw.length != 1 || raw['enabled'] is! bool) {
          throw const FormatException('Invalid automatic update preference.');
        }
        enabled = raw['enabled'] as bool;
      }
      if (_disposed) return;
      _timer = Timer.periodic(interval, (_) => unawaited(check()));
      await check();
    } catch (error) {
      enabled = false;
      status = 'Automatic updates could not start: $error';
      _changed();
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_disposed || savingPreference) return;
    savingPreference = true;
    _changed();
    try {
      await preferences.parent.create(recursive: true);
      final temporary = File('${preferences.path}.part');
      await temporary.writeAsString(
        jsonEncode({'enabled': value}),
        flush: true,
      );
      // Rename replaces the old file without deleting the user's durable choice.
      await temporary.rename(preferences.path);
      enabled = value;
      status = value ? 'Automatic checks enabled.' : 'Automatic checks disabled. Windows-managed MSIX updates are configured in Windows Settings.';
      _changed();
      if (value) await check();
    } catch (error) {
      status = 'Update preference could not be saved: $error';
      _changed();
    } finally {
      savingPreference = false;
      _changed();
    }
  }

  Future<void> check() async {
    if (_disposed || checking) return;
    if (!enabled) {
      status =
          'Automatic checks disabled. No update was downloaded or installed.';
      _changed();
      return;
    }
    checking = true;
    status = 'Checking for updates...';
    _changed();
    try {
      final result = await discovery.check();
      if (_disposed || !enabled) return;
      available = result;
      status = available == null
          ? 'No newer release found. Inno installations require manual updates; signed MSIX installations update through Windows.'
          : '${available!.version} is available. Inno installations require manual updates; signed MSIX installations update through Windows.';
    } catch (error) {
      if (!_disposed && enabled) {
        status = 'Update check failed; nothing was installed: $error';
      }
    } finally {
      checking = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
