import 'dart:async';

import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../models/puzzle_catalog.dart';
import 'egg_hunt_controller.dart';

class EggHuntApp extends StatefulWidget {
  const EggHuntApp({super.key, this.controller});

  final EggHuntController? controller;

  @override
  State<EggHuntApp> createState() => _EggHuntAppState();
}

class _EggHuntAppState extends State<EggHuntApp> {
  late final bool _ownsController = widget.controller == null;
  late final EggHuntController _controller =
      widget.controller ?? EggHuntController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chasse aux oeufs',
      theme: _buildTheme(),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _EggHuntShell(controller: _controller),
      ),
    );
  }
}

ThemeData _buildTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFFD96A34),
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFFB4491A),
        secondary: const Color(0xFF5B8A3C),
        tertiary: const Color(0xFFE4A22A),
        surface: const Color(0xFFFFFBF4),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xFFF8F1E2),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        height: 1.05,
      ),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 16, height: 1.45),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFFFFFBF6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Color(0x1A8B5E34)),
      ),
      margin: EdgeInsets.zero,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class _EggHuntShell extends StatelessWidget {
  const _EggHuntShell({required this.controller});

  final EggHuntController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF6E7C9), Color(0xFFFCEFD8), Color(0xFFE4F0D4)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeroBanner(controller: controller),
                        if (controller.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: _ErrorBanner(
                              message: controller.errorMessage!,
                              onClose: controller.clearError,
                            ),
                          ),
                        const SizedBox(height: 18),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: _buildStage(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (controller.isBusy)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 4),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    switch (controller.stage) {
      case EggHuntStage.scanning:
        return const _ScanningView(key: ValueKey('scanning'));
      case EggHuntStage.lobby:
        return _LobbyView(key: const ValueKey('lobby'), controller: controller);
      case EggHuntStage.createSetup:
        return _CreateGameView(
          key: const ValueKey('create'),
          controller: controller,
        );
      case EggHuntStage.hostDashboard:
        return _HostDashboardView(
          key: const ValueKey('host'),
          controller: controller,
        );
      case EggHuntStage.playerPicker:
        return _PlayerPickerView(
          key: const ValueKey('picker'),
          controller: controller,
        );
      case EggHuntStage.playerHunt:
        return _PlayerHuntView(
          key: const ValueKey('hunt'),
          controller: controller,
        );
    }
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.controller});

  final EggHuntController controller;

  @override
  Widget build(BuildContext context) {
    final stageLabel = switch (controller.stage) {
      EggHuntStage.scanning => 'Recherche du reseau',
      EggHuntStage.lobby => 'Salon de depart',
      EggHuntStage.createSetup => 'Creation de partie',
      EggHuntStage.hostDashboard => 'Maitre du jeu',
      EggHuntStage.playerPicker => 'Choix du joueur',
      EggHuntStage.playerHunt => 'Enigmes en cours',
    };

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        gradient: const LinearGradient(
          colors: [Color(0xFFA24119), Color(0xFFD96A34), Color(0xFFEAA93A)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22191B16),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Pill(
                icon: Icons.egg_alt,
                label: stageLabel,
                foreground: Colors.white,
                background: const Color(0x1FFFFFFF),
              ),
              _Pill(
                icon: Icons.wifi_tethering,
                label: controller.deviceName,
                foreground: Colors.white,
                background: const Color(0x1FFFFFFF),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Chasse aux oeufs connectee',
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            "Un appareil cache les oeufs, les autres rejoignent la partie sur le meme reseau local et resolvent des enigmes difficiles avant d'obtenir un indice.",
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: const Color(0xFFFBECDD)),
          ),
        ],
      ),
    );
  }
}

class _ScanningView extends StatelessWidget {
  const _ScanningView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SectionCard(
      title: 'Recherche des autres appareils',
      subtitle:
          "L'application sonde le reseau local pour voir si une partie est deja ouverte.",
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text('Exploration du Wi-Fi en cours...'),
            ],
          ),
        ),
      ),
    );
  }
}

class _LobbyView extends StatelessWidget {
  const _LobbyView({super.key, required this.controller});

  final EggHuntController controller;

  @override
  Widget build(BuildContext context) {
    final peers = controller.peers;
    final activeHosts = controller.activeHosts;
    final nearbyCount = peers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'Etat du reseau local',
          subtitle: controller.isNetworkSupported
              ? nearbyCount == 0
                    ? "Aucun autre appareil n'a repondu pour l'instant."
                    : '$nearbyCount appareil(s) detecte(s) sur le reseau local.'
              : "Cette plateforme ne prend pas en charge la decouverte reseau de ce prototype.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.isNetworkSupported)
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [for (final peer in peers) _PeerChip(peer: peer)],
                )
              else
                const Text(
                  "Le prototype LAN cible surtout Android, iPhone et les ordinateurs connectes au meme Wi-Fi.",
                ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: controller.isNetworkSupported
                        ? () => controller.refreshPeers()
                        : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Rechercher a nouveau'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isNetworkSupported
                        ? controller.openCreateSetup
                        : null,
                    icon: const Icon(Icons.egg),
                    label: const Text('Creer une partie'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (activeHosts.isNotEmpty)
          _SectionCard(
            title: 'Parties disponibles',
            subtitle:
                "Une partie active a ete detectee. Choisis celle que tu veux rejoindre.",
            child: Column(
              children: [
                for (final host in activeHosts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _HostTile(
                      host: host,
                      onJoin: () => controller.joinHost(host),
                    ),
                  ),
              ],
            ),
          )
        else
          _SectionCard(
            title: 'Aucune partie en cours',
            subtitle: nearbyCount == 0
                ? "Si personne d'autre n'a l'application ouverte, tu peux devenir le maitre du jeu."
                : "Des appareils sont bien presents, mais personne n'a encore lance la partie. Tu peux la creer maintenant.",
            child: const Text(
              "Le createur preparera la liste des joueurs, les cachettes et l'ordre des oeufs. Les autres appareils pourront ensuite rejoindre la chasse.",
            ),
          ),
      ],
    );
  }
}

class _CreateGameView extends StatefulWidget {
  const _CreateGameView({super.key, required this.controller});

  final EggHuntController controller;

  @override
  State<_CreateGameView> createState() => _CreateGameViewState();
}

class _CreateGameViewState extends State<_CreateGameView> {
  late final TextEditingController _titleController = TextEditingController(
    text: 'Chasse de ${widget.controller.deviceName}',
  );
  final TextEditingController _playerController = TextEditingController();
  final List<String> _players = <String>[];
  final List<_DraftEgg> _eggs = <_DraftEgg>[];
  int _nextDraftId = 0;

  @override
  void dispose() {
    _titleController.dispose();
    _playerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'Construire la partie',
          subtitle:
              "Le createur choisit les chasseurs, puis cache un ou plusieurs oeufs avec une cachette precise pour chacun.",
          action: TextButton.icon(
            onPressed: widget.controller.returnToLobby,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Retour'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Nom de la partie',
                  hintText: 'Ex. Chasse du dimanche',
                ),
              ),
              const SizedBox(height: 22),
              Text('Joueurs', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _playerController,
                      decoration: const InputDecoration(
                        labelText: 'Ajouter un joueur',
                        hintText: 'Ex. Zoe',
                      ),
                      onSubmitted: (_) => _addPlayer(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _addPlayer,
                    child: const Text('Ajouter'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_players.isEmpty)
                const Text(
                  "Ajoute les enfants ou joueurs qui devront chercher les oeufs.",
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final player in _players)
                      InputChip(
                        label: Text(player),
                        onDeleted: () => _removePlayer(player),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Cachettes et enigmes',
          subtitle:
              "Chaque oeuf est rattache a un joueur et a une cachette predefinie. L'application affichera ensuite l'enigme difficile correspondante.",
          action: FilledButton.tonalIcon(
            onPressed: _players.isEmpty ? null : _addEgg,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Ajouter un oeuf'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_players.isEmpty)
                const Text(
                  "Ajoute d'abord au moins un joueur avant de preparer les oeufs.",
                )
              else if (_eggs.isEmpty)
                const Text(
                  "Aucun oeuf n'est configure pour le moment. Utilise le bouton ci-dessus pour ajouter la premiere cachette.",
                )
              else
                for (final draft in _eggs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _DraftEggCard(
                      draft: draft,
                      players: _players,
                      onChanged: () => setState(() {}),
                      onRemove: () => _removeEgg(draft.id),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _players.isNotEmpty && _eggs.isNotEmpty
                ? () => widget.controller.startHosting(
                    title: _titleController.text,
                    playerNames: _players,
                    eggDrafts: [
                      for (final egg in _eggs)
                        HostEggDraft(
                          playerName: egg.playerName,
                          hideSpotId: egg.hideSpotId,
                        ),
                    ],
                  )
                : null,
            icon: const Icon(Icons.wifi),
            label: const Text('Lancer la partie'),
          ),
        ),
      ],
    );
  }

  void _addPlayer() {
    final value = _playerController.text.trim();
    if (value.isEmpty) {
      return;
    }
    final exists = _players.any(
      (player) => player.toLowerCase() == value.toLowerCase(),
    );
    if (exists) {
      _playerController.clear();
      return;
    }
    setState(() {
      _players.add(value);
      _playerController.clear();
      if (_eggs.isEmpty) {
        _eggs.add(_createDefaultEgg());
      } else {
        for (final egg in _eggs) {
          if (!_players.contains(egg.playerName)) {
            egg.playerName = _players.first;
          }
        }
      }
    });
  }

  void _removePlayer(String player) {
    setState(() {
      _players.remove(player);
      _eggs.removeWhere((egg) => egg.playerName == player);
      if (_players.isNotEmpty) {
        for (final egg in _eggs) {
          if (!_players.contains(egg.playerName)) {
            egg.playerName = _players.first;
          }
        }
      }
    });
  }

  void _addEgg() {
    setState(() {
      _eggs.add(_createDefaultEgg());
    });
  }

  void _removeEgg(int id) {
    setState(() {
      _eggs.removeWhere((egg) => egg.id == id);
    });
  }

  _DraftEgg _createDefaultEgg() {
    final firstArea = kAreas.first;
    final firstSpot = hideSpotsForArea(firstArea).first;
    return _DraftEgg(
      id: _nextDraftId++,
      playerName: _players.first,
      area: firstArea,
      hideSpotId: firstSpot.id,
    );
  }
}

class _HostDashboardView extends StatelessWidget {
  const _HostDashboardView({super.key, required this.controller});

  final EggHuntController controller;

  @override
  Widget build(BuildContext context) {
    final game = controller.hostedGame;
    if (game == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: game.title,
          subtitle:
              "La partie est annoncee sur le reseau local. Les autres appareils peuvent maintenant la rejoindre.",
          action: TextButton.icon(
            onPressed: controller.stopHostedGame,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Arreter'),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatBadge(
                icon: Icons.group,
                label: '${game.players.length} joueur(s)',
                tone: const Color(0xFFEED7B8),
              ),
              _StatBadge(
                icon: Icons.egg_alt,
                label: '${game.eggs.length} oeuf(s)',
                tone: const Color(0xFFF3E7A4),
              ),
              _StatBadge(
                icon: Icons.devices,
                label: '${controller.peers.length} appareil(s) detecte(s)',
                tone: const Color(0xFFDCEAD1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Suivi des joueurs',
          subtitle:
              "Le maitre du jeu peut verifier en temps reel quels oeufs ont ete trouves.",
          child: Column(
            children: [
              for (final player in game.players)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PlayerProgressTile(
                    player: player,
                    eggs: game.eggsForPlayer(player.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Cachettes configurees',
          subtitle:
              "Chaque ligne indique a quel joueur un oeuf a ete attribue, avec la cachette choisie.",
          child: Column(
            children: [
              for (final egg in game.eggs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HostEggTile(
                    egg: egg,
                    playerName:
                        game.playerById(egg.playerId)?.name ?? 'Inconnu',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerPickerView extends StatelessWidget {
  const _PlayerPickerView({super.key, required this.controller});

  final EggHuntController controller;

  @override
  Widget build(BuildContext context) {
    final game = controller.remoteGame;
    if (game == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: game.title,
          subtitle:
              "Choisis le nom prepare par le createur pour commencer a recevoir tes enigmes.",
          action: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: controller.returnToLobby,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Changer de partie'),
              ),
              FilledButton.tonalIcon(
                onPressed: controller.refreshRemoteGame,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          child: Text(
            'Hote detecte: ${game.hostDeviceName}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Joueurs disponibles',
          subtitle:
              "Le createur a deja reparti les cachettes. Chaque joueur verra ensuite ses oeufs les uns apres les autres.",
          child: Column(
            children: [
              for (final player in game.players)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _JoinPlayerTile(
                    player: player,
                    eggs: game.eggsForPlayer(player.id),
                    onTap: () => controller.selectPlayer(player.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerHuntView extends StatefulWidget {
  const _PlayerHuntView({super.key, required this.controller});

  final EggHuntController controller;

  @override
  State<_PlayerHuntView> createState() => _PlayerHuntViewState();
}

class _PlayerHuntViewState extends State<_PlayerHuntView> {
  Timer? _ticker;
  String? _trackedEggId;
  DateTime? _riddleStartedAt;

  @override
  void initState() {
    super.initState();
    _syncCurrentEgg();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(_syncCurrentEgg);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _PlayerHuntView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCurrentEgg();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.controller.selectedPlayer;
    final eggs = widget.controller.selectedPlayerEggs;
    final currentEgg = widget.controller.currentEgg;
    final foundCount = eggs.where((egg) => egg.isFound).length;
    final totalCount = eggs.length;

    if (player == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'Tour de ${player.name}',
          subtitle: totalCount == 0
              ? "Aucun oeuf n'a encore ete attribue a ce joueur."
              : 'Progression: $foundCount / $totalCount oeuf(s) trouves.',
          action: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: widget.controller.backToPlayerPicker,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Changer de joueur'),
              ),
              FilledButton.tonalIcon(
                onPressed: widget.controller.refreshRemoteGame,
                icon: const Icon(Icons.sync),
                label: const Text('Synchroniser'),
              ),
            ],
          ),
          child: totalCount == 0
              ? const Text(
                  "Le createur n'a pas encore attribue d'oeuf a ce joueur. Reviens plus tard ou demande-lui d'ajouter une cachette.",
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: totalCount == 0 ? 0 : foundCount / totalCount,
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      currentEgg == null
                          ? 'Mission accomplie: tous les oeufs de ${player.name} ont ete trouves.'
                          : 'Oeuf ${foundCount + 1} sur $totalCount',
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        if (currentEgg != null)
          _SectionCard(
            title: 'Enigme en cours',
            subtitle: _hintUnlocked
                ? "L'indice est maintenant disponible. Si besoin, utilise-le."
                : 'Indice dans ${_remainingLabel()} si tu ne trouves pas avant.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF2DD),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    currentEgg.hideSpot.riddle,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(height: 1.25),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _hintUnlocked
                      ? Container(
                          key: const ValueKey('hint-on'),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDDEECC),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Text(
                            'Indice: ${currentEgg.hideSpot.hint}',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        )
                      : Container(
                          key: const ValueKey('hint-off'),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F0E8),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Text(
                            "Tiens bon encore un peu: l'indice s'affichera automatiquement apres 5 minutes.",
                          ),
                        ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: widget.controller.markCurrentEggFound,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Trouve !'),
                ),
              ],
            ),
          )
        else if (totalCount > 0)
          const _SectionCard(
            title: 'Tous les oeufs sont trouves',
            subtitle:
                "Bravo. Le joueur a termine sa chasse, il peut maintenant aller fanfaronner.",
            child: Text(
              "Tu peux revenir a la liste des joueurs pour lancer la chasse d'un autre participant.",
            ),
          ),
        if (eggs.isNotEmpty) ...[
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Journal du joueur',
            subtitle:
                "Les oeufs trouves revelent leur cachette. Les suivants restent secrets tant qu'ils ne sont pas valides.",
            child: Column(
              children: [
                for (final egg in eggs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PlayerEggHistoryTile(
                      egg: egg,
                      revealLocation: egg.isFound,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  bool get _hintUnlocked {
    final startedAt = _riddleStartedAt;
    if (startedAt == null) {
      return false;
    }
    return DateTime.now().difference(startedAt) >= const Duration(minutes: 5);
  }

  String _remainingLabel() {
    final startedAt = _riddleStartedAt;
    if (startedAt == null) {
      return '05:00';
    }
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = const Duration(minutes: 5) - elapsed;
    if (remaining.isNegative) {
      return '00:00';
    }
    final minutes = remaining.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _syncCurrentEgg() {
    final eggId = widget.controller.currentEgg?.id;
    if (_trackedEggId == eggId) {
      return;
    }
    _trackedEggId = eggId;
    _riddleStartedAt = eggId == null ? null : DateTime.now();
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(subtitle),
                    ],
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 12), action!],
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _PeerChip extends StatelessWidget {
  const _PeerChip({required this.peer});

  final DiscoveredPeer peer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: peer.isJoinable
            ? const Color(0xFFDDEECC)
            : const Color(0xFFF1E7DA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(peer.isJoinable ? Icons.wifi : Icons.devices_other, size: 18),
          const SizedBox(width: 8),
          Text(peer.deviceName),
        ],
      ),
    );
  }
}

class _HostTile extends StatelessWidget {
  const _HostTile({required this.host, required this.onJoin});

  final DiscoveredPeer host;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2DE),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: Color(0xFFD96A34),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.egg_alt, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  host.gameTitle ?? 'Partie sans nom',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text('Creee par ${host.deviceName}'),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: onJoin,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Rejoindre'),
          ),
        ],
      ),
    );
  }
}

class _DraftEggCard extends StatelessWidget {
  const _DraftEggCard({
    required this.draft,
    required this.players,
    required this.onChanged,
    required this.onRemove,
  });

  final _DraftEgg draft;
  final List<String> players;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final availableSpots = hideSpotsForArea(draft.area);
    final currentSpot = hideSpotById(draft.hideSpotId);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8EFE3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Oeuf a cacher',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: draft.playerName,
            decoration: const InputDecoration(labelText: 'Pour quel joueur ?'),
            items: [
              for (final player in players)
                DropdownMenuItem(value: player, child: Text(player)),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              draft.playerName = value;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: draft.area,
            decoration: const InputDecoration(labelText: 'Piece / zone'),
            items: [
              for (final area in kAreas)
                DropdownMenuItem(value: area, child: Text(area)),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              final nextSpot = hideSpotsForArea(value).first;
              draft.area = value;
              draft.hideSpotId = nextSpot.id;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: draft.hideSpotId,
            decoration: const InputDecoration(labelText: 'Objet / cachette'),
            items: [
              for (final spot in availableSpots)
                DropdownMenuItem(value: spot.id, child: Text(spot.objectLabel)),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              draft.hideSpotId = value;
              onChanged();
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Enigme qui sera envoyee',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(currentSpot.riddle),
          const SizedBox(height: 10),
          Text(
            'Indice apres 5 minutes: ${currentSpot.hint}',
            style: const TextStyle(
              color: Color(0xFF5A6A38),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerProgressTile extends StatelessWidget {
  const _PlayerProgressTile({required this.player, required this.eggs});

  final PlayerProfile player;
  final List<EggAssignment> eggs;

  @override
  Widget build(BuildContext context) {
    final foundCount = eggs.where((egg) => egg.isFound).length;
    final totalCount = eggs.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8EFE3),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  player.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text('$foundCount / $totalCount'),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: totalCount == 0 ? 0 : foundCount / totalCount,
              minHeight: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _HostEggTile extends StatelessWidget {
  const _HostEggTile({required this.egg, required this.playerName});

  final EggAssignment egg;
  final String playerName;

  @override
  Widget build(BuildContext context) {
    final statusColor = egg.isFound
        ? const Color(0xFFDDEECC)
        : const Color(0xFFFFF0DE);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(egg.isFound ? Icons.check_circle : Icons.egg_alt),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${egg.hideSpot.area} · ${egg.hideSpot.objectLabel}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text('Attribue a $playerName'),
              ],
            ),
          ),
          Text(egg.isFound ? 'Trouve' : 'Cache'),
        ],
      ),
    );
  }
}

class _JoinPlayerTile extends StatelessWidget {
  const _JoinPlayerTile({
    required this.player,
    required this.eggs,
    required this.onTap,
  });

  final PlayerProfile player;
  final List<EggAssignment> eggs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final totalCount = eggs.length;
    final foundCount = eggs.where((egg) => egg.isFound).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7EEDB),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalCount oeuf(s) a chercher, $foundCount deja trouves.',
                ),
              ],
            ),
          ),
          FilledButton(onPressed: onTap, child: const Text('Choisir')),
        ],
      ),
    );
  }
}

class _PlayerEggHistoryTile extends StatelessWidget {
  const _PlayerEggHistoryTile({
    required this.egg,
    required this.revealLocation,
  });

  final EggAssignment egg;
  final bool revealLocation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: egg.isFound ? const Color(0xFFDDEECC) : const Color(0xFFF6F0E8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(egg.isFound ? Icons.check_circle : Icons.hourglass_top),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              revealLocation
                  ? '${egg.hideSpot.area} · ${egg.hideSpot.objectLabel}'
                  : 'Enigme a venir',
            ),
          ),
          Text(egg.isFound ? 'Trouve' : 'En attente'),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5D8D1),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}

class _DraftEgg {
  _DraftEgg({
    required this.id,
    required this.playerName,
    required this.area,
    required this.hideSpotId,
  });

  final int id;
  String playerName;
  String area;
  String hideSpotId;
}
