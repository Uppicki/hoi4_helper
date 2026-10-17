import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/player_world.dart';
import 'package:hoi4_helper/core/player_world_knowledge.dart';
import 'package:hoi4_helper/core/telemetry_catalog.dart';
import 'package:hoi4_helper/core/telemetry_log.dart';

void main() {
  test(
    'real anonymized V3 peace frame is accepted only after its end',
    () async {
      final fixture = File('test/fixtures/telemetry_v3_peace.txt');
      final lines = (await fixture.readAsString()).trimRight().split('\n');
      expect(lines.length, 21);
      final folder = await Directory.systemTemp.createTemp('hoi4-real-v3-');
      addTearDown(() => folder.delete(recursive: true));
      final log = File('${folder.path}${Platform.pathSeparator}game.log');
      await log.writeAsString('${lines.take(lines.length - 1).join('\n')}\n');
      final reader = TelemetryLogReader(log);

      final incomplete = await reader.poll();
      expect(incomplete.latest, isNull);
      expect(incomplete.status, TelemetryStreamStatus.incompleteFrame);
      await log.writeAsString('${lines.last}\n', mode: FileMode.append);
      final complete = await reader.poll();
      final observation = complete.latest!;
      expect(complete.receivedNewLine, isTrue);
      expect(observation.schemaVersion, 3);
      expect(observation.gameDate, '1936.01.05.24');
      expect(observation.playerTag, 'ALB');
      expect(observation.manpower, 0);
      expect(observation.values.length, telemetryMetrics.length);
      expect(observation.values.values, everyElement(0));
      expect(observation.invalidKeys, isEmpty);
      for (final key in telemetryMetrics.keys) {
        expect(observation.status(key), TelemetryValueStatus.value);
      }

      final world = projectPlayerWorld(observation).observation!;
      expect(world.countries, {'ALB'});
      expect(world.relations, isEmpty);
      expect(world.atWarWith('ETH').status, PlayerKnowledgeStatus.unknown);
      expect(world.countriesCoverage, 'partial');
      expect(world.gameDate, observation.gameDate);
      expect(world.receivedAt, observation.receivedAt);
      expect(world.campaignId, isNull);
      expect(world.saveId, isNull);
      expect(observation.withoutRawWorld().rawWorld, isNull);
      final waiting = await reader.poll();
      expect(waiting.latest, same(observation));
      expect(waiting.status, TelemetryStreamStatus.waitingNextDay);
    },
  );

  test('real anonymized V3 war frame requires its declared opponent', () async {
    final lines = (await File(
      'test/fixtures/telemetry_v3_war.txt',
    ).readAsString()).trimRight().split('\n');
    expect(lines.length, 22);
    final folder = await Directory.systemTemp.createTemp('hoi4-real-v3-war-');
    addTearDown(() => folder.delete(recursive: true));
    final log = File('${folder.path}${Platform.pathSeparator}game.log');
    final withoutOpponent = lines.where(
      (line) => !line.contains('|phase=relation|'),
    );
    await log.writeAsString('${withoutOpponent.join('\n')}\n');
    final reader = TelemetryLogReader(log);
    final incomplete = await reader.poll();
    expect(incomplete.latest, isNull);
    expect(incomplete.status, TelemetryStreamStatus.incompleteFrame);

    await log.writeAsString('${lines.join('\n')}\n', mode: FileMode.append);
    final complete = await reader.poll();
    final observation = complete.latest!;
    expect(complete.receivedNewLine, isTrue);
    expect(observation.schemaVersion, 3);
    expect(observation.gameDate, '1936.01.06.09');
    expect(observation.playerTag, 'ALB');
    expect(observation.manpower, 0);
    expect(observation.values.length, telemetryMetrics.length);
    expect(observation.values.values, everyElement(0));
    for (final key in telemetryMetrics.keys) {
      expect(observation.status(key), TelemetryValueStatus.value);
    }
    final knowledge = projectPlayerWorld(observation);
    expect(knowledge.availability, PlayerWorldAvailability.ready);
    final world = knowledge.observation!;
    expect(world.countries, {'ALB', 'BUL'});
    expect(world.relations.single.otherTag, 'BUL');
    expect(world.atWarWith('BUL').status, PlayerKnowledgeStatus.value);
    expect(world.atWarWith('BUL').value, isTrue);
    expect(world.atWarWith('ETH').status, PlayerKnowledgeStatus.unknown);
    expect(
      world.relations.single.inFactionWithPlayer.status,
      PlayerKnowledgeStatus.unsupported,
    );
    expect(world.gameDate, observation.gameDate);
    expect(world.receivedAt, observation.receivedAt);
    expect(world.campaignId, isNull);
    expect(world.saveId, isNull);
    expect(observation.withoutRawWorld().rawWorld, isNull);
  });
}
