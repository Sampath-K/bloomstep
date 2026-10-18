import 'dart:io';

import 'package:budlark/services/windows_storage_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_windows/flutter_secure_storage_windows.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual Windows DPAPI v4 record survives branded upgrade without legacy migration', () async {
    final root = await Directory.systemTemp.createTemp('budlark-dpapi-test-');
    addTearDown(() => root.delete(recursive: true));
    final paths = PathProviderPlatform.instance;
    final secure = FlutterSecureStoragePlatform.instance;
    final targetPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      PathProviderPlatform.instance = paths;
      FlutterSecureStoragePlatform.instance = secure;
      debugDefaultTargetPlatformOverride = targetPlatform;
    });
    final legacy = p.join(root.path, 'Budlark');
    PathProviderPlatform.instance = _Preview3Paths(legacy);
    FlutterSecureStorageWindows.registerWith();
    const storage = FlutterSecureStorage(
      wOptions: WindowsOptions(useBackwardCompatibility: false),
    );
    await storage.write(
      key: 'synthetic-upgrade-record',
      value: 'Synthetic test fixture, not an account or token.',
    );
    final files = await Directory(legacy)
        .list()
        .where((entry) => entry is File)
        .toList();
    expect(files, hasLength(1));
    final before = await File(files.single.path).readAsBytes();
    PathProviderPlatform.instance = BudlarkWindowsPaths(
      knownFolder: (_) async => root.path,
    );
    FlutterSecureStorageWindows.registerWith();
    expect(
      await storage.read(key: 'synthetic-upgrade-record'),
      'Synthetic test fixture, not an account or token.',
    );
    expect(await File(files.single.path).readAsBytes(), before);
    expect(
      await Directory(p.join(root.path, 'Budlark contributors')).exists(),
      false,
    );
  }, skip: !Platform.isWindows);
  test(
    'branding cannot relocate garden, credential or instance storage',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'budlark-storage-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final legacy = Directory(p.join(root.path, 'Budlark'));
      await legacy.create(recursive: true);
      final saved = File(p.join(legacy.path, 'synthetic-record'));
      await saved.writeAsString('synthetic, not credentials');
      final original = PathProviderPlatform.instance;
      addTearDown(() => PathProviderPlatform.instance = original);
      PathProviderPlatform.instance = BudlarkWindowsPaths(
        knownFolder: (folder) async {
          expect(folder, '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}');
          return root.path;
        },
      );
      final actual = await getApplicationSupportDirectory();
      expect(actual.path, legacy.path);
      expect(await saved.readAsString(), 'synthetic, not credentials');
      expect(await getApplicationSupportDirectory(), isA<Directory>());
    },
  );

  test('cache shares the local machine product namespace', () async {
    final root = await Directory.systemTemp.createTemp('budlark-cache-test-');
    addTearDown(() => root.delete(recursive: true));
    final provider = BudlarkWindowsPaths(
      knownFolder: (folder) async {
        expect(folder, '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}');
        return root.path;
      },
    );
    expect(
      await provider.getApplicationCachePath(),
      p.join(root.path, 'Budlark'),
    );
  });

  test(
    'missing Windows known folder is explicit, not temporary storage',
    () async {
      final provider = BudlarkWindowsPaths(knownFolder: (_) async => null);
      await expectLater(provider.getApplicationSupportPath(), throwsStateError);
    },
  );
}

class _Preview3Paths extends PathProviderPlatform {
  _Preview3Paths(this.support);
  final String support;

  @override
  Future<String?> getApplicationSupportPath() async => support;
}
