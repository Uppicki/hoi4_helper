import 'player_world.dart';
import 'telemetry_log.dart';

final _countryTag = RegExp(r'^[A-Z0-9]{3}$');

/// Only direct, positive membership in the player's own wars admits a country.
/// Other source fields are deliberately absent from the permitted projection.
PlayerWorldKnowledge projectPlayerWorld(TelemetryObservation? source) {
  if (source == null) {
    return const PlayerWorldKnowledge.unavailable(
      PlayerWorldAvailability.unavailable,
    );
  }
  if (source.schemaVersion < 3) {
    return const PlayerWorldKnowledge.unavailable(
      PlayerWorldAvailability.unsupported,
    );
  }
  final raw = source.rawWorld;
  if (source.schemaVersion != 3 || raw == null) {
    return const PlayerWorldKnowledge.unavailable(
      PlayerWorldAvailability.invalid,
    );
  }
  if (raw.scopeId != PlayerWorldObservation.scopeId ||
      raw.policyId != PlayerWorldObservation.warPolicyId ||
      source.receivedAt == null ||
      source.logSource == null ||
      source.logSource!.trim().isEmpty ||
      !_countryTag.hasMatch(source.playerTag) ||
      !isValidTelemetryGameDate(source.gameDate)) {
    return const PlayerWorldKnowledge.unavailable(
      PlayerWorldAvailability.unknown,
    );
  }

  final relations = <PlayerRelationKnowledge>[];
  final seen = <String>{};
  for (final item in raw.relations) {
    final war = PlayerKnowledgeBool.fromWire(item.fields['at_war']);
    if (!_countryTag.hasMatch(item.otherTag) ||
        item.otherTag == source.playerTag ||
        !seen.add(item.otherTag) ||
        war.status != PlayerKnowledgeStatus.value ||
        war.value != true) {
      // A negative or unknown assertion cannot prove existence through the
      // narrow "own war opponents" rule. Do not expose even the raw TAG.
      return const PlayerWorldKnowledge.unavailable(
        PlayerWorldAvailability.invalid,
      );
    }
    relations.add(
      PlayerRelationKnowledge(otherTag: item.otherTag, atWarWithPlayer: war),
    );
  }
  relations.sort((left, right) => left.otherTag.compareTo(right.otherTag));
  return PlayerWorldKnowledge.ready(
    PlayerWorldObservation(
      gameDate: source.gameDate,
      playerTag: source.playerTag,
      receivedAt: source.receivedAt!,
      logSource: source.logSource!,
      visibilityPolicyId: raw.policyId,
      relations: relations,
    ),
  );
}
