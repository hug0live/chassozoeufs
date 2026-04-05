import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'game_store.dart';
import 'models.dart';
import 'puzzle_catalog.dart';

class EggHuntServerApp {
  EggHuntServerApp({
    required this.store,
    required this.allowedOrigin,
    required this.publicDirectory,
  });

  final GameStore store;
  final String allowedOrigin;
  final String publicDirectory;

  Handler get handler {
    final router = Router()
      ..get('/health', _health)
      ..get('/api/catalog/hide-spots', _listHideSpots)
      ..get('/api/games', _listGames)
      ..get('/api/games/active', _activeGame)
      ..get('/api/games/<gameId>', _getGame)
      ..post('/api/games', _createGame)
      ..post('/api/games/<gameId>/join', _joinGame)
      ..post('/api/games/<gameId>/leave', _leaveGame)
      ..post('/api/games/<gameId>/eggs/<eggId>/found', _markEggFound)
      ..post('/api/games/<gameId>/close', _closeGame)
      ..get('/ws/games/<gameId>', _gameSocket);

    return Pipeline()
        .addMiddleware(_corsMiddleware())
        .addMiddleware(logRequests())
        .addHandler((request) async {
          final response = await router.call(request);
          if (response.statusCode != 404) {
            return response;
          }
          return _servePublic(request);
        });
  }

  Response _health(Request request) {
    return _jsonResponse({
      'status': 'ok',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Response _listHideSpots(Request request) {
    return _jsonResponse({
      'hideSpots': [for (final spot in kHideSpots) spot.toJson()],
    });
  }

  Response _listGames(Request request) {
    return _jsonResponse({
      'games': [for (final game in store.listGames()) game.toJson()],
    });
  }

  Response _activeGame(Request request) {
    return _jsonResponse({'game': store.activeGame?.toJson()});
  }

  Response _getGame(Request request, String gameId) {
    final game = store.gameById(gameId);
    if (game == null) {
      return _errorResponse(404, 'Partie introuvable.');
    }
    return _jsonResponse({'game': game.toJson()});
  }

  Future<Response> _createGame(Request request) async {
    try {
      final body = await _readJson(request);
      final title = _readString(body['title']);
      final hostName = _readString(body['hostName']);
      final players = _readStringList(body['players']);
      final eggDrafts = _readEggDrafts(body['eggs']);

      final game = await store.createGame(
        title: title,
        hostName: hostName,
        playerNames: players,
        eggDrafts: eggDrafts,
      );

      return _jsonResponse({'game': game.toJson()}, status: 201);
    } on GameStoreException catch (error) {
      return _errorResponse(400, error.message);
    } on FormatException catch (error) {
      return _errorResponse(400, error.message);
    }
  }

  Future<Response> _joinGame(Request request, String gameId) async {
    try {
      final body = await _readJson(request);
      final playerId = _readString(body['playerId']);
      final claimant = _readString(body['claimedBy']);
      if (playerId.isEmpty) {
        throw const FormatException('Le champ playerId est obligatoire.');
      }
      if (claimant.isEmpty) {
        throw const FormatException('Le champ claimedBy est obligatoire.');
      }

      final game = await store.joinPlayer(
        gameId: gameId,
        playerId: playerId,
        claimant: claimant,
      );

      return _jsonResponse({'game': game.toJson()});
    } on GameStoreException catch (error) {
      return _errorResponse(409, error.message);
    } on FormatException catch (error) {
      return _errorResponse(400, error.message);
    }
  }

  Future<Response> _leaveGame(Request request, String gameId) async {
    try {
      final body = await _readJson(request);
      final playerId = _readString(body['playerId']);
      final claimant = _readString(body['claimedBy']);
      if (playerId.isEmpty) {
        throw const FormatException('Le champ playerId est obligatoire.');
      }
      if (claimant.isEmpty) {
        throw const FormatException('Le champ claimedBy est obligatoire.');
      }

      final game = await store.releasePlayer(
        gameId: gameId,
        playerId: playerId,
        claimant: claimant,
      );

      return _jsonResponse({'game': game.toJson()});
    } on GameStoreException catch (error) {
      return _errorResponse(409, error.message);
    } on FormatException catch (error) {
      return _errorResponse(400, error.message);
    }
  }

  Future<Response> _markEggFound(
    Request request,
    String gameId,
    String eggId,
  ) async {
    try {
      final body = await _readJson(request);
      final playerId = _readString(body['playerId']);
      if (playerId.isEmpty) {
        throw const FormatException('Le champ playerId est obligatoire.');
      }

      final game = await store.markEggFound(
        gameId: gameId,
        playerId: playerId,
        eggId: eggId,
      );

      return _jsonResponse({'game': game.toJson()});
    } on GameStoreException catch (error) {
      return _errorResponse(400, error.message);
    } on FormatException catch (error) {
      return _errorResponse(400, error.message);
    }
  }

  Future<Response> _closeGame(Request request, String gameId) async {
    try {
      final game = await store.closeGame(gameId);
      return _jsonResponse({'game': game.toJson()});
    } on GameStoreException catch (error) {
      return _errorResponse(404, error.message);
    }
  }

  FutureOr<Response> _gameSocket(Request request, String gameId) {
    final game = store.gameById(gameId);
    if (game == null) {
      return _errorResponse(404, 'Partie introuvable.');
    }

    final handler = webSocketHandler((WebSocketChannel channel, String? _) {
      channel.sink.add(jsonEncode({'type': 'snapshot', 'game': game.toJson()}));

      final subscription = store.updates
          .where((updated) => updated.id == gameId)
          .listen((updatedGame) {
            channel.sink.add(
              jsonEncode({'type': 'snapshot', 'game': updatedGame.toJson()}),
            );
          });

      channel.stream.listen(
        (message) {
          if (message == 'ping') {
            channel.sink.add(jsonEncode({'type': 'pong'}));
          }
        },
        onDone: () async {
          await subscription.cancel();
        },
        onError: (_) async {
          await subscription.cancel();
        },
      );
    }, allowedOrigins: _allowedOrigins);

    return handler(request);
  }

  Future<Response> _servePublic(Request request) async {
    if (request.method != 'GET') {
      return Response.notFound('Not found');
    }
    if (request.url.path.startsWith('api/') ||
        request.url.path.startsWith('ws/')) {
      return Response.notFound('Not found');
    }

    final requestedPath = request.url.path.isEmpty
        ? 'index.html'
        : request.url.path;
    final normalizedRoot = path.normalize(path.absolute(publicDirectory));
    final candidate = path.normalize(path.join(normalizedRoot, requestedPath));
    final safePath =
        path.isWithin(normalizedRoot, candidate) || candidate == normalizedRoot;
    if (!safePath) {
      return Response.forbidden('Forbidden');
    }

    var target = File(candidate);
    if (!await target.exists() && !requestedPath.contains('.')) {
      target = File(path.join(normalizedRoot, 'index.html'));
    }
    if (!await target.exists()) {
      return Response.notFound('Not found');
    }

    return Response.ok(
      target.openRead(),
      headers: {'content-type': _contentTypeFor(target.path)},
    );
  }

  Iterable<String>? get _allowedOrigins {
    if (allowedOrigin == '*') {
      return null;
    }
    return allowedOrigin
        .split(',')
        .map((origin) => origin.trim())
        .where((origin) => origin.isNotEmpty);
  }

  Future<JsonMap> _readJson(Request request) async {
    final raw = await request.readAsString();
    if (raw.trim().isEmpty) {
      return <String, Object?>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('Le corps JSON doit etre un objet.');
  }

  List<String> _readStringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return [
      for (final item in value)
        if (item is String) item,
    ];
  }

  List<EggDraft> _readEggDrafts(Object? value) {
    if (value is! List) {
      return const <EggDraft>[];
    }
    final result = <EggDraft>[];
    for (final item in value) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final playerName = _readString(item['playerName']);
      final hideSpotId = _readString(item['hideSpotId']);
      if (playerName.isEmpty || hideSpotId.isEmpty) {
        continue;
      }
      result.add(EggDraft(playerName: playerName, hideSpotId: hideSpotId));
    }
    return result;
  }

  String _readString(Object? value) {
    return value is String ? value : '';
  }

  String _contentTypeFor(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    switch (extension) {
      case '.html':
        return 'text/html; charset=utf-8';
      case '.css':
        return 'text/css; charset=utf-8';
      case '.js':
        return 'text/javascript; charset=utf-8';
      case '.json':
        return 'application/json; charset=utf-8';
      case '.svg':
        return 'image/svg+xml';
      case '.png':
        return 'image/png';
      case '.ico':
        return 'image/x-icon';
      default:
        return 'application/octet-stream';
    }
  }

  Response _jsonResponse(JsonMap payload, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(payload),
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Response _errorResponse(int status, String message) {
    return _jsonResponse({'error': message}, status: status);
  }

  Middleware _corsMiddleware() {
    final headers = {
      'access-control-allow-origin': allowedOrigin,
      'access-control-allow-methods': 'GET, POST, OPTIONS',
      'access-control-allow-headers': 'Origin, Content-Type, Authorization',
    };

    return (innerHandler) {
      return (request) async {
        if (request.method == 'OPTIONS') {
          return Response(204, headers: headers);
        }

        final response = await innerHandler(request);
        return response.change(headers: {...response.headers, ...headers});
      };
    };
  }
}
