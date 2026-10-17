import 'telemetry_log.dart';
import 'world_state.dart';

/// A display-only projection of an unverified telemetry observation.
/// It has no save identity and must not be treated as a completed save.
WorldStateSnapshot telemetryDisplaySnapshot(
  TelemetryObservation? observation, {
  required DateTime readAt,
}) {
  return WorldStateSnapshot(
    sourceDescription: observation?.logSource ?? 'Телеметрия',
    readAt: observation?.receivedAt ?? readAt,
    gameDate: observation == null
        ? null
        : parseTelemetryGameDate(observation.gameDate),
    playerTag: observation?.playerTag,
  );
}

CountryWorldState? telemetryDisplayCountry(TelemetryObservation? observation) {
  if (observation == null) return null;
  return CountryWorldState(
    tag: observation.playerTag,
    availableManpower: observation.manpower,
    stability: observation.value('stability'),
    warSupport: observation.value('war_support'),
    politicalPower: observation.value('political_power'),
    commandPower: observation.value('command_power'),
    researchSlots: observation.count('research_slots'),
    divisionCount: observation.count('divisions'),
    shipCount: observation.count('ships'),
    armyExperience: observation.value('army_xp'),
    airExperience: observation.value('air_xp'),
    civilianFactories: observation.count('civilian_factories'),
    militaryFactories: observation.count('military_factories'),
    dockyards: observation.count('dockyards'),
  );
}

GameDate? parseTelemetryGameDate(String code) {
  final match = RegExp(
    r'^(\d{4})\.(\d{2})\.(\d{2})\.(\d{2})$',
  ).firstMatch(code);
  if (match == null || !isValidTelemetryGameDate(code)) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  return GameDate(year, month, day, hour);
}
