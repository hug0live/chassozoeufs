import '../models/game_models.dart';

abstract class LanPartyService {
  bool get isSupported;
  List<DiscoveredPeer> get peers;

  Future<void> initialize({
    required String deviceId,
    required String deviceName,
    required void Function() onPeersChanged,
  });

  Future<List<DiscoveredPeer>> discover();

  Future<void> startHosting(
    EggHuntGame game, {
    required void Function(EggHuntGame game) onGameChanged,
  });

  Future<void> updateHostedGame(EggHuntGame game);

  Future<void> stopHosting();

  Future<EggHuntGame> fetchGame(DiscoveredPeer host);

  Future<EggHuntGame> markEggFound({
    required DiscoveredPeer host,
    required String playerId,
    required String eggId,
  });

  Future<void> dispose();
}

class LanPartyException implements Exception {
  const LanPartyException(this.message);

  final String message;

  @override
  String toString() => message;
}
