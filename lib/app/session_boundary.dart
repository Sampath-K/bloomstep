import 'dart:async';

import 'package:flutter/material.dart';

class SessionBoundary extends StatefulWidget {
  const SessionBoundary({
    super.key,
    required this.expiresAt,
    required this.isValid,
    required this.onExpired,
    this.onCheckpoint,
    required this.child,
  });
  final DateTime expiresAt;
  final bool Function() isValid;
  final Future<void> Function(String? reason) onExpired;
  final Future<void> Function()? onCheckpoint;
  final Widget child;

  @override
  State<SessionBoundary> createState() => _SessionBoundaryState();
}

class _SessionBoundaryState extends State<SessionBoundary>
    with WidgetsBindingObserver {
  Timer? _deadline;
  Timer? _clockCheck;
  bool _expired = false;
  bool _checkpointing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final remaining = widget.expiresAt.toUtc().difference(
      DateTime.now().toUtc(),
    );
    _deadline = Timer(remaining.isNegative ? Duration.zero : remaining, _check);
    _clockCheck = Timer.periodic(const Duration(minutes: 1), (_) => _check());
    _check();
  }

  void _check() {
    if (_expired) return;
    if (widget.isValid()) {
      if (!_checkpointing && widget.onCheckpoint != null) {
        unawaited(_checkpoint());
      }

      return;
    }
    _reject();
  }

  @override
  void didUpdateWidget(SessionBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    _check();
  }

  Future<void> _checkpoint() async {
    _checkpointing = true;
    try {
      await widget.onCheckpoint!();
    } catch (error) {
      if (mounted && !_expired) {
        _error = 'The session clock could not be saved: $error';
        _reject();
      }
    } finally {
      _checkpointing = false;
    }
  }

  void _reject() {
    _expired = true;
    _deadline?.cancel();
    _clockCheck?.cancel();
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_finish());
    });
  }

  Future<void> _finish() async {
    try {
      await widget.onExpired(_error);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Authentication cleanup failed: $error');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _clockCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _expired
      ? Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: SelectableText(
                'Please sign in again. Your offline session has ended. Your saved garden was not deleted.'
                '${_error == null ? '' : '\n\n$_error'}',
              ),
            ),
          ),
        )
      : widget.child;
}
