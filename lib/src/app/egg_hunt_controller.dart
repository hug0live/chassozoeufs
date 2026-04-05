import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/game_models.dart';
import '../network/lan_party_service.dart';

enum EggHuntStage {
  scanning,
  lobby,
  createSetup,
  hostDashboard,
  playerPicker,
  playerHunt,
}

class HostEggDraft {
  const HostEggDraft({required this.playerName, required this.hideSpotId});

  final String playerName;
  final String hideSpotId;
}

class EggHuntController extends ChangeNotifier {
  EggHuntController({
    LanPartyService? networkService,
    String? deviceId,
    String? deviceName,
  }) : _networkService = networkService ?? createLanPartyService(),
       deviceId = deviceId ?? _generateDeviceId(),
       deviceName = deviceName ?? _generateDeviceName();

  final LanPartyService _networkService;
  final String deviceId;
  final String deviceName;

  EggHuntStage _stage = EggHuntStage.scanning;
  bool _isBusy = false;
  bool _isInitialized = false;
  String? _errorMessage;
  List<DiscoveredPeer> _peers = const [];
  EggHuntGame? _hostedGame;
  EggHuntGame? _remoteGame;
  DiscoveredPeer? _selectedHost;
  String? _selectedPlayerId;
  Timer? _pollTimer;

  EggHuntStage get stage => _stage;
  bool get isBusy => _isBusy;
  bool get isNetworkSupported => _networkService.isSupported;
  String? get errorMessage => _errorMessage;
  List<DiscoveredPeer> get peers => _peers;
  EggHuntGame? get hostedGame => _hostedGame;
  EggHuntGame? get remoteGame => _remoteGame;
  DiscoveredPeer? get selectedHost => _selectedHost;
  String? get selectedPlayerId => _selectedPlayerId;

  List<DiscoveredPeer> get activeHosts {
    final hosts = _peers.where((peer) => peer.isJoinable).toList();
    hosts.sort((left, right) {
      final leftLabel = left.gameTitle ?? left.deviceName;
      final rightLabel = right.gameTitle ?? right.deviceName;
      return leftLabel.compareTo(rightLabel);
    });
    return hosts;
  }

  PlayerProfile? get selectedPlayer {
    final playerId = _selectedPlayerId;
    final game = _remoteGame;
    if (playerId == null || game == null) {
      return null;
    }
    return game.playerById(playerId);
  }

  List<EggAssignment> get selectedPlayerEggs {
    final game = _remoteGame;
    final playerId = _selectedPlayerId;
    if (game == null || playerId == null) {
      return const <EggAssignment>[];
    }
    return game.eggsForPlayer(playerId);
  }

  EggAssignment? get currentEgg {
    for (final egg in selectedPlayerEggs) {
      if (!egg.isFound) {
        return egg;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    _isInitialized = true;

    if (!isNetworkSupported) {
      _stage = EggHuntStage.lobby;
      notifyListeners();
      return;
    }

    _isBusy = true;
    notifyListeners();
    try {
      await _networkService.initialize(
        deviceId: deviceId,
        deviceName: deviceName,
        onPeersChanged: _onPeersChanged,
      );
      await refreshPeers(quiet: true);
    } catch (error) {
      _errorMessage = error.toString();
      _stage = EggHuntStage.lobby;
    } finally {
      _isBusy = false;
      if (_stage == EggHuntStage.scanning) {
        _stage = EggHuntStage.lobby;
      }
      notifyListeners();
    }
  }

  Future<void> refreshPeers({bool quiet = false}) async {
    if (!isNetworkSupported) {
      _peers = const [];
      _stage = EggHuntStage.lobby;
      notifyListeners();
      return;
    }

    if (!quiet) {
      _isBusy = true;
      notifyListeners();
    }

    try {
      _peers = await _networkService.discover();
      _errorMessage = null;
      if (_stage == EggHuntStage.scanning) {
        _stage = EggHuntStage.lobby;
      }
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      if (!quiet) {
        _isBusy = false;
      }
      notifyListeners();
    }
  }

  void openCreateSetup() {
    _stopPolling();
    _remoteGame = null;
    _selectedHost = null;
    _selectedPlayerId = null;
    _errorMessage = null;
    _stage = EggHuntStage.createSetup;
    notifyListeners();
  }

  Future<void> startHosting({
    required String title,
    required List<String> playerNames,
    required List<HostEggDraft> eggDrafts,
  }) async {
    final cleanedPlayers = _sanitizePlayerNames(playerNames);
    if (cleanedPlayers.isEmpty || eggDrafts.isEmpty) {
      _errorMessage =
          'Ajoute au moins un joueur et un oeuf pour lancer la partie.';
      notifyListeners();
      return;
    }

    final players = <PlayerProfile>[];
    for (var index = 0; index < cleanedPlayers.length; index++) {
      players.add(
        PlayerProfile(
          id: 'player-${index + 1}-${_slug(cleanedPlayers[index])}',
          name: cleanedPlayers[index],
        ),
      );
    }
    final playerIdsByName = {
      for (final player in players) player.name: player.id,
    };

    final orderByPlayer = <String, int>{};
    final eggs = <EggAssignment>[];
    for (var index = 0; index < eggDrafts.length; index++) {
      final draft = eggDrafts[index];
      final playerId = playerIdsByName[draft.playerName];
      if (playerId == null) {
        continue;
      }
      final order = (orderByPlayer[playerId] ?? 0) + 1;
      orderByPlayer[playerId] = order;
      eggs.add(
        EggAssignment(
          id: 'egg-${index + 1}-${draft.hideSpotId}',
          playerId: playerId,
          hideSpotId: draft.hideSpotId,
          order: order,
        ),
      );
    }

    if (eggs.isEmpty) {
      _errorMessage = 'Chaque oeuf doit etre attribue a un joueur existant.';
      notifyListeners();
      return;
    }

    final game = EggHuntGame(
      id: 'hunt-${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Chasse de Paques' : title.trim(),
      hostDeviceId: deviceId,
      hostDeviceName: deviceName,
      players: players,
      eggs: eggs,
      createdAt: DateTime.now(),
    );

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _networkService.startHosting(
        game,
        onGameChanged: (updatedGame) {
          _hostedGame = updatedGame;
          notifyListeners();
        },
      );
      _hostedGame = game;
      _remoteGame = null;
      _selectedHost = null;
      _selectedPlayerId = null;
      _stage = EggHuntStage.hostDashboard;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> joinHost(DiscoveredPeer host) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final game = await _networkService.fetchGame(host);
      _selectedHost = host;
      _remoteGame = game;
      _selectedPlayerId = null;
      _stage = EggHuntStage.playerPicker;
      _startPolling();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void selectPlayer(String playerId) {
    _selectedPlayerId = playerId;
    _stage = EggHuntStage.playerHunt;
    notifyListeners();
  }

  void backToPlayerPicker() {
    _stage = EggHuntStage.playerPicker;
    notifyListeners();
  }

  Future<void> markCurrentEggFound() async {
    final host = _selectedHost;
    final playerId = _selectedPlayerId;
    final egg = currentEgg;
    if (host == null || playerId == null || egg == null) {
      return;
    }

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _remoteGame = await _networkService.markEggFound(
        host: host,
        playerId: playerId,
        eggId: egg.id,
      );
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> refreshRemoteGame({bool quiet = false}) async {
    final host = _selectedHost;
    if (host == null) {
      return;
    }
    if (!quiet) {
      _isBusy = true;
      notifyListeners();
    }
    try {
      _remoteGame = await _networkService.fetchGame(host);
      _errorMessage = null;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      if (!quiet) {
        _isBusy = false;
      }
      notifyListeners();
    }
  }

  Future<void> stopHostedGame() async {
    _isBusy = true;
    notifyListeners();
    try {
      await _networkService.stopHosting();
      _hostedGame = null;
      _stage = EggHuntStage.lobby;
      await refreshPeers(quiet: true);
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> returnToLobby() async {
    _stopPolling();
    _remoteGame = null;
    _selectedHost = null;
    _selectedPlayerId = null;
    _stage = EggHuntStage.lobby;
    notifyListeners();
    await refreshPeers(quiet: true);
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _onPeersChanged() {
    _peers = _networkService.peers;
    notifyListeners();
  }

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refreshRemoteGame(quiet: true)),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  List<String> _sanitizePlayerNames(List<String> names) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in names) {
      final normalized = raw.trim();
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

  static String _slug(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  static String _generateDeviceId() {
    final random = Random();
    return '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(999999)}';
  }

  static String _generateDeviceName() {
    const prefixes = ['Lapin', 'Panier', 'Clochette', 'Tulipe'];
    final random = Random();
    final prefix = prefixes[random.nextInt(prefixes.length)];
    final suffix = 100 + random.nextInt(900);
    return '$prefix $suffix';
  }

  @override
  void dispose() {
    _stopPolling();
    unawaited(_networkService.dispose());
    super.dispose();
  }
}
