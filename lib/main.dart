import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/bloomstep_app.dart';
import 'services/single_instance.dart';
import 'services/invitation_intent.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  InvitationInbox? invitations;
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
  runApp(BloomstepApp(invitationInbox: invitations));
}
