import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';

void installWindowsStorageIdentity() {
  if (Platform.isWindows) {
    PathProviderPlatform.instance = BloomstepWindowsPaths();
  }
}

class BloomstepWindowsPaths extends PathProviderWindows {
  BloomstepWindowsPaths({this.knownFolder});

  // The package's non-FFI export omits folder constants. These are the Windows
  // SDK FOLDERID_RoamingAppData and FOLDERID_LocalAppData, not environment paths.
  static const roamingAppData = '{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}';
  static const localAppData = '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}';
  final Future<String?> Function(String folder)? knownFolder;

  Future<String> _stableDirectory(String folder) async {
    final root = await (knownFolder?.call(folder) ?? getPath(folder));
    if (root == null || root.isEmpty || !p.isAbsolute(root)) {
      throw StateError(
        'Bloomstep could not resolve its Windows data directory.',
      );
    }
    // Both garden storage and secure-storage v4 use this path. Branding must
    // never change the existing on-disk namespace or split the instance lock.
    final directory = Directory(p.join(root, 'com.bloomstep', 'bloomstep'));
    await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<String?> getApplicationSupportPath() =>
      _stableDirectory(roamingAppData);

  @override
  Future<String?> getApplicationCachePath() => _stableDirectory(localAppData);
}
