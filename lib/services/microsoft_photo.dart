import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Only a trusted identity adapter may supply this proof, never UI input,
/// email, a CIAM oid, or a subject from a different OIDC client.
class MicrosoftPhotoIdentity {
  const MicrosoftPhotoIdentity({
    required this.bloomstepAccount,
    required this.tenantId,
    required this.objectId,
  });
  static const consumerTenant = '9188040d-6c67-4c5b-b112-36a304b66dad';
  final String bloomstepAccount;
  final String tenantId;
  final String objectId;
}

abstract interface class MicrosoftPhotoSession {
  String get tenantId;
  String get objectId;
  Future<String> accessToken();
  void close();
}

class MicrosoftPhotoFailure implements Exception {
  const MicrosoftPhotoFailure();
  @override
  String toString() => 'Microsoft photo connection unavailable.';
}

enum MicrosoftPhotoStatus { unlinked, loaded, mismatch, cancelled, unavailable }

class MicrosoftPhotoConnection {
  MicrosoftPhotoConnection({required this.authenticate, required this.client});
  static const maxBytes = 1024 * 1024;
  final Future<MicrosoftPhotoSession> Function(Future<void> cancelled)
  authenticate;
  final http.Client client;
  int _generation = 0;
  Completer<void>? _cancel;
  MicrosoftPhotoSession? _session;
  String? _account;
  Uint8List? _bytes;

  Uint8List? bytesFor(String? account) =>
      account != null && account == _account && _bytes != null
      ? Uint8List.fromList(_bytes!)
      : null;

  void clear() {
    _generation++;
    if (_cancel != null && !_cancel!.isCompleted) _cancel!.complete();
    _cancel = null;
    _session?.close();
    _session = null;
    _account = null;
    _bytes = null;
  }

  Future<MicrosoftPhotoStatus> connect(MicrosoftPhotoIdentity? proof) async {
    clear();
    if (proof == null ||
        proof.bloomstepAccount.isEmpty ||
        proof.tenantId != MicrosoftPhotoIdentity.consumerTenant ||
        !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(proof.objectId)) {
      return MicrosoftPhotoStatus.unlinked;
    }
    final generation = _generation;
    final cancel = _cancel = Completer<void>();
    try {
      final session = await authenticate(cancel.future);
      if (generation != _generation) {
        session.close();
        return MicrosoftPhotoStatus.cancelled;
      }
      if (session.tenantId != proof.tenantId ||
          session.objectId != proof.objectId) {
        session.close();
        return MicrosoftPhotoStatus.mismatch;
      }
      _session = session;
      final token = await session.accessToken().timeout(
        const Duration(seconds: 30),
      );
      if (generation != _generation) return MicrosoftPhotoStatus.cancelled;
      if (token.isEmpty) throw const MicrosoftPhotoFailure();
      final abort = Completer<void>();
      final deadline = Timer(const Duration(seconds: 15), () {
        if (!abort.isCompleted) abort.complete();
      });
      unawaited(
        cancel.future.then((_) {
          if (!abort.isCompleted) abort.complete();
        }),
      );
      final request =
          http.AbortableRequest(
              'GET',
              Uri.parse('https://graph.microsoft.com/v1.0/me/photo/\$value'),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers['Authorization'] = 'Bearer $token';
      final Uint8List bytes;
      try {
        bytes = await (() async {
          final response = await client.send(request);
          if (response.statusCode != 200 ||
              !const ['image/jpeg', 'image/png'].contains(
                response.headers['content-type']?.split(';').first.trim(),
              ) ||
              (response.contentLength ?? 0) > maxBytes) {
            throw const MicrosoftPhotoFailure();
          }
          final builder = BytesBuilder(copy: false);
          await for (final chunk in response.stream) {
            if (builder.length + chunk.length > maxBytes) {
              throw const MicrosoftPhotoFailure();
            }
            builder.add(chunk);
          }
          if (builder.isEmpty) throw const MicrosoftPhotoFailure();
          return builder.takeBytes();
        })().timeout(const Duration(seconds: 15));
      } finally {
        deadline.cancel();
        if (!abort.isCompleted) abort.complete();
      }
      if (generation != _generation) return MicrosoftPhotoStatus.cancelled;
      _account = proof.bloomstepAccount;
      _bytes = bytes;
      return MicrosoftPhotoStatus.loaded;
    } on MicrosoftPhotoFailure {
      if (generation != _generation) return MicrosoftPhotoStatus.cancelled;
      clear();
      return MicrosoftPhotoStatus.unavailable;
    } on Exception {
      // Optional photos never expose token, callback or provider error details.
      if (generation != _generation) return MicrosoftPhotoStatus.cancelled;
      clear();
      return MicrosoftPhotoStatus.unavailable;
    }
  }
}
