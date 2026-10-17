import 'dart:convert';
import 'dart:io';

import 'package:hoi4_helper/core/telemetry_log.dart';
import 'package:hoi4_helper/core/telemetry_snapshot.dart';
import 'package:hoi4_helper/core/player_world_knowledge.dart';

/// Read-only smoke check against the user's installed mod, without dumping
/// metric values or copying game logs into the repository.
Future<void> main() async {
  final file = TelemetryLogReader.findDefaultLog();
  if (file == null) {
    stderr.writeln('game.log не найден.');
    exitCode = 1;
    return;
  }
  final result = await TelemetryLogReader(file).poll();
  final observation = result.latest;
  if (observation == null) {
    stderr.writeln('Полное наблюдение не прочитано: ${result.status.name}');
    exitCode = 1;
    return;
  }
  final knowledge = projectPlayerWorld(observation);
  final snapshot = telemetryDisplaySnapshot(
    observation.withoutRawWorld(),
    readAt: DateTime.now(),
  );
  stdout.writeln(
    jsonEncode({
      'version': observation.schemaVersion,
      'date': observation.gameDate,
      'country': observation.playerTag,
      'metrics': observation.values.length,
      'invalid': observation.invalidKeys.length,
      'status': result.status.name,
      'historical': result.historical,
      'displayDate': snapshot.gameDate?.toString(),
      'worldStatus': knowledge.availability.name,
      'opponents': knowledge.observation?.relations.length,
    }),
  );
  if (snapshot.gameDate == null) exitCode = 1;
}
