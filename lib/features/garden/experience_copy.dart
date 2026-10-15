import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/experience_experiments.dart';

typedef ExperienceCopyBuilder = Widget Function(
  BuildContext context,
  String copy,
);

/// Text-only variants; the caller retains all semantics, actions and layout.
class ExperienceCopy extends StatefulWidget {
  const ExperienceCopy({
    super.key,
    required this.experiments,
    required this.surface,
    required this.builder,
    this.onAssignment,
  });
  final ExperienceResolver experiments;
  final ExperienceSurface surface;
  final ExperienceCopyBuilder builder;
  final ValueChanged<ExperienceAssignment?>? onAssignment;
  @override
  State<ExperienceCopy> createState() => _ExperienceCopyState();
}

class _ExperienceCopyState extends State<ExperienceCopy> {
  late ExperienceAssignment _assignment;
  int _generation = 0;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    _assignment = ExperienceAssignment.control(widget.surface);
    widget.experiments.changes.addListener(_scopeChanged);
    _resolve();
  }

  @override
  void didUpdateWidget(ExperienceCopy oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.experiments != widget.experiments ||
        oldWidget.surface != widget.surface) {
      oldWidget.experiments.changes.removeListener(_scopeChanged);
      widget.experiments.changes.addListener(_scopeChanged);
      _assignment = ExperienceAssignment.control(widget.surface);
      _resolve();
    }
  }

  void _scopeChanged() {
    if (!mounted) return;
    setState(() => _assignment = ExperienceAssignment.control(widget.surface));
    _resolve();
  }

  void _report(Object error, StackTrace stack) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'experience experiments',
      context: ErrorDescription(
        'while recording an optional experience observation',
      ),
    ),
  );
  Future<void> _resolve() async {
    final generation = ++_generation;
    _expiry?.cancel();
    widget.onAssignment?.call(null);
    try {
      await widget.experiments.followup();
      final assignment = await widget.experiments.resolve(widget.surface);
      if (!mounted || generation != _generation) return;
      setState(() => _assignment = assignment);
      if (!assignment.active) return;
      _expiry = Timer(widget.experiments.remainingEnrollment, _scopeChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted ||
            generation != _generation ||
            ModalRoute.of(context)?.isCurrent == false ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed ||
            !TickerMode.valuesOf(context).enabled) {
          if (mounted && generation == _generation) {
            setState(
              () => _assignment = ExperienceAssignment.control(widget.surface),
            );
          }
          return;
        }
        var hidden = false;
        context.visitAncestorElements((element) {
          if (element.widget case Offstage(offstage: true)) hidden = true;
          return !hidden;
        });
        final box = context.findRenderObject();
        if (hidden ||
            box is! RenderBox ||
            !box.hasSize ||
            !(box.localToGlobal(Offset.zero) & box.size).overlaps(
              Offset.zero & MediaQuery.sizeOf(context),
            )) {
          setState(
            () => _assignment = ExperienceAssignment.control(widget.surface),
          );
          return;
        }
        try {
          final recorded = await widget.experiments.rendered(assignment);
          if (!mounted || generation != _generation) return;
          if (recorded) {
            widget.onAssignment?.call(assignment);
          } else {
            setState(
              () => _assignment = ExperienceAssignment.control(widget.surface),
            );
          }
        } catch (error, stack) {
          if (mounted) {
            setState(
              () => _assignment = ExperienceAssignment.control(widget.surface),
            );
          }
          _report(error, stack);
        }
      });
    } catch (error, stack) {
      if (mounted && generation == _generation) {
        setState(
          () => _assignment = ExperienceAssignment.control(widget.surface),
        );
      }
      _report(error, stack);
    }
  }

  @override
  void dispose() {
    _generation++;
    _expiry?.cancel();
    widget.experiments.changes.removeListener(_scopeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _assignment.copy);
}
