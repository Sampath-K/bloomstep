import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/measurement_receipt.dart';

class InstallerMeasurement {
  InstallerMeasurement(
    String directory, {
    DateTime Function()? clock,
    this.ownerId,
  }) : path = p.join(directory, 'installer-receipt.json'),
       _clock = clock ?? DateTime.now;
  final String path;
  final DateTime Function() _clock;
  final String? ownerId;
  Future<void> _pending = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    // Keep the queue available after failure; the caller still receives it.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<MeasurementReceipt?> read() => _serial(_read);

  Future<MeasurementReceipt?> _read() async {
    final file = File(path);
    if (!await file.exists()) return null;
    if (await file.length() > MeasurementReceipt.maxBytes) {
      throw const FormatException(
        'Installer measurement receipt is too large. No observations collected.',
      );
    }
    try {
      final receipt = MeasurementReceipt.parse(
        await file.readAsString(),
        now: _clock(),
      );
      if (receipt.source != 'installer') {
        throw const FormatException(
          'Installer receipt has an unsupported source.',
        );
      }
      return receipt;
    } on ExpiredMeasurementReceipt {
      await _clear();
      return null;
    }
  }

  Future<bool> observe(String name) {
    if (!['first_launch', 'signin_view'].contains(name)) {
      throw ArgumentError.value(name, 'name');
    }
    return _serial(() async {
      final receipt = await _read();
      if (receipt == null ||
          ownerId == null ||
          receipt.events.first.id != ownerId ||
          !receipt.events.any((e) => e.name == 'install_completed') ||
          receipt.events.any((e) => e.name == name)) {
        return false;
      }
      if (name == 'signin_view' &&
          !receipt.events.any((e) => e.name == 'first_launch')) {
        throw StateError(
          'A sign-in view cannot precede an observed first launch.',
        );
      }
      final original = jsonEncode(receipt.toJson());
      final data = receipt.toJson();
      (data['events'] as List).add({
        'id': const Uuid().v4(),
        'name': name,
        'ts': _clock().toUtc().toIso8601String(),
      });
      final text = jsonEncode(data);
      MeasurementReceipt.parse(text, now: _clock());
      final latest = await _read();
      if (latest == null || jsonEncode(latest.toJson()) != original) {
        throw StateError(
          'Installer receipt changed. No launch observation was written; retry safely.',
        );
      }
      final temporary = File('$path.pending');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
      return true;
    });
  }

  Future<void> clear() => _serial(_clear);

  Future<void> _clear() async {
    for (final name in [path, '$path.pending']) {
      final file = File(name);
      if (await file.exists()) await file.delete();
    }
  }
}
