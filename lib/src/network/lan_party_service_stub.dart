import '../models/game_models.dart';
import 'lan_party_service_base.dart';

LanPartyService createLanPartyService() => _StubLanPartyService();

class _StubLanPartyService implements LanPartyService {
  @override
  bool get isSupported => false;

  @override
  List<DiscoveredPeer> get peers => const [];

  @override
  Future<void> initialize({
    required String deviceId,
    required String deviceName,
    required void Function() onPeersChanged,
  }) async {}

  @override
  Future<List<DiscoveredPeer>> discover() async => const [];

  @override
  Future<EggHuntGame> fetchGame(DiscoveredPeer host) {
    throw const LanPartyException(
      "Le reseau local n'est pas disponible sur cette plateforme.",
    );
  }

  @override
  Future<EggHuntGame> markEggFound({
    required DiscoveredPeer host,
    required String playerId,
    required String eggId,
  }) {
    throw const LanPartyException(
      "Le reseau local n'est pas disponible sur cette plateforme.",
    );
  }

  @override
  Future<void> startHosting(
    EggHuntGame game, {
    required void Function(EggHuntGame game) onGameChanged,
  }) {
    throw const LanPartyException(
      "Le reseau local n'est pas disponible sur cette plateforme.",
    );
  }

  @override
  Future<void> stopHosting() async {}

  @override
  Future<void> updateHostedGame(EggHuntGame game) async {}

  @override
  Future<void> dispose() async {}
}
