typedef JsonMap = Map<String, Object?>;

String _asString(Object? value, {String fallback = ''}) {
  return value is String ? value : fallback;
}

DateTime? _asDateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

class PlayerEntry {
  const PlayerEntry({
    required this.id,
    required this.name,
    this.claimedBy,
    this.joinedAt,
  });

  final String id;
  final String name;
  final String? claimedBy;
  final DateTime? joinedAt;

  PlayerEntry copyWith({
    String? id,
    String? name,
    String? claimedBy,
    DateTime? joinedAt,
    bool clearClaimedBy = false,
    bool clearJoinedAt = false,
  }) {
    return PlayerEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      claimedBy: clearClaimedBy ? null : claimedBy ?? this.claimedBy,
      joinedAt: clearJoinedAt ? null : joinedAt ?? this.joinedAt,
    );
  }

  JsonMap toJson() => {
    'id': id,
    'name': name,
    'claimedBy': claimedBy,
    'joinedAt': joinedAt?.toIso8601String(),
  };

  factory PlayerEntry.fromJson(JsonMap json) {
    return PlayerEntry(
      id: _asString(json['id']),
      name: _asString(json['name']),
      claimedBy: json['claimedBy'] is String
          ? json['claimedBy'] as String
          : null,
      joinedAt: _asDateTime(json['joinedAt']),
    );
  }
}

class EggEntry {
  const EggEntry({
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

  EggEntry copyWith({
    String? id,
    String? playerId,
    String? hideSpotId,
    int? order,
    DateTime? foundAt,
    bool clearFoundAt = false,
  }) {
    return EggEntry(
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

  factory EggEntry.fromJson(JsonMap json) {
    return EggEntry(
      id: _asString(json['id']),
      playerId: _asString(json['playerId']),
      hideSpotId: _asString(json['hideSpotId']),
      order: json['order'] is int ? json['order'] as int : 0,
      foundAt: _asDateTime(json['foundAt']),
    );
  }
}

class GameSession {
  const GameSession({
    required this.id,
    required this.title,
    required this.hostName,
    required this.players,
    required this.eggs,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
  });

  final String id;
  final String title;
  final String hostName;
  final List<PlayerEntry> players;
  final List<EggEntry> eggs;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String status;

  bool get isActive => status == 'active';

  PlayerEntry? playerById(String playerId) {
    for (final player in players) {
      if (player.id == playerId) {
        return player;
      }
    }
    return null;
  }

  List<EggEntry> eggsForPlayer(String playerId) {
    final result = eggs.where((egg) => egg.playerId == playerId).toList();
    result.sort((left, right) => left.order.compareTo(right.order));
    return result;
  }

  GameSession copyWith({
    String? id,
    String? title,
    String? hostName,
    List<PlayerEntry>? players,
    List<EggEntry>? eggs,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? status,
  }) {
    return GameSession(
      id: id ?? this.id,
      title: title ?? this.title,
      hostName: hostName ?? this.hostName,
      players: players ?? this.players,
      eggs: eggs ?? this.eggs,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
    );
  }

  JsonMap toJson() => {
    'id': id,
    'title': title,
    'hostName': hostName,
    'players': players.map((player) => player.toJson()).toList(),
    'eggs': eggs.map((egg) => egg.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status,
  };

  factory GameSession.fromJson(JsonMap json) {
    final rawPlayers = json['players'] is List
        ? json['players'] as List<Object?>
        : const [];
    final rawEggs = json['eggs'] is List
        ? json['eggs'] as List<Object?>
        : const [];
    return GameSession(
      id: _asString(json['id']),
      title: _asString(json['title']),
      hostName: _asString(json['hostName']),
      players: [
        for (final raw in rawPlayers)
          if (raw is JsonMap) PlayerEntry.fromJson(raw),
      ],
      eggs: [
        for (final raw in rawEggs)
          if (raw is JsonMap) EggEntry.fromJson(raw),
      ],
      createdAt: _asDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _asDateTime(json['updatedAt']) ?? DateTime.now(),
      status: _asString(json['status'], fallback: 'active'),
    );
  }
}

class EggDraft {
  const EggDraft({required this.playerName, required this.hideSpotId});

  final String playerName;
  final String hideSpotId;
}
