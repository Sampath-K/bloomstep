import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';

void installWindowsStorageIdentity() {
  if (Platform.isWindows) {
    PathProviderPlatform.instance = BudlarkWindowsPaths();
  }
}

class BudlarkWindowsPaths extends PathProviderWindows {
  BudlarkWindowsPaths({this.knownFolder});

  // The package's non-FFI export omits folder constants. These are the Windows
  // SDK FOLDERID_LocalAppData, not an environment path.
  static const localAppData = '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}';
  final Future<String?> Function(String folder)? knownFolder;

  Future<String> _stableDirectory(String folder) async {
    final root = await (knownFolder?.call(folder) ?? getPath(folder));
    if (root == null || root.isEmpty || !p.isAbsolute(root)) {
      throw StateError(
        'Budlark could not resolve its Windows data directory.',
      );
    }
    // Garden storage, credentials and the instance lock share one namespace.
    final directory = Directory(p.join(root, 'Budlark'));
    await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<String?> getApplicationSupportPath() => _stableDirectory(localAppData);

  @override
  Future<String?> getApplicationCachePath() => _stableDirectory(localAppData);
}
