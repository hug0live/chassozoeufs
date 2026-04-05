import 'package:chassozoeufs/src/app/egg_hunt_app.dart';
import 'package:chassozoeufs/src/app/egg_hunt_controller.dart';
import 'package:chassozoeufs/src/models/game_models.dart';
import 'package:chassozoeufs/src/network/lan_party_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows lobby actions when no game is available', (tester) async {
    final controller = EggHuntController(
      networkService: _FakeLanPartyService(),
      deviceId: 'test-device',
      deviceName: 'Lapin Test',
    );

    await tester.pumpWidget(EggHuntApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Chasse aux oeufs connectee'), findsOneWidget);
    expect(find.text('Creer une partie'), findsOneWidget);
    expect(find.text('Aucune partie en cours'), findsOneWidget);
  });
}

class _FakeLanPartyService implements LanPartyService {
  @override
  bool get isSupported => true;

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
    throw const LanPartyException('No host in widget test.');
  }

  @override
  Future<EggHuntGame> markEggFound({
    required DiscoveredPeer host,
    required String playerId,
    required String eggId,
  }) {
    throw const LanPartyException('No host in widget test.');
  }

  @override
  Future<void> startHosting(
    EggHuntGame game, {
    required void Function(EggHuntGame game) onGameChanged,
  }) async {}

  @override
  Future<void> stopHosting() async {}

  @override
  Future<void> updateHostedGame(EggHuntGame game) async {}

  @override
  Future<void> dispose() async {}
}
