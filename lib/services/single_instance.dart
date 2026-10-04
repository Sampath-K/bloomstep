import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

class SingleInstance {
  SingleInstance(this.directory, this.activate, this.reportError);
  final String directory;
  final Future<void> Function() activate;
  final void Function(String) reportError;
  RandomAccessFile? _lock;
  ServerSocket? _server;
  final _clients = <Socket>{};
  String? _token;
  bool _closed = false;
  String get _descriptor => p.join(directory, 'instance.json');

  Future<bool> start() async {
    if (_closed || _lock != null) {
      throw StateError('Instance coordinator is already used.');
    }
    await Directory(directory).create(recursive: true);
    final lock = await File(p.join(directory, 'instance.lock'))
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive, 0, 1);
    } on FileSystemException catch (error) {
      await lock.close();
      if (![11, 32, 33].contains(error.osError?.errorCode)) rethrow;
      await _activateExisting();
      return false;
    }
    _lock = lock;
    try {
      _token = List.generate(
        32,
        (_) => Random.secure().nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen(
        (socket) {
          if (_clients.length >= 8) {
            socket.destroy();
            reportError('Local activation is busy; no command was accepted.');
            return;
          }
          unawaited(_serve(socket));
        },
        onError: (Object error) =>
            reportError('The local activation listener failed.'),
      );
      final next = File('$_descriptor.next');
      await next.writeAsString(
        jsonEncode({'port': server.port, 'pid': pid, 'token': _token}),
        flush: true,
      );
      await next.rename(_descriptor);
      return true;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _packet(Socket socket) async {
    final bytes = <int>[];
    await for (final chunk in socket) {
      bytes.addAll(chunk);
      if (bytes.length > 256) {
        throw const FormatException('Activation packet is too large.');
      }
      final end = bytes.indexOf(10);
      if (end < 0) continue;
      final decoded = jsonDecode(utf8.decode(bytes.sublist(0, end)));
      if (decoded is! Map) {
        throw const FormatException('Invalid activation packet.');
      }
      return decoded.cast<String, dynamic>();
    }
    throw const FormatException(
      'Activation connection ended without a command.',
    );
  }

  Future<void> _serve(Socket socket) async {
    _clients.add(socket);
    try {
      final packet = await _packet(socket).timeout(const Duration(seconds: 2));
      if (_closed ||
          packet.length != 2 ||
          packet['command'] != 'activate' ||
          packet['token'] is! String ||
          !_sameToken(packet['token'] as String)) {
        throw const FormatException('Invalid local activation request.');
      }
      await activate();
      socket.writeln(jsonEncode({'ok': true}));
      await socket.flush();
    } catch (_) {
      reportError('Local activation was rejected or could not be completed.');
      try {
        socket.writeln(
          jsonEncode({'error': 'Local activation could not be completed.'}),
        );
        await socket.flush();
      } on SocketException {
        reportError('Local activation response could not be delivered.');
      }
    } finally {
      _clients.remove(socket);
      socket.destroy();
    }
  }

  bool _sameToken(String value) {
    final token = _token!;
    if (value.length != token.length) return false;
    var difference = 0;
    for (var i = 0; i < token.length; i++) {
      difference |= token.codeUnitAt(i) ^ value.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<void> _activateExisting() async {
    Map<String, dynamic>? descriptor;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        final decoded = jsonDecode(await File(_descriptor).readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Invalid instance descriptor.');
        }
        descriptor = decoded;
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } on FormatException {
        throw StateError(
          'Existing Bloomstep instance metadata is invalid. Close the old app and retry.',
        );
      }
    }
    if (descriptor == null ||
        descriptor['port'] is! int ||
        descriptor['port'] < 1 ||
        descriptor['port'] > 65535 ||
        descriptor['pid'] is! int ||
        descriptor['pid'] < 1 ||
        descriptor['token'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(descriptor['token'] as String)) {
      throw StateError(
        'An existing Bloomstep instance is not ready. Retry after it finishes starting.',
      );
    }
    if (Platform.isWindows) {
      final permit = DynamicLibrary.open('user32.dll')
          .lookupFunction<Int32 Function(Uint32), int Function(int)>(
            'AllowSetForegroundWindow',
          );
      permit(descriptor['pid'] as int);
    }
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      descriptor['port'] as int,
    ).timeout(const Duration(seconds: 2));
    try {
      socket.writeln(
        jsonEncode({'command': 'activate', 'token': descriptor['token']}),
      );
      await socket.flush();
      final response = await _packet(socket)
          .timeout(const Duration(seconds: 2));
      if (response['ok'] != true) {
        throw StateError('The existing app could not activate its window.');
      }
    } finally {
      socket.destroy();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _server?.close();
      for (final socket in _clients.toList()) {
        socket.destroy();
      }
      final file = File(_descriptor);
      if (_lock != null && await file.exists()) {
        try {
          final record = jsonDecode(await file.readAsString());
          if (record is Map && record['token'] == _token) {
            await file.delete();
          }
        } on FormatException {
          reportError(
            'Local instance metadata is damaged; it was preserved for diagnosis.',
          );
        }
      }
    } finally {
      final lock = _lock;
      _lock = null;
      if (lock != null) {
        try {
          await lock.unlock(0, 1);
        } finally {
          await lock.close();
        }
      }
    }
  }
}
