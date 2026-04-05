import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/game_models.dart';
import 'lan_party_service_base.dart';

LanPartyService createLanPartyService() => _IoLanPartyService();

class _IoLanPartyService implements LanPartyService {
  static const int _presencePort = 45454;
  static const Duration _peerLifetime = Duration(seconds: 18);

  RawDatagramSocket? _presenceSocket;
  HttpServer? _hostServer;
  EggHuntGame? _hostedGame;
  void Function(EggHuntGame game)? _onGameChanged;
  void Function()? _onPeersChanged;
  Timer? _cleanupTimer;
  String? _deviceId;
  String? _deviceName;
  final Map<String, DiscoveredPeer> _knownPeers = {};

  @override
  bool get isSupported => true;

  @override
  List<DiscoveredPeer> get peers {
    final values = _knownPeers.values.toList();
    values.sort((left, right) => left.deviceName.compareTo(right.deviceName));
    return values;
  }

  @override
  Future<void> initialize({
    required String deviceId,
    required String deviceName,
    required void Function() onPeersChanged,
  }) async {
    _deviceId = deviceId;
    _deviceName = deviceName;
    _onPeersChanged = onPeersChanged;

    _presenceSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _presencePort,
      reuseAddress: true,
      reusePort: true,
    );
    _presenceSocket!.broadcastEnabled = true;
    _presenceSocket!.listen(_handlePresenceEvent);
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _prunePeers(),
    );
  }

  @override
  Future<List<DiscoveredPeer>> discover() async {
    final socket = _presenceSocket;
    if (socket == null) {
      return peers;
    }

    final payload = utf8.encode(
      jsonEncode({
        'type': 'discover',
        'deviceId': _deviceId,
        'deviceName': _deviceName,
      }),
    );
    socket.send(payload, InternetAddress('255.255.255.255'), _presencePort);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _prunePeers();
    return peers;
  }

  @override
  Future<void> startHosting(
    EggHuntGame game, {
    required void Function(EggHuntGame game) onGameChanged,
  }) async {
    await stopHosting();
    _hostedGame = game;
    _onGameChanged = onGameChanged;
    _hostServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    unawaited(_hostServer!.forEach(_handleRequest));
    _broadcastStatus();
  }

  @override
  Future<void> updateHostedGame(EggHuntGame game) async {
    _hostedGame = game;
    _broadcastStatus();
  }

  @override
  Future<void> stopHosting() async {
    await _hostServer?.close(force: true);
    _hostServer = null;
    _hostedGame = null;
    _onGameChanged = null;
    _broadcastStatus();
  }

  @override
  Future<EggHuntGame> fetchGame(DiscoveredPeer host) async {
    return _requestGame(host: host, method: 'GET', path: '/snapshot');
  }

  @override
  Future<EggHuntGame> markEggFound({
    required DiscoveredPeer host,
    required String playerId,
    required String eggId,
  }) async {
    return _requestGame(
      host: host,
      method: 'POST',
      path: '/mark-found',
      body: {'playerId': playerId, 'eggId': eggId},
    );
  }

  Future<EggHuntGame> _requestGame({
    required DiscoveredPeer host,
    required String method,
    required String path,
    JsonMap? body,
  }) async {
    final port = host.hostPort;
    if (port == null) {
      throw const LanPartyException("Cette partie n'est plus joignable.");
    }

    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://${host.address}:$port$path'),
      );
      request.headers.contentType = ContentType.json;
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final rawResponse = await utf8.decoder.bind(response).join();
      final decoded = rawResponse.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(rawResponse);
      final json = decoded is JsonMap ? decoded : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = json['error'] is String
            ? json['error'] as String
            : 'Erreur reseau locale.';
        throw LanPartyException(message);
      }

      return EggHuntGame.fromJson(json);
    } on SocketException {
      throw const LanPartyException(
        "Impossible de joindre l'hote. Verifie que les appareils sont sur le meme Wi-Fi.",
      );
    } finally {
      client.close(force: true);
    }
  }

  void _handlePresenceEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }

    final datagram = _presenceSocket?.receive();
    if (datagram == null) {
      return;
    }

    final message = utf8.decode(datagram.data, allowMalformed: true);
    final decoded = jsonDecodeSafe(message);
    if (decoded == null) {
      return;
    }

    final type = decoded['type'];
    final senderId = decoded['deviceId'];
    if (senderId is! String || senderId == _deviceId) {
      return;
    }

    if (type == 'discover') {
      _upsertPeer(
        deviceId: senderId,
        deviceName: decoded['deviceName'] is String
            ? decoded['deviceName'] as String
            : 'Appareil voisin',
        address: datagram.address.address,
        hasActiveGame: false,
      );
      _sendStatusTo(datagram.address);
      return;
    }

    if (type == 'status') {
      _upsertPeer(
        deviceId: senderId,
        deviceName: decoded['deviceName'] is String
            ? decoded['deviceName'] as String
            : 'Appareil voisin',
        address: datagram.address.address,
        hasActiveGame: decoded['hasActiveGame'] == true,
        hostPort: decoded['hostPort'] is int
            ? decoded['hostPort'] as int
            : null,
        gameId: decoded['gameId'] is String
            ? decoded['gameId'] as String
            : null,
        gameTitle: decoded['gameTitle'] is String
            ? decoded['gameTitle'] as String
            : null,
      );
    }
  }

  void _upsertPeer({
    required String deviceId,
    required String deviceName,
    required String address,
    required bool hasActiveGame,
    int? hostPort,
    String? gameId,
    String? gameTitle,
  }) {
    _knownPeers[deviceId] = DiscoveredPeer(
      deviceId: deviceId,
      deviceName: deviceName,
      address: address,
      hasActiveGame: hasActiveGame,
      lastSeen: DateTime.now(),
      hostPort: hostPort,
      gameId: gameId,
      gameTitle: gameTitle,
    );
    _onPeersChanged?.call();
  }

  void _prunePeers() {
    final now = DateTime.now();
    final expired = <String>[];
    for (final entry in _knownPeers.entries) {
      if (now.difference(entry.value.lastSeen) > _peerLifetime) {
        expired.add(entry.key);
      }
    }
    if (expired.isEmpty) {
      return;
    }
    for (final key in expired) {
      _knownPeers.remove(key);
    }
    _onPeersChanged?.call();
  }

  void _broadcastStatus() {
    _sendStatusTo(InternetAddress('255.255.255.255'));
  }

  void _sendStatusTo(InternetAddress target) {
    final socket = _presenceSocket;
    if (socket == null) {
      return;
    }

    final payload = utf8.encode(
      jsonEncode({
        'type': 'status',
        'deviceId': _deviceId,
        'deviceName': _deviceName,
        'hasActiveGame': _hostedGame != null && _hostServer != null,
        'hostPort': _hostServer?.port,
        'gameId': _hostedGame?.id,
        'gameTitle': _hostedGame?.title,
      }),
    );
    socket.send(payload, target, _presencePort);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (_hostedGame == null) {
        _writeError(
          request.response,
          HttpStatus.serviceUnavailable,
          'Aucune partie active.',
        );
        return;
      }

      switch ('${request.method} ${request.uri.path}') {
        case 'GET /snapshot':
          _writeGame(request.response, _hostedGame!);
          return;
        case 'POST /mark-found':
          final body = await _readJsonBody(request);
          final playerId = body['playerId'];
          final eggId = body['eggId'];
          if (playerId is! String || eggId is! String) {
            _writeError(
              request.response,
              HttpStatus.badRequest,
              'Requete incomplete.',
            );
            return;
          }
          final updated = _markEggFound(playerId: playerId, eggId: eggId);
          _hostedGame = updated;
          _onGameChanged?.call(updated);
          _writeGame(request.response, updated);
          return;
        default:
          _writeError(request.response, HttpStatus.notFound, 'Route inconnue.');
      }
    } catch (error) {
      _writeError(
        request.response,
        HttpStatus.internalServerError,
        error.toString(),
      );
    }
  }

  EggHuntGame _markEggFound({required String playerId, required String eggId}) {
    final game = _hostedGame;
    if (game == null) {
      throw const LanPartyException('La partie a ete fermee.');
    }

    final updatedEggs = <EggAssignment>[];
    var didUpdate = false;
    for (final egg in game.eggs) {
      if (egg.id == eggId && egg.playerId == playerId) {
        updatedEggs.add(egg.copyWith(foundAt: egg.foundAt ?? DateTime.now()));
        didUpdate = true;
      } else {
        updatedEggs.add(egg);
      }
    }

    if (!didUpdate) {
      throw const LanPartyException("Cet oeuf n'appartient pas a ce joueur.");
    }

    return game.copyWith(eggs: updatedEggs);
  }

  Future<JsonMap> _readJsonBody(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final decoded = jsonDecodeSafe(raw);
    if (decoded == null) {
      return <String, dynamic>{};
    }
    return decoded;
  }

  void _writeGame(HttpResponse response, EggHuntGame game) {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(game.toJson()));
    response.close();
  }

  void _writeError(HttpResponse response, int statusCode, String message) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({'error': message}));
    response.close();
  }

  @override
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    await stopHosting();
    _presenceSocket?.close();
    _presenceSocket = null;
    _knownPeers.clear();
  }
}

JsonMap? jsonDecodeSafe(String source) {
  try {
    final decoded = jsonDecode(source);
    if (decoded is JsonMap) {
      return decoded;
    }
  } catch (_) {
    return null;
  }
  return null;
}
