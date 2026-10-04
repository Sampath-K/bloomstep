import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../core/garden_store.dart';
import 'identity.dart';

const invitationChannels = {'link', 'email', 'qr', 'native'};
const invitationCategories = {
  'calm',
  'focus',
  'health',
  'learning',
  'connection',
};

void validateRecipeCard(Map<String, dynamic> card) {
  if (card.keys.toSet().difference({
        'explicitChoice',
        'templateCategory',
        'aspiration',
        'anchor',
        'behavior',
        'celebration',
        'species',
      }).isNotEmpty ||
      card.length != 7 ||
      card['explicitChoice'] != true ||
      !invitationCategories.contains(card['templateCategory']) ||
      !{'Cosmos', 'Sunflower', 'Fern'}.contains(card['species'])) {
    throw const FormatException('Approve the complete recipe card explicitly.');
  }
  for (final key in ['aspiration', 'anchor', 'behavior', 'celebration']) {
    final value = card[key];
    if (value is! String ||
        value.trim().isEmpty ||
        value != value.trim() ||
        value.length > 200) {
      throw const FormatException(
        'Shared recipe fields must contain 1–200 characters.',
      );
    }
  }
}

class InvitationReceipt {
  InvitationReceipt(this.json, {this.cached = false});
  final Map<String, dynamic> json;
  final bool cached;
  String get id => json['invitationId'];
  String get channel => json['channel'];
  String get token => json['token'];
  DateTime get expiresAt => DateTime.parse(json['expiresAt']);
  Map<String, dynamic>? get recipeCard =>
      json['recipeCard'] as Map<String, dynamic>?;
}

class InvitationStatus {
  InvitationStatus(this.json, this.fetchedAt, {this.cached = false});
  final Map<String, dynamic> json;
  final DateTime fetchedAt;
  final bool cached;
  List<dynamic> get rewards => json['rewards'];
  List<dynamic> get invitations => json['invitations'];
}

class InvitationService {
  InvitationService(
    this.store, {
    this.identity,
    this.client,
    Future<String> Function()? tokenProvider,
    this.origin = IdentityService.apiOrigin,
    DateTime Function()? clock,
  }) : tokenProvider = tokenProvider ?? (() => identity!.accessToken()),
       clock = clock ?? DateTime.now;
  final GardenStore store;
  final IdentityService? identity;
  final http.Client? client;
  final Future<String> Function() tokenProvider;
  final String origin;
  final DateTime Function() clock;
  static const _uuid = Uuid();
  static final _queues = Expando<Future<void>>();

  static bool _keys(Map value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);
  static String _canonical(Object? value) {
    Object? ordered(Object? item) {
      if (item is Map) {
        final keys = item.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: ordered(item[key])};
      }
      if (item is List) return item.map(ordered).toList();
      return item;
    }

    return jsonEncode(ordered(value));
  }

  static bool _id(Object? value) =>
      value is String &&
      RegExp(
        r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[1-8][a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$',
      ).hasMatch(value);
  static DateTime _stamp(Object? value) {
    if (value is! String ||
        !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$')
            .hasMatch(value)) {
      throw const FormatException('Invalid invitation timestamp.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
      throw const FormatException('Invalid invitation date.');
    }
    return parsed;
  }

  static void validateToken(String token) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const FormatException('Invalid invitation code.');
    }
    final bytes = base64Url.decode('$token=');
    if (bytes.length != 32 ||
        base64Url.encode(bytes).replaceAll('=', '') != token) {
      throw const FormatException('Noncanonical invitation code.');
    }
  }

  Uri _uri(String path, {bool export = false}) {
    final uri = Uri.tryParse(origin);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443) ||
        !['', '/', '/api', '/api/'].contains(uri.path)) {
      throw StateError(
        'Connected invitations require the approved API origin.',
      );
    }
    return uri.replace(
      path: path,
      queryParameters: export ? {'export': 'true'} : null,
    );
  }

  Uri webUri(InvitationReceipt receipt) => _uri('/').replace(
    queryParameters: {'invite': receipt.token, 'channel': receipt.channel},
  );

  Future<T> _serial<T>(Future<T> Function(String, int) operation) {
    final account = store.account, generation = store.syncGeneration;
    final next = (_queues[store] ?? Future<void>.value()).then((_) {
      store.requireSyncSession(account, generation);
      return operation(account, generation);
    });
    _queues[store] = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<Map<String, dynamic>> _state() async {
    final raw = await store.setting('invitationState');
    if (raw == null) {
      return {
        'version': 1,
        'creations': [],
        'redemption': null,
        'status': null,
      };
    }
    if (raw.length > 65536) {
      throw const FormatException('Invitation cache is damaged.');
    }
    final state = jsonDecode(raw);
    if (state is! Map<String, dynamic> ||
        !_keys(state, {'version', 'creations', 'redemption', 'status'}) ||
        state['version'] != 1 ||
        state['creations'] is! List ||
        state['creations'].length > 10) {
      throw const FormatException('Invitation cache is damaged.');
    }
    for (final row in state['creations']) {
      if (row is! Map ||
          !_keys(row, {'payload', 'receipt'}) ||
          row['payload'] is! Map) {
        throw const FormatException('Invalid cached creation.');
      }
      final payload = row['payload'] as Map;
      if (!_keys(payload, {
            'requestId',
            'channel',
            if (payload.containsKey('recipeCard')) 'recipeCard',
          }) ||
          !_id(payload['requestId']) ||
          !invitationChannels.contains(payload['channel'])) {
        throw const FormatException('Invalid cached creation payload.');
      }
      if (payload['recipeCard'] != null) {
        validateRecipeCard(Map<String, dynamic>.from(payload['recipeCard']));
      }
      if (row['receipt'] != null) {
        final receipt = Map<String, dynamic>.from(row['receipt']);
        _receipt(receipt, creation: true);
        if (receipt['invitationId'] != payload['requestId'] ||
            receipt['channel'] != payload['channel'] ||
            _canonical(receipt['recipeCard']) !=
                _canonical(payload['recipeCard'])) {
          throw const FormatException('Cached creation identity changed.');
        }
      }
    }
    final redemption = state['redemption'];
    if (redemption != null) {
      if (redemption is! Map ||
          !_keys(redemption, {'payload', 'receipt'}) ||
          redemption['payload'] is! Map ||
          !_keys(redemption['payload'], {'requestId', 'token'}) ||
          !_id(redemption['payload']['requestId']) ||
          redemption['payload']['token'] is! String) {
        throw const FormatException('Invalid cached redemption.');
      }
      validateToken(redemption['payload']['token']);
      if (redemption['receipt'] != null) {
        _receipt(
          Map<String, dynamic>.from(redemption['receipt']),
          creation: false,
        );
      }
    }
    return state;
  }

  Future<void> _save(
    Map<String, dynamic> state,
    String account,
    int generation, {
    String? acceptedChannel,
  }) {
    store.requireSyncSession(account, generation);
    return store.saveInvitationState(
      jsonEncode(state),
      acceptedChannel: acceptedChannel,
    );
  }

  Future<Map<String, dynamic>> _request(
    String path,
    String account,
    int generation, {
    Map<String, dynamic>? body,
    bool export = false,
  }) async {
    if (identity != null && identity!.account != account) {
      throw StateError('Sign in to the garden that owns this invitation.');
    }
    final token = await tokenProvider();
    store.requireSyncSession(account, generation);
    final transport = client ?? http.Client();
    try {
      final request =
          http.Request(
              body == null ? 'GET' : 'POST',
              _uri(path, export: export),
            )
            ..followRedirects = false
            ..headers['X-Bloomstep-Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      Future<Map<String, dynamic>> download() async {
        final response = await transport.send(request);
        if (response.statusCode != 200) {
          throw StateError(
            'Connected invitation request failed (HTTP ${response.statusCode}). Retry uses the same request; no invitation or reward was invented.',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 65536) {
            throw const FormatException('Invitation response is too large.');
          }
          bytes.addAll(chunk);
        }
        final value = jsonDecode(utf8.decode(bytes));
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid invitation response.');
        }
        return value;
      }

      final value = await download().timeout(const Duration(seconds: 15));
      store.requireSyncSession(account, generation);
      return value;
    } finally {
      if (client == null) transport.close();
    }
  }

  void _receipt(Map<String, dynamic> value, {required bool creation}) {
    if (!_keys(
          value,
          creation
              ? {'invitationId', 'token', 'channel', 'expiresAt', 'recipeCard'}
              : {
                  'invitationId',
                  'channel',
                  'acceptedAt',
                  'expiresAt',
                  'recipeCard',
                  'status',
                },
        ) ||
        !_id(value['invitationId']) ||
        !invitationChannels.contains(value['channel'])) {
      throw const FormatException('Invalid server invitation receipt.');
    }
    _stamp(value['expiresAt']);
    if (creation) {
      if (value['token'] is! String) {
        throw const FormatException('Missing code.');
      }
      validateToken(value['token']);
    } else {
      _stamp(value['acceptedAt']);
      if (!{'accepted', 'rewarded'}.contains(value['status'])) {
        throw const FormatException('Invalid acceptance.');
      }
    }
    if (value['recipeCard'] != null) {
      if (value['recipeCard'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid card.');
      }
      validateRecipeCard(value['recipeCard']);
    }
  }

  Future<InvitationReceipt> create(
    String channel, {
    Map<String, dynamic>? recipeCard,
  }) {
    final snapshot = recipeCard == null
        ? null
        : (jsonDecode(jsonEncode(recipeCard)) as Map<String, dynamic>);
    return _create(channel, snapshot);
  }

  Future<InvitationReceipt> _create(
    String channel,
    Map<String, dynamic>? recipeCard,
  ) => _serial((account, generation) async {
    if (!invitationChannels.contains(channel)) {
      throw const FormatException('Invalid sharing channel.');
    }
    if (recipeCard != null) validateRecipeCard(recipeCard);
    final state = await _state();
    final creations = state['creations'] as List;
    Map<String, dynamic>? row;
    for (final raw in creations) {
      final candidate = Map<String, dynamic>.from(raw);
      final payload = candidate['payload'] as Map;
      if (payload['channel'] == channel &&
          _canonical(payload['recipeCard']) == _canonical(recipeCard)) {
        final receipt = candidate['receipt'];
        if (receipt == null) {
          row = candidate;
          break;
        }
        _receipt(Map<String, dynamic>.from(receipt), creation: true);
        if (clock().toUtc().isBefore(_stamp(receipt['expiresAt']))) {
          return InvitationReceipt(
            Map<String, dynamic>.from(receipt),
            cached: true,
          );
        }
      }
    }
    if (row == null) {
      if (creations.length >= 10) {
        throw StateError('This preview allows ten invitations per account.');
      }
      row = {
        'payload': {
          'requestId': _uuid.v4(),
          'channel': channel,
          'recipeCard': ?recipeCard,
        },
        'receipt': null,
      };
      creations.add(row);
      await _save(state, account, generation);
    } else {
      creations[creations.indexWhere(
            (r) => r['payload']['requestId'] == row!['payload']['requestId'],
          )] =
          row;
    }
    final response = await _request(
      '/api/invitations',
      account,
      generation,
      body: Map<String, dynamic>.from(row['payload']),
    );
    _receipt(response, creation: true);
    if (response['invitationId'] != row['payload']['requestId'] ||
        response['channel'] != channel ||
        _canonical(response['recipeCard']) != _canonical(recipeCard) ||
        !clock().toUtc().isBefore(_stamp(response['expiresAt'])) ||
        _stamp(
          response['expiresAt'],
        ).isAfter(clock().toUtc().add(const Duration(days: 7, minutes: 5)))) {
      throw const FormatException(
        'Server invitation does not match the requested snapshot.',
      );
    }
    row['receipt'] = response;
    await _save(state, account, generation);
    return InvitationReceipt(response);
  });

  Future<InvitationReceipt> redeem(String token) =>
      _serial((account, generation) async {
        validateToken(token);
        final state = await _state();
        var row = state['redemption'] as Map<String, dynamic>?;
        if (row != null && row['payload']['token'] != token) {
          throw StateError(
            'An acceptance is already pending or recorded. Retry the original invitation.',
          );
        }
        if (row == null) {
          row = {
            'payload': {'requestId': _uuid.v4(), 'token': token},
            'receipt': null,
          };
          state['redemption'] = row;
          await _save(state, account, generation);
        }
        final response = await _request(
          '/api/invitations/redeem',
          account,
          generation,
          body: Map<String, dynamic>.from(row['payload']),
        );
        _receipt(response, creation: false);
        if (_stamp(response['acceptedAt'])
                .isAfter(clock().toUtc().add(const Duration(minutes: 5))) ||
            !_stamp(response['expiresAt'])
                .isAfter(_stamp(response['acceptedAt'])) ||
            _stamp(response['expiresAt'])
                    .difference(_stamp(response['acceptedAt'])) >
                const Duration(days: 30)) {
          throw const FormatException('Acceptance has an invalid lifetime.');
        }
        if (row['receipt'] != null &&
            (row['receipt']['invitationId'] != response['invitationId'] ||
                row['receipt']['acceptedAt'] != response['acceptedAt'] ||
                row['receipt']['channel'] != response['channel'])) {
          throw const FormatException('Acceptance attribution changed.');
        }
        final first = row['receipt'] == null;
        row['receipt'] = response;
        await _save(
          state,
          account,
          generation,
          acceptedChannel: first ? response['channel'] : null,
        );
        return InvitationReceipt(response);
      });

  void _status(Map<String, dynamic> value, {bool export = false}) {
    if (!_keys(value, {
          'invitations',
          'rewards',
          'definition',
          if (export) 'sharedRecipes',
        }) ||
        value['definition'] is! String ||
        value['definition'].length > 2000 ||
        value['invitations'] is! List ||
        value['invitations'].length > 11 ||
        value['rewards'] is! List ||
        value['rewards'].length > 11) {
      throw const FormatException('Invalid private invitation status.');
    }
    for (final row in value['invitations']) {
      if (row is! Map ||
          !_keys(row, {
            'invitationId',
            'direction',
            'channel',
            'acceptedAt',
            'expiresAt',
            'status',
          }) ||
          !_id(row['invitationId']) ||
          !{'incoming', 'outgoing'}.contains(row['direction']) ||
          !invitationChannels.contains(row['channel']) ||
          !{
            'created',
            'accepted',
            'rewarded',
            'expired',
          }.contains(row['status'])) {
        throw const FormatException('Invalid invitation metadata.');
      }
      _stamp(row['expiresAt']);
      if (row['acceptedAt'] != null) _stamp(row['acceptedAt']);
    }
    for (final row in value['rewards']) {
      if (row is! Map ||
          !_keys(row, {'id', 'cosmetic', 'grantedAt'}) ||
          row['id'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['id']) ||
          row['cosmetic'] != 'rare_flower') {
        throw const FormatException('Invalid server cosmetic.');
      }
      _stamp(row['grantedAt']);
    }
    if (export) {
      if (value['sharedRecipes'] is! List ||
          value['sharedRecipes'].length > 10) {
        throw const FormatException('Invalid card export.');
      }
      for (final row in value['sharedRecipes']) {
        if (row is! Map ||
            !_keys(row, {'invitationId', 'expiresAt', 'recipeCard'}) ||
            !_id(row['invitationId'])) {
          throw const FormatException('Invalid card export.');
        }
        _stamp(row['expiresAt']);
        validateRecipeCard(Map<String, dynamic>.from(row['recipeCard']));
      }
    }
  }

  Future<InvitationStatus> refreshStatus({bool export = false}) =>
      _serial((account, generation) async {
        final response = await _request(
          '/api/invitations/status',
          account,
          generation,
          export: export,
        );
        _status(response, export: export);
        final state = await _state();
        final normal = {...response}..remove('sharedRecipes');
        state['status'] = {
          'response': normal,
          'fetchedAt': clock().toUtc().toIso8601String(),
        };
        await _save(state, account, generation);
        return InvitationStatus(response, clock().toUtc());
      });

  Future<InvitationStatus?> cachedStatus() async {
    final account = store.account, generation = store.syncGeneration;
    final state = await _state();
    store.requireSyncSession(account, generation);
    final status = state['status'];
    if (status == null) return null;
    final response = Map<String, dynamic>.from(status['response']);
    _status(response);
    final stamp = _stamp(status['fetchedAt']);
    if (stamp.isAfter(clock().toUtc().add(const Duration(minutes: 5))) ||
        clock().toUtc().difference(stamp) >= const Duration(days: 30)) {
      return null;
    }
    return InvitationStatus(response, stamp, cached: true);
  }

  Future<Map<String, dynamic>?> cachedAcceptedCard() async {
    final account = store.account, generation = store.syncGeneration;
    final state = await _state();
    store.requireSyncSession(account, generation);
    final receipt = state['redemption']?['receipt'];
    if (receipt == null) return null;
    _receipt(Map<String, dynamic>.from(receipt), creation: false);
    if (!clock().toUtc().isBefore(_stamp(receipt['expiresAt'])) ||
        clock().toUtc().difference(_stamp(receipt['acceptedAt'])) >=
            const Duration(days: 7)) {
      return null;
    }
    return receipt['recipeCard'] as Map<String, dynamic>?;
  }
}
