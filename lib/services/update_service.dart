import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

class UpdateInfo {
  const UpdateInfo(this.version, this.releasePage, this.prerelease);
  final String version;
  final Uri releasePage;
  final bool prerelease;
}

class UpdateService {
  UpdateService({this.client});
  final http.Client? client;
  static const bundledVersion = String.fromEnvironment(
    'BUDLARK_RELEASE_VERSION',
    defaultValue: '0.1.0-preview',
  );
  // The immutable repository ID survives product/repository display-name changes.
  static const _repositoryId = 1404357574;
  static final _repository = Uri.https(
    'api.github.com',
    '/repositories/$_repositoryId',
  );
  static final _endpoint = Uri.https(
    'api.github.com',
    '/repositories/$_repositoryId/releases',
    {'per_page': '20'},
  );

  Future<UpdateInfo?> check({String currentVersion = bundledVersion}) async {
    final current = Version.parse(currentVersion);
    final requestClient = client ?? http.Client();
    try {
      final metadata = await requestClient
          .get(_repository, headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 20));
      if (metadata.statusCode != 200) {
        throw StateError(
          'Update source unavailable (HTTP ${metadata.statusCode}). No installer was downloaded.',
        );
      }
      final repository = jsonDecode(metadata.body);
      final home = repository is Map && repository['html_url'] is String
          ? Uri.tryParse(repository['html_url'] as String)
          : null;
      if (repository is! Map ||
          repository['id'] != _repositoryId ||
          home == null ||
          home.scheme != 'https' ||
          home.host != 'github.com' ||
          home.hasPort ||
          home.userInfo.isNotEmpty ||
          home.hasQuery ||
          home.hasFragment ||
          !RegExp(r'^/Sampath-K/[A-Za-z0-9_.-]+$').hasMatch(home.path)) {
        throw const FormatException('The update repository could not be verified.');
      }
      final response = await requestClient
          .get(_endpoint, headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError(
          'Update check failed (HTTP ${response.statusCode}). No installer was downloaded.',
        );
      }
      final releases = jsonDecode(response.body);
      if (releases is! List) {
        throw const FormatException('Invalid release response.');
      }
      Version? best;
      UpdateInfo? info;
      for (final raw in releases) {
        if (raw is! Map ||
            raw['draft'] is! bool ||
            raw['prerelease'] is! bool ||
            raw['tag_name'] is! String ||
            raw['html_url'] is! String) {
          throw const FormatException('Incomplete published release metadata.');
        }
        if (raw['draft'] == true) continue;
        final tag = raw['tag_name'] as String;
        if (!tag.startsWith('v')) {
          throw const FormatException('Unexpected release tag.');
        }
        final version = Version.parse(tag.substring(1));
        final uri = Uri.parse(raw['html_url'] as String);
        if (uri.scheme != 'https' ||
            uri.host != 'github.com' ||
            uri.hasPort ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment ||
            uri.path != '${home.path}/releases/tag/$tag') {
          throw const FormatException(
            'Release link is not the approved Budlark repository.',
          );
        }
        final preview = raw['prerelease'] == true || version.isPreRelease;
        if (preview && !current.isPreRelease) continue;
        if (version > current && (best == null || version > best)) {
          best = version;
          info = UpdateInfo(version.toString(), uri, preview);
        }
      }
      return info;
    } finally {
      if (client == null) requestClient.close();
    }
  }
}
