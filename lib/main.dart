import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/bloomstep_app.dart';
import 'services/single_instance.dart';
import 'services/invitation_intent.dart';
import 'services/installer_measurement.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  InvitationInbox? invitations;
  InstallerMeasurement? measurement;
  String? measurementWarning;
  if (Platform.isWindows) {
    try {
      final directory = await getApplicationSupportDirectory();
      invitations = InvitationInbox(p.join(directory.path, 'invitations'));
      InvitationIntent? invitation;
      if (arguments.isNotEmpty) {
        if (arguments.length != 1) {
          throw const FormatException(
            'Only one invitation may be opened at a time.',
          );
        }
        invitation = InvitationIntent.parseNative(Uri.parse(arguments.single));
      }
      final instance = SingleInstance(
        p.join(directory.path, 'instance'),
        () async {
          await windowManager.ensureInitialized();
          await windowManager.show();
          await windowManager.focus();
        },
        (message) => debugPrint(message),
        onInvitation: invitations.save,
      );
      if (!await instance.start(invitation: invitation)) exit(0);
    } catch (_) {
      runApp(
        const MaterialApp(
          title: 'Bloomstep',
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: SelectableText(
                  'Bloomstep could not safely process this invitation or open its app window. Use a valid Bloomstep link, or close an existing Bloomstep window and retry. No new garden or session was opened.',
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }
  }
  if (Platform.isWindows) {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) {
      measurementWarning = 'Optional installer measurement path is unavailable. No local observations collected; sign-in still works.';
    } else {
      measurement = InstallerMeasurement(
        p.join(local, 'Bloomstep', 'measurement'),
      );
      try {
        final marker = File(
          p.join(
            p.dirname(Platform.resolvedExecutable),
            'measurement-owner.txt',
          ),
        );
        String? owner;
        if (await marker.exists()) {
          if (await marker.length() != 36) {
            throw const FormatException(
              'Optional measurement ownership marker is invalid.',
            );
          }
          owner = await marker.readAsString();
          if (!RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ).hasMatch(owner)) {
            throw const FormatException(
              'Optional measurement ownership marker is invalid.',
            );
          }
        }
        measurement = InstallerMeasurement(
          p.join(local, 'Bloomstep', 'measurement'),
          ownerId: owner,
        );
        await measurement.observe('first_launch');
      } catch (_) {
        measurementWarning = 'Optional installer receipt is invalid or could not be updated. No server data was sent; sign-in still works. Clear the optional receipt to stop observation.';
      }
    }
  }
  runApp(
    BloomstepApp(
      invitationInbox: invitations,
      measurement: measurement,
      measurementWarning: measurementWarning,
    ),
  );
}
