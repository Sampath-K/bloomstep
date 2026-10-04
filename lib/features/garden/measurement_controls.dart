import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/garden_store.dart';
import '../../core/measurement_receipt.dart';
import '../../services/installer_measurement.dart';

class MeasurementControls extends StatefulWidget {
  const MeasurementControls({
    super.key,
    required this.store,
    required this.analytics,
    this.installer,
    this.pickReceipt,
  });
  final GardenStore store;
  final bool analytics;
  final InstallerMeasurement? installer;
  final Future<String?> Function()? pickReceipt;
  @override
  State<MeasurementControls> createState() => _MeasurementControlsState();
}

class _MeasurementControlsState extends State<MeasurementControls> {
  late final String account = widget.store.account;
  late final int generation = widget.store.syncGeneration;
  bool busy = false;
  String? status;

  Future<void> _run(Future<String> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      widget.store.requireSyncSession(account, generation);
      final result = await action();
      if (mounted) setState(() => status = result);
    } catch (error) {
      if (mounted) setState(() => status = 'Receipt action failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _pick() async {
    if (widget.pickReceipt != null) return widget.pickReceipt!();
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Measurement receipt', extensions: ['json']),
      ],
    );
    if (file == null) return null;
    if (await file.length() > MeasurementReceipt.maxBytes) {
      throw const FormatException('Receipt exceeds the 16 KiB limit.');
    }
    return file.readAsString();
  }

  Future<String> _link(MeasurementReceipt receipt) async {
    if (!mounted) {
      throw StateError('Receipt settings were closed. Nothing linked.');
    }
    widget.store.requireSyncSession(account, generation);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Link observations to this account?'),
        content: Text(
          '${receipt.events.length} ${receipt.source} observations from '
          '${receipt.events.first.at.toIso8601String()} through '
          '${receipt.events.last.at.toIso8601String()}.\n\n'
          'This explicitly links these historical events to your currently signed-in '
          'account. They sync privately under your product-event consent. '
          'Original times and IDs are preserved. This is not automatic attribution '
          'or proof that someone else used the download. Import only your own receipt.\n\n'
          'The source receipt stays local; clear it and any exported copies separately. '
          'Turning off app product events purges linked account events.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Link to this account'),
          ),
        ],
      ),
    );
    if (accepted != true) return 'Nothing linked.';
    if (!mounted) {
      throw StateError('Receipt settings were closed. Nothing linked.');
    }
    widget.store.requireSyncSession(account, generation);
    final count = await widget.store.importMeasurementReceipt(receipt);
    return count == 0
        ? 'Already linked. No duplicate observations added.'
        : '$count observations linked with original times. Queued for consented account sync; no live server success inferred.';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const ListTile(
        title: Text('Optional acquisition/install receipts'),
        subtitle: Text(
          'Separate, explicit account linking. Browser/installer consent must precede '
          'observations; receipts expire after seven days. No private text or invite codes. '
          'A self-selected sample, not complete funnel measurement.',
        ),
      ),
      ListTile(
        title: const Text('Link my exported website receipt'),
        subtitle: Text(
          widget.analytics
              ? 'Requires confirmation; choose only a measurement JSON receipt, not an account export.'
              : 'Enable account product-event consent first.',
        ),
        enabled: widget.analytics && !busy,
        onTap: !widget.analytics || busy
            ? null
            : () => _run(() async {
                final text = await _pick();
                if (text == null) return 'No receipt selected. Nothing linked.';
                final receipt = MeasurementReceipt.parse(text);
                if (receipt.source != 'website') {
                  throw const FormatException(
                    'Select a website measurement receipt.',
                  );
                }
                return _link(receipt);
              }),
      ),
      if (widget.installer != null) ...[
        ListTile(
          title: const Text('Link my pending installer receipt'),
          enabled: widget.analytics && !busy,
          onTap: !widget.analytics || busy
              ? null
              : () => _run(() async {
                  final receipt = await widget.installer!.read();
                  if (receipt == null) {
                    return 'No current installer receipt. No installation history was manufactured.';
                  }
                  return _link(receipt);
                }),
        ),
        ListTile(
          title: const Text('Clear installer receipt / stop local observation'),
          subtitle: const Text(
            'Does not delete an exported browser copy or already-linked account events.',
          ),
          enabled: !busy,
          onTap: busy
              ? null
              : () => _run(() async {
                  await widget.installer!.clear();
                  return 'Local installer receipt removed. No further launch/sign-in observations from that receipt.';
                }),
        ),
      ],
      if (busy) const LinearProgressIndicator(),
      if (status != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(status!, semanticsLabel: status),
        ),
    ],
  );
}
