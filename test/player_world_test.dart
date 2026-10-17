import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/player_world.dart';
import 'package:hoi4_helper/core/player_world_knowledge.dart';
import 'package:hoi4_helper/core/telemetry_catalog.dart';
import 'package:hoi4_helper/core/telemetry_log.dart';

import '../tool/telemetry_mod_builder.dart';

String row(String body, {String date = '1936.01.05.24', int version = 3}) =>
    '[23:36:38][$date][effectbase.cpp:1783]: HOI4_HELPER_V$version|$body\n';

String begin({String policy = 'own_war_participants_v1'}) => row(
  'phase=begin|tag=ALB|parts=1|manpower=0|world=player_war_opponents|policy=$policy',
);
String data() => row('phase=data|tag=ALB|part=0|political_power=0');
String relation(String tag, {String war = '1'}) =>
    row('phase=relation|tag=ALB|other=$tag|at_war=$war');
String end(int count) => row('phase=end|tag=ALB|parts=1|enemies=$count');

Future<File> logFile() async {
  final folder = await Directory.systemTemp.createTemp('hoi4-world-');
  addTearDown(() => folder.delete(recursive: true));
  return File('${folder.path}${Platform.pathSeparator}game.log');
}

TelemetryObservation source({
  String policy = PlayerWorldObservation.warPolicyId,
  List<RawPlayerRelation>? relations,
  int version = 3,
}) => TelemetryObservation(
  gameDate: '1936.01.05.24',
  playerTag: 'ALB',
  manpower: 0,
  schemaVersion: version,
  receivedAt: DateTime(2026, 10, 17, 12, 34),
  logSource: 'synthetic-game.log',
  rawWorld: version == 3
      ? RawPlayerWorld(
          scopeId: PlayerWorldObservation.scopeId,
          policyId: policy,
          relations:
              relations ??
              [
                RawPlayerRelation('ITA', {'at_war': '1'}),
              ],
        )
      : null,
);

void main() {
  test(
    'boolean zero remains false; absent and invalid values carry no payload',
    () {
      final no = PlayerKnowledgeBool.fromWire('0');
      expect(no.status, PlayerKnowledgeStatus.value);
      expect(no.value, isFalse);
      expect(PlayerKnowledgeBool.fromWire('1').value, isTrue);
      expect(
        PlayerKnowledgeBool.fromWire(null).status,
        PlayerKnowledgeStatus.missing,
      );
      expect(
        PlayerKnowledgeBool.fromWire('false').status,
        PlayerKnowledgeStatus.invalid,
      );
      for (final value in [
        PlayerKnowledgeBool.unknown,
        PlayerKnowledgeBool.missing,
        PlayerKnowledgeBool.unsupported,
        PlayerKnowledgeBool.invalid,
      ]) {
        expect(value.value, isNull);
      }
    },
  );

  test(
    'knowledge admits only own-war membership and ignores hidden raw fields',
    () {
      PlayerWorldObservation view(String hidden) => projectPlayerWorld(
        source(
          relations: [
            RawPlayerRelation('ITA', {
              'at_war': '1',
              'enemy_manpower': hidden,
              'ai_war_plan': hidden,
            }),
          ],
        ),
      ).observation!;
      final first = view('0');
      final second = view('99999999');
      expect(first.countries, {'ALB', 'ITA'});
      expect(second.countries, first.countries);
      expect(
        second.relations.map((r) => r.otherTag),
        first.relations.map((r) => r.otherTag),
      );
      expect(first.atWarWith('ITA').value, isTrue);
      expect(second.atWarWith('ITA').value, first.atWarWith('ITA').value);
      expect(first.atWarWith('GER').status, PlayerKnowledgeStatus.unknown);
      expect(
        first.relations.single.inFactionWithPlayer.status,
        PlayerKnowledgeStatus.unsupported,
      );
      expect(first.countriesCoverage, 'partial');
      expect(first.relationsCoverage, 'complete');
      expect(first.gameDate, '1936.01.05.24');
      expect(first.logSource, 'synthetic-game.log');
      expect(first.campaignId, isNull);
      expect(first.saveId, isNull);
      expect(first.gameDataId, isNull);
      expect(() => first.relations.clear(), throwsUnsupportedError);
    },
  );

  test(
    'unknown rules and invalid membership cannot reveal raw country tags',
    () {
      final unknown = projectPlayerWorld(source(policy: 'unverified_rule'));
      expect(unknown.availability, PlayerWorldAvailability.unknown);
      expect(unknown.observation, isNull);
      for (final raw in ['0', 'bad', '']) {
        final invalid = projectPlayerWorld(
          source(
            relations: [
              RawPlayerRelation('ITA', {'at_war': raw}),
            ],
          ),
        );
        expect(invalid.availability, PlayerWorldAvailability.invalid);
        expect(invalid.observation, isNull);
      }
      expect(
        projectPlayerWorld(
          source(relations: [RawPlayerRelation('ITA', {})]),
        ).observation,
        isNull,
      );
      expect(
        projectPlayerWorld(
          source(
            relations: [
              RawPlayerRelation('ALB', {'at_war': '1'}),
            ],
          ),
        ).observation,
        isNull,
      );
      expect(
        projectPlayerWorld(
          source(
            relations: [
              RawPlayerRelation('ITA', {'at_war': '1'}),
              RawPlayerRelation('ITA', {'at_war': '1'}),
            ],
          ),
        ).observation,
        isNull,
      );
      for (final version in [1, 2]) {
        final old = projectPlayerWorld(source(version: version));
        expect(old.availability, PlayerWorldAvailability.unsupported);
        expect(old.observation, isNull);
      }
    },
  );

  test('missing provenance cannot admit a world section', () {
    final original = source();
    for (final path in <String?>[null, '']) {
      final input = TelemetryObservation(
        gameDate: original.gameDate,
        playerTag: original.playerTag,
        manpower: 0,
        schemaVersion: 3,
        receivedAt: original.receivedAt,
        rawWorld: original.rawWorld,
        logSource: path,
      );
      final projected = projectPlayerWorld(input);
      expect(projected.availability, PlayerWorldAvailability.unknown);
      expect(projected.observation, isNull);
    }
    final noReceipt = TelemetryObservation(
      gameDate: original.gameDate,
      playerTag: original.playerTag,
      manpower: 0,
      schemaVersion: 3,
      logSource: original.logSource,
      rawWorld: original.rawWorld,
    );
    expect(projectPlayerWorld(noReceipt).observation, isNull);
  });

  test(
    'new unknown policy and peace replace the previous opponent list',
    () async {
      final file = await logFile();
      await file.writeAsString(begin() + data() + relation('ITA') + end(1));
      final reader = TelemetryLogReader(file);
      expect(
        projectPlayerWorld((await reader.poll()).latest).observation!.countries,
        {'ALB', 'ITA'},
      );
      final unknown =
          (begin(policy: 'unverified') + data() + relation('ITA') + end(1))
              .replaceAll('1936.01.05.24', '1936.01.06.24');
      await file.writeAsString(unknown, mode: FileMode.append);
      final noKnowledge = projectPlayerWorld((await reader.poll()).latest);
      expect(noKnowledge.availability, PlayerWorldAvailability.unknown);
      expect(noKnowledge.observation, isNull);
      final peace = (begin() + data() + end(0)).replaceAll(
        '1936.01.05.24',
        '1936.01.07.24',
      );
      await file.writeAsString(peace, mode: FileMode.append);
      final latest = projectPlayerWorld(
        (await reader.poll()).latest,
      ).observation!;
      expect(latest.countries, {'ALB'});
      expect(latest.relations, isEmpty);
      expect(latest.atWarWith('ITA').status, PlayerKnowledgeStatus.unknown);
    },
  );

  test(
    'V3 publishes metrics and world only after parts, rows and matching end',
    () async {
      final file = await logFile();
      await file.writeAsString('');
      final reader = TelemetryLogReader(file);
      await reader.poll();
      await file.writeAsString(
        begin() + data() + relation('ITA'),
        mode: FileMode.append,
      );
      expect((await reader.poll()).latest, isNull);
      await file.writeAsString(end(1), mode: FileMode.append);
      final result = await reader.poll();
      final observation = result.latest!;
      expect(observation.schemaVersion, 3);
      expect(observation.value('political_power'), 0);
      expect(result.receivedNewLine, isTrue);
      final world = projectPlayerWorld(observation).observation!;
      expect(world.countries, {'ALB', 'ITA'});
      expect(world.receivedAt, observation.receivedAt);
      expect(world.atWarWith('ITA').value, isTrue);
      expect(world.atWarWith('USA').value, isNull);
    },
  );

  test(
    'empty V3 scope is peace, not an empty world; V2 cannot carry it forward',
    () async {
      final file = await logFile();
      await file.writeAsString(begin() + data() + end(0));
      final reader = TelemetryLogReader(file);
      final peace = projectPlayerWorld(
        (await reader.poll()).latest,
      ).observation!;
      expect(peace.relations, isEmpty);
      expect(peace.countries, {'ALB'});
      expect(peace.countriesCoverage, 'partial');
      expect(peace.atWarWith('ITA').status, PlayerKnowledgeStatus.unknown);
      await file.writeAsString(
        row(
              'phase=begin|tag=ALB|parts=1|manpower=0',
              date: '1936.01.06.24',
              version: 2,
            ) +
            row(
              'phase=data|tag=ALB|part=0|political_power=5',
              date: '1936.01.06.24',
              version: 2,
            ) +
            row('phase=end|tag=ALB|parts=1', date: '1936.01.06.24', version: 2),
        mode: FileMode.append,
      );
      final legacy = (await reader.poll()).latest!;
      expect(legacy.rawWorld, isNull);
      expect(
        projectPlayerWorld(legacy).availability,
        PlayerWorldAvailability.unsupported,
      );
    },
  );

  test(
    'V3 rejects missing, duplicate, mixed, out-of-scope and count-mismatched rows',
    () async {
      final file = await logFile();
      final invalidFrames = [
        begin() + data() + relation('ITA') + end(0),
        begin() + data() + end(1),
        begin() + data() + relation('ITA') + relation('ITA') + end(2),
        begin() + data() + relation('ALB') + end(1),
        begin() +
            data() +
            row('phase=relation|tag=GER|other=ITA|at_war=1') +
            end(1),
        begin() +
            data() +
            row(
              'phase=relation|tag=ALB|other=ITA|at_war=1',
              date: '1936.01.06.24',
            ) +
            end(1),
        begin() + data() + row('phase=end|tag=ALB|parts=1'),
        begin() + data() + row('phase=end|tag=ALB|parts=1|enemies=-1'),
        begin() + data() + row('phase=end|tag=ALB|parts=1|enemies=bad'),
        begin() +
            row('phase=data|tag=ALB|part=0|political_power=1', version: 2) +
            end(0),
        begin() +
            data() +
            row('phase=relation|tag=ALB|other=ITA|at_war=1', version: 4) +
            end(1),
        begin() + data() + end(0).replaceAll('1936.01.05.24', '1936.11.31.24'),
      ];
      for (final frame in invalidFrames) {
        await file.writeAsString(frame);
        final result = await TelemetryLogReader(file).poll();
        expect(result.latest, isNull, reason: frame);
        expect(result.status, TelemetryStreamStatus.incompleteFrame);
      }
    },
  );

  test(
    'log replacement and country change clear the entire V3 observation',
    () async {
      final file = await logFile();
      await file.writeAsString(begin() + data() + relation('ITA') + end(1));
      final reader = TelemetryLogReader(file);
      expect(
        projectPlayerWorld((await reader.poll()).latest).observation,
        isNotNull,
      );
      await file.writeAsString(
        begin().replaceAll('tag=ALB', 'tag=GER'),
        mode: FileMode.append,
      );
      expect((await reader.poll()).latest, isNull);
      await file.writeAsString(begin() + data());
      expect((await reader.poll()).latest, isNull);
    },
  );

  test('mod builder requires documented commands and participant UI', () {
    const effects =
        '## every_enemy_country\n## set_temp_variable\n## add_to_temp_variable\n';
    const triggers = '## has_war_with\n';
    const interface = 'attacker_participants defender_participants';
    validateWarOverviewSupport(
      effects: effects,
      triggers: triggers,
      warInterface: interface,
    );
    expect(
      () => validateWarOverviewSupport(
        effects: effects.replaceAll('every_enemy_country', 'every_country'),
        triggers: triggers,
        warInterface: interface,
      ),
      throwsFormatException,
    );
    expect(
      () => validateWarOverviewSupport(
        effects: effects,
        triggers: '',
        warInterface: interface,
      ),
      throwsFormatException,
    );
    expect(
      () => validateWarOverviewSupport(
        effects: effects,
        triggers: triggers,
        warInterface: '',
      ),
      throwsFormatException,
    );
  });

  test(
    'generated V3 templates agree with reader for positive and empty scopes',
    () async {
      final mod = buildTelemetryMod(telemetryMetrics.values.toList());
      final templates = RegExp(
        r'\blog = "([^"]+)"',
      ).allMatches(mod).map((m) => m.group(1)!).toList();
      final file = await logFile();
      for (final hasEnemy in [false, true]) {
        final rendered = templates
            .where((t) => hasEnemy || !t.contains('phase=relation'))
            .map(
              (t) => row(
                t
                    .replaceFirst('HOI4_HELPER_V3|', '')
                    .replaceAll('[ROOT.GetTag]', 'ALB')
                    .replaceAll('[THIS.GetTag]', 'ITA')
                    .replaceAll('[ROOT.GetManpower]', '0')
                    .replaceAll('[?hh_war_opponents|0]', hasEnemy ? '1' : '0')
                    .replaceAll(RegExp(r'\[\?[^\]]+\]'), '1'),
              ),
            )
            .join();
        await file.writeAsString(rendered);
        final full = (await TelemetryLogReader(file).poll()).latest!;
        expect(full.values.length, telemetryMetrics.length);
        final world = projectPlayerWorld(full).observation!;
        expect(world.relations.length, hasEnemy ? 1 : 0);
      }
      final foreignScope = mod.substring(
        mod.indexOf('        every_enemy_country'),
      );
      expect(foreignScope, contains('limit = { has_war_with = ROOT }'));
      expect(
        foreignScope,
        contains('tag=[ROOT.GetTag]|other=[THIS.GetTag]|at_war=1'),
      );
      expect(foreignScope, isNot(contains('value = manpower')));
    },
  );
}
