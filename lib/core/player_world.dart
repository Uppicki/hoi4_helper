enum PlayerKnowledgeStatus { value, unknown, missing, unsupported, invalid }

/// A boolean in the permitted player view. Non-values never carry a payload.
class PlayerKnowledgeBool {
  const PlayerKnowledgeBool._(this.status, this.value);

  static const unknown = PlayerKnowledgeBool._(
    PlayerKnowledgeStatus.unknown,
    null,
  );
  static const missing = PlayerKnowledgeBool._(
    PlayerKnowledgeStatus.missing,
    null,
  );
  static const unsupported = PlayerKnowledgeBool._(
    PlayerKnowledgeStatus.unsupported,
    null,
  );
  static const invalid = PlayerKnowledgeBool._(
    PlayerKnowledgeStatus.invalid,
    null,
  );

  const PlayerKnowledgeBool.known(bool value)
    : this._(PlayerKnowledgeStatus.value, value);

  factory PlayerKnowledgeBool.fromWire(String? raw) => switch (raw) {
    null => missing,
    '0' => const PlayerKnowledgeBool.known(false),
    '1' => const PlayerKnowledgeBool.known(true),
    _ => invalid,
  };

  final PlayerKnowledgeStatus status;
  final bool? value;
}

/// Untrusted source fields. These objects must never be given to the world UI.
class RawPlayerRelation {
  RawPlayerRelation(this.otherTag, Map<String, String> fields)
    : fields = Map.unmodifiable(fields);

  final String otherTag;
  final Map<String, String> fields;
}

class RawPlayerWorld {
  RawPlayerWorld({
    required this.scopeId,
    required this.policyId,
    required Iterable<RawPlayerRelation> relations,
  }) : relations = List.unmodifiable(relations);

  final String scopeId;
  final String policyId;
  final List<RawPlayerRelation> relations;
}

enum PlayerWorldAvailability {
  ready,
  unavailable,
  unsupported,
  unknown,
  invalid,
}

class PlayerRelationKnowledge {
  const PlayerRelationKnowledge({
    required this.otherTag,
    required this.atWarWithPlayer,
  });

  final String otherTag;
  final PlayerKnowledgeBool atWarWithPlayer;
  PlayerKnowledgeBool get inFactionWithPlayer =>
      PlayerKnowledgeBool.unsupported;
  PlayerKnowledgeBool get subjectOfPlayer => PlayerKnowledgeBool.unsupported;
  PlayerKnowledgeBool get overlordOfPlayer => PlayerKnowledgeBool.unsupported;
}

/// The permitted view of one complete frame, not a save or campaign snapshot.
class PlayerWorldObservation {
  PlayerWorldObservation({
    required this.gameDate,
    required this.playerTag,
    required this.receivedAt,
    required this.logSource,
    required this.visibilityPolicyId,
    required Iterable<PlayerRelationKnowledge> relations,
  }) : relations = List.unmodifiable(relations);

  static const schemaVersion = 1;
  static const scopeId = 'player_war_opponents';
  static const warPolicyId = 'own_war_participants_v1';

  final String gameDate;
  final String playerTag;
  final DateTime receivedAt;
  final String logSource;
  final String visibilityPolicyId;
  final List<PlayerRelationKnowledge> relations;

  int get modRecordVersion => 3;
  String? get campaignId => null;
  String? get saveId => null;
  String? get gameDataId => null;
  String get countriesCoverage => 'partial';
  String get relationsCoverage => 'complete';
  List<String> get supportedRelationFields => const ['atWarWithPlayer'];

  Set<String> get countries => Set.unmodifiable([
    playerTag,
    ...relations.map((relation) => relation.otherTag),
  ]);

  /// Absence from the opponent list says nothing about another country.
  PlayerKnowledgeBool atWarWith(String tag) {
    for (final relation in relations) {
      if (relation.otherTag == tag) return relation.atWarWithPlayer;
    }
    return PlayerKnowledgeBool.unknown;
  }
}

class PlayerWorldKnowledge {
  const PlayerWorldKnowledge.unavailable(this.availability)
    : observation = null;

  const PlayerWorldKnowledge.ready(PlayerWorldObservation this.observation)
    : availability = PlayerWorldAvailability.ready;

  final PlayerWorldAvailability availability;
  final PlayerWorldObservation? observation;
}
