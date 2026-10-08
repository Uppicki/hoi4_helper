import 'telemetry_log.dart';
import 'world_state.dart';

/// A display-only projection of an unverified telemetry observation.
/// It has no save identity and must not be treated as a completed save.
WorldStateSnapshot telemetryDisplaySnapshot(
  TelemetryObservation? observation, {
  required DateTime readAt,
}) {
  return WorldStateSnapshot(
    sourceDescription: 'Телеметрия',
    readAt: readAt,
    gameDate: observation == null
        ? null
        : parseTelemetryGameDate(observation.gameDate),
    playerTag: observation?.playerTag,
  );
}

GameDate? parseTelemetryGameDate(String code) {
  final match = RegExp(
    r'^(\d{4})\.(\d{2})\.(\d{2})\.(\d{2})$',
  ).firstMatch(code);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  const daysByMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (year < 1 ||
      year > 9999 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > daysByMonth[month - 1] ||
      hour > 23) {
    return null;
  }
  return GameDate(year, month, day, hour);
}
