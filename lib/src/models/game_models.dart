import 'puzzle_catalog.dart';

typedef JsonMap = Map<String, dynamic>;

String _readString(Object? value, {String fallback = ''}) {
  return value is String ? value : fallback;
}

DateTime? _readDateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

class PlayerProfile {
  const PlayerProfile({required this.id, required this.name});

  final String id;
  final String name;

  JsonMap toJson() => {'id': id, 'name': name};

  factory PlayerProfile.fromJson(JsonMap json) {
    return PlayerProfile(
      id: _readString(json['id']),
      name: _readString(json['name']),
    );
  }
}

class EggAssignment {
  const EggAssignment({
    required this.id,
    required this.playerId,
    required this.hideSpotId,
    required this.order,
    this.foundAt,
  });

  final String id;
  final String playerId;
  final String hideSpotId;
  final int order;
  final DateTime? foundAt;

  bool get isFound => foundAt != null;

  HideSpotDefinition get hideSpot => hideSpotById(hideSpotId);

  EggAssignment copyWith({
    String? id,
    String? playerId,
    String? hideSpotId,
    int? order,
    DateTime? foundAt,
    bool clearFoundAt = false,
  }) {
    return EggAssignment(
      id: id ?? this.id,
      playerId: playerId ?? this.playerId,
      hideSpotId: hideSpotId ?? this.hideSpotId,
      order: order ?? this.order,
      foundAt: clearFoundAt ? null : foundAt ?? this.foundAt,
    );
  }

  JsonMap toJson() => {
    'id': id,
    'playerId': playerId,
    'hideSpotId': hideSpotId,
    'order': order,
    'foundAt': foundAt?.toIso8601String(),
  };

  factory EggAssignment.fromJson(JsonMap json) {
    return EggAssignment(
      id: _readString(json['id']),
      playerId: _readString(json['playerId']),
      hideSpotId: _readString(json['hideSpotId']),
      order: json['order'] is int ? json['order'] as int : 0,
      foundAt: _readDateTime(json['foundAt']),
    );
  }
}

class EggHuntGame {
  const EggHuntGame({
    required this.id,
    required this.title,
    required this.hostDeviceId,
    required this.hostDeviceName,
    required this.players,
    required this.eggs,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String hostDeviceId;
  final String hostDeviceName;
  final List<PlayerProfile> players;
  final List<EggAssignment> eggs;
  final DateTime createdAt;

  PlayerProfile? playerById(String id) {
    for (final player in players) {
      if (player.id == id) {
        return player;
      }
    }
    return null;
  }

  List<EggAssignment> eggsForPlayer(String playerId) {
    final playerEggs = eggs.where((egg) => egg.playerId == playerId).toList();
    playerEggs.sort((left, right) => left.order.compareTo(right.order));
    return playerEggs;
  }

  EggHuntGame copyWith({
    String? id,
    String? title,
    String? hostDeviceId,
    String? hostDeviceName,
    List<PlayerProfile>? players,
    List<EggAssignment>? eggs,
    DateTime? createdAt,
  }) {
    return EggHuntGame(
      id: id ?? this.id,
      title: title ?? this.title,
      hostDeviceId: hostDeviceId ?? this.hostDeviceId,
      hostDeviceName: hostDeviceName ?? this.hostDeviceName,
      players: players ?? this.players,
      eggs: eggs ?? this.eggs,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  JsonMap toJson() => {
    'id': id,
    'title': title,
    'hostDeviceId': hostDeviceId,
    'hostDeviceName': hostDeviceName,
    'players': players.map((player) => player.toJson()).toList(),
    'eggs': eggs.map((egg) => egg.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory EggHuntGame.fromJson(JsonMap json) {
    final playersJson = json['players'] is List
        ? json['players'] as List<Object?>
        : const [];
    final eggsJson = json['eggs'] is List
        ? json['eggs'] as List<Object?>
        : const [];
    return EggHuntGame(
      id: _readString(json['id']),
      title: _readString(json['title']),
      hostDeviceId: _readString(json['hostDeviceId']),
      hostDeviceName: _readString(json['hostDeviceName']),
      players: [
        for (final raw in playersJson)
          if (raw is JsonMap) PlayerProfile.fromJson(raw),
      ],
      eggs: [
        for (final raw in eggsJson)
          if (raw is JsonMap) EggAssignment.fromJson(raw),
      ],
      createdAt: _readDateTime(json['createdAt']) ?? DateTime.now(),
    );
  }
}

class DiscoveredPeer {
  const DiscoveredPeer({
    required this.deviceId,
    required this.deviceName,
    required this.address,
    required this.hasActiveGame,
    required this.lastSeen,
    this.hostPort,
    this.gameId,
    this.gameTitle,
  });

  final String deviceId;
  final String deviceName;
  final String address;
  final bool hasActiveGame;
  final DateTime lastSeen;
  final int? hostPort;
  final String? gameId;
  final String? gameTitle;

  bool get isJoinable => hasActiveGame && hostPort != null;

  DiscoveredPeer copyWith({
    String? deviceId,
    String? deviceName,
    String? address,
    bool? hasActiveGame,
    DateTime? lastSeen,
    int? hostPort,
    String? gameId,
    String? gameTitle,
    bool clearHostPort = false,
    bool clearGameId = false,
    bool clearGameTitle = false,
  }) {
    return DiscoveredPeer(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      address: address ?? this.address,
      hasActiveGame: hasActiveGame ?? this.hasActiveGame,
      lastSeen: lastSeen ?? this.lastSeen,
      hostPort: clearHostPort ? null : hostPort ?? this.hostPort,
      gameId: clearGameId ? null : gameId ?? this.gameId,
      gameTitle: clearGameTitle ? null : gameTitle ?? this.gameTitle,
    );
  }
}
