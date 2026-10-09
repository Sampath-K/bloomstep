import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

String? _environmentValue(String name) {
  for (final entry in Platform.environment.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

Map<String, String> _allowedProcessEnvironment() {
  final names = Platform.isWindows
      ? const ['PATH', 'SystemRoot', 'TEMP', 'TMP']
      : const ['PATH'];
  final environment = <String, String>{};
  for (final name in names) {
    final value = _environmentValue(name);
    if (value != null) environment[name] = value;
  }
  return environment;
}

class LocalTestApi {
  LocalTestApi._(this.process, this.port);

  final Process process;
  final int port;
  Uri get origin => Uri(scheme: 'http', host: '127.0.0.1', port: port);

  static Future<LocalTestApi> start({
    required Directory runRoot,
    required String secret,
    bool telemetry = false,
  }) async {
    final database = File(p.join(runRoot.path, 'server.json'));
    if (await database.exists()) {
      throw StateError('The owned test API database already exists.');
    }
    final script = p.join(
      Directory.current.path,
      'api',
      'test',
      'support',
      'local_api_server.mjs',
    );
    final processEnvironment = <String, String>{
      ..._allowedProcessEnvironment(),
      'BLOOMSTEP_TEST_AUTH_SECRET': secret,
      'BLOOMSTEP_TEST_DATABASE': database.path,
      'BLOOMSTEP_TEST_PORT': '0',
      'BLOOMSTEP_TEST_REUSE_DATABASE': 'false',
      'BLOOMSTEP_TEST_TELEMETRY': '$telemetry',
    };
    final process = await Process.start(
      'node',
      [script],
      workingDirectory: Directory.current.path,
      environment: processEnvironment,
      includeParentEnvironment: false,
    );
    final ready = Completer<int>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final match = RegExp(r'^TEST_API_READY ([0-9]{1,5})$')
              .firstMatch(line);
          if (match != null && !ready.isCompleted) {
            ready.complete(int.parse(match.group(1)!));
          }
        });
    process.stderr.listen((_) {});
    process.exitCode.then((_) {
      if (!ready.isCompleted) {
        ready.completeError(StateError('The isolated test API did not start.'));
      }
    });
    try {
      return LocalTestApi._(
        process,
        await ready.future.timeout(const Duration(seconds: 30)),
      );
    } catch (_) {
      process.kill();
      rethrow;
    }
  }

  Future<void> close() async {
    process.stdin.writeln('shutdown');
    await process.stdin.flush();
    await process.stdin.close();
    await process.exitCode.timeout(const Duration(seconds: 10));
  }
}
