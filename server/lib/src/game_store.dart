import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;

import 'models.dart';
import 'puzzle_catalog.dart';

class GameStore {
  GameStore({required this.dataDirectory});

  final String dataDirectory;

  final Map<String, GameSession> _games = {};
  final StreamController<GameSession> _updates =
      StreamController<GameSession>.broadcast();

  Stream<GameSession> get updates => _updates.stream;

  List<GameSession> listGames() {
    final games = _games.values.toList();
    games.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return games;
  }

  GameSession? get activeGame {
    for (final game in listGames()) {
      if (game.isActive) {
        return game;
      }
    }
    return null;
  }

  GameSession? gameById(String gameId) => _games[gameId];

  Future<void> initialize() async {
    final directory = Directory(dataDirectory);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File(_stateFilePath);
    if (!await file.exists()) {
      return;
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final rawGames = decoded['games'];
    if (rawGames is! List) {
      return;
    }

    for (final item in rawGames) {
      if (item is JsonMap) {
        final game = GameSession.fromJson(item);
        _games[game.id] = game;
      }
    }
  }

  Future<GameSession> createGame({
    required String title,
    required String hostName,
    required List<String> playerNames,
    required List<EggDraft> eggDrafts,
  }) async {
    final sanitizedPlayers = _sanitizePlayerNames(playerNames);
    if (sanitizedPlayers.isEmpty) {
      throw const GameStoreException('Ajoute au moins un joueur.');
    }
    if (eggDrafts.isEmpty) {
      throw const GameStoreException('Ajoute au moins un oeuf.');
    }

    final now = DateTime.now().toUtc();
    for (final game in listGames()) {
      if (game.isActive) {
        _games[game.id] = game.copyWith(status: 'closed', updatedAt: now);
      }
    }

    final players = <PlayerEntry>[];
    for (var index = 0; index < sanitizedPlayers.length; index++) {
      final name = sanitizedPlayers[index];
      players.add(
        PlayerEntry(id: 'player-${index + 1}-${_slug(name)}', name: name),
      );
    }

    final playerIdsByName = {
      for (final player in players) player.name: player.id,
    };
    final orderByPlayer = <String, int>{};
    final eggs = <EggEntry>[];
    for (var index = 0; index < eggDrafts.length; index++) {
      final draft = eggDrafts[index];
      if (!kHideSpotById.containsKey(draft.hideSpotId)) {
        throw GameStoreException(
          'La cachette ${draft.hideSpotId} n\'existe pas dans le catalogue.',
        );
      }
      final playerId = playerIdsByName[draft.playerName];
      if (playerId == null) {
        throw GameStoreException(
          'Le joueur ${draft.playerName} n\'existe pas dans la partie.',
        );
      }
      final order = (orderByPlayer[playerId] ?? 0) + 1;
      orderByPlayer[playerId] = order;
      eggs.add(
        EggEntry(
          id: 'egg-${index + 1}-${draft.hideSpotId}',
          playerId: playerId,
          hideSpotId: draft.hideSpotId,
          order: order,
        ),
      );
    }

    final game = GameSession(
      id: 'hunt-${now.millisecondsSinceEpoch}-${Random().nextInt(99999)}',
      title: title.trim().isEmpty ? 'Chasse de Paques' : title.trim(),
      hostName: hostName.trim().isEmpty ? 'Raspberry Pi' : hostName.trim(),
      players: players,
      eggs: eggs,
      createdAt: now,
      updatedAt: now,
      status: 'active',
    );

    _games[game.id] = game;
    await _persist();
    _updates.add(game);
    return game;
  }

  Future<GameSession> joinPlayer({
    required String gameId,
    required String playerId,
    required String claimant,
  }) async {
    final game = _requireGame(gameId);
    for (final player in game.players) {
      if (player.id != playerId && player.claimedBy == claimant) {
        throw const GameStoreException(
          'Cet appareil a deja reserve un autre joueur.',
        );
      }
    }

    final updatedPlayers = <PlayerEntry>[];
    var found = false;

    for (final player in game.players) {
      if (player.id == playerId) {
        found = true;
        if (player.claimedBy != null &&
            player.claimedBy!.isNotEmpty &&
            player.claimedBy != claimant) {
          throw GameStoreException(
            'Ce joueur est deja selectionne sur un autre appareil.',
          );
        }
        updatedPlayers.add(
          player.copyWith(
            claimedBy: claimant.trim().isEmpty ? null : claimant.trim(),
            joinedAt: DateTime.now().toUtc(),
          ),
        );
      } else {
        updatedPlayers.add(player);
      }
    }

    if (!found) {
      throw const GameStoreException('Joueur introuvable.');
    }

    return _saveGame(
      game.copyWith(players: updatedPlayers, updatedAt: DateTime.now().toUtc()),
    );
  }

  Future<GameSession> releasePlayer({
    required String gameId,
    required String playerId,
    required String claimant,
  }) async {
    final game = _requireGame(gameId);
    final updatedPlayers = <PlayerEntry>[];
    var found = false;

    for (final player in game.players) {
      if (player.id == playerId) {
        found = true;
        if (player.claimedBy != claimant) {
          throw const GameStoreException(
            'Ce joueur est reserve par un autre appareil.',
          );
        }
        updatedPlayers.add(
          player.copyWith(clearClaimedBy: true, clearJoinedAt: true),
        );
      } else {
        updatedPlayers.add(player);
      }
    }

    if (!found) {
      throw const GameStoreException('Joueur introuvable.');
    }

    return _saveGame(
      game.copyWith(players: updatedPlayers, updatedAt: DateTime.now().toUtc()),
    );
  }

  Future<GameSession> markEggFound({
    required String gameId,
    required String playerId,
    required String eggId,
  }) async {
    final game = _requireGame(gameId);
    final updatedEggs = <EggEntry>[];
    var found = false;

    for (final egg in game.eggs) {
      if (egg.id == eggId) {
        if (egg.playerId != playerId) {
          throw const GameStoreException(
            'Cet oeuf n\'est pas attribue a ce joueur.',
          );
        }
        updatedEggs.add(
          egg.copyWith(foundAt: egg.foundAt ?? DateTime.now().toUtc()),
        );
        found = true;
      } else {
        updatedEggs.add(egg);
      }
    }

    if (!found) {
      throw const GameStoreException('Oeuf introuvable.');
    }

    return _saveGame(
      game.copyWith(eggs: updatedEggs, updatedAt: DateTime.now().toUtc()),
    );
  }

  Future<GameSession> closeGame(String gameId) async {
    final game = _requireGame(gameId);
    return _saveGame(
      game.copyWith(status: 'closed', updatedAt: DateTime.now().toUtc()),
    );
  }

  GameSession _requireGame(String gameId) {
    final game = _games[gameId];
    if (game == null) {
      throw const GameStoreException('Partie introuvable.');
    }
    return game;
  }

  Future<GameSession> _saveGame(GameSession game) async {
    _games[game.id] = game;
    await _persist();
    _updates.add(game);
    return game;
  }

  Future<void> _persist() async {
    final file = File(_stateFilePath);
    final payload = jsonEncode({
      'games': [for (final game in listGames()) game.toJson()],
    });
    await file.writeAsString(payload);
  }

  List<String> _sanitizePlayerNames(List<String> names) {
    final result = <String>[];
    final seen = <String>{};
    for (final name in names) {
      final normalized = name.trim();
      if (normalized.isEmpty) {
        continue;
      }
      final key = normalized.toLowerCase();
      if (seen.add(key)) {
        result.add(normalized);
      }
    }
    return result;
  }

  String get _stateFilePath => path.join(dataDirectory, 'state.json');

  static String _slug(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }
}

class GameStoreException implements Exception {
  const GameStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}
