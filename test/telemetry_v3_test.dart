import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/game_localization.dart';
import 'package:hoi4_helper/core/telemetry_log.dart';
import 'package:hoi4_helper/core/telemetry_snapshot.dart';
import 'package:hoi4_helper/ui/telemetry_screen.dart';

String _line(String body, {int version = 3}) =>
    '[10:00:00][1936.03.05.24][effectbase.cpp:1]: HOI4_HELPER_V$version|$body\n';

String _begin() => _line(
  'phase=begin|tag=GER|parts=1|manpower=100|world=player_war_opponents|policy=own_war_participants_v1',
);
String _data({int version = 3}) => _line(
  'phase=data|tag=GER|part=0|stability=0.8|available_civ=0|civilian_factories=50',
  version: version,
);
String _end([int enemies = 0]) =>
    _line('phase=end|tag=GER|parts=1|enemies=$enemies');

class _EmptyNames extends GameLocalizationRepository {
  @override
  Future<GameLocalization> load(GameLanguage language) async =>
      GameLocalization(language, const {});
}

class _ReadyReader extends TelemetryLogReader {
  _ReadyReader(this.result) : super(File('unused'));
  final TelemetryLogPoll result;

  @override
  Future<TelemetryLogPoll> poll() async => result;
}

void main() {
  late Directory folder;
  late File file;
  setUp(() {
    folder = Directory.systemTemp.createTempSync('hoi-v3-compat-');
    file = File('${folder.path}/game.log');
  });
  tearDown(() => folder.deleteSync(recursive: true));

  test(
    'V3 publishes numeric values after a complete frame, including hour 24',
    () async {
      await file.writeAsString('');
      final reader = TelemetryLogReader(file);
      await reader.poll();
      await file.writeAsString(_begin() + _data(), mode: FileMode.append);
      final partial = await reader.poll();
      expect(partial.latest, isNull);
      expect(partial.status, TelemetryStreamStatus.incompleteFrame);
      await file.writeAsString(_end(), mode: FileMode.append);
      final accepted = await reader.poll();
      expect(accepted.receivedNewLine, isTrue);
      expect(accepted.historical, isFalse);
      expect(accepted.latest?.schemaVersion, 3);
      expect(accepted.latest?.value('stability'), 0.8);
      expect(accepted.latest?.value('available_civ'), 0);
      expect(accepted.latest?.status('fuel'), TelemetryValueStatus.missing);
      expect(
        telemetryDisplaySnapshot(
          accepted.latest,
          readAt: DateTime(2026),
        ).gameDate?.hour,
        24,
      );
      expect(
        (await reader.poll()).status,
        TelemetryStreamStatus.waitingNextDay,
      );
    },
  );

  test(
    'V3 relation payload cannot enter or affect numeric dashboard values',
    () async {
      Future<TelemetryObservation> read(String hidden) async {
        await file.writeAsString(
          _begin() +
              _data() +
              _line(
                'phase=relation|tag=GER|other=ITA|at_war=1|hidden_value=$hidden',
              ) +
              _end(1),
        );
        return (await TelemetryLogReader(file).poll()).latest!;
      }

      final first = await read('123');
      final second = await read('unknown');
      expect(second.values, first.values);
      expect(second.invalidKeys, first.invalidKeys);
      expect(second.values.containsKey('hidden_value'), isFalse);
      expect(second.campaignId, isNull);
      expect(second.saveId, isNull);
    },
  );

  final invalid = <String, String Function()>{
    'mixed V2 data in V3': () => _begin() + _data(version: 2) + _end(),
    'missing relation count': () =>
        _begin() + _data() + _line('phase=end|tag=GER|parts=1'),
    'missing relation': () => _begin() + _data() + _end(1),
    'duplicate relation': () =>
        _begin() +
        _data() +
        _line('phase=relation|tag=GER|other=ITA|at_war=1') +
        _line('phase=relation|tag=GER|other=ITA|at_war=1') +
        _end(2),
    'self relation': () =>
        _begin() +
        _data() +
        _line('phase=relation|tag=GER|other=GER|at_war=1') +
        _end(1),
    'mixed country': () =>
        _begin() +
        _data() +
        _line('phase=relation|tag=ALB|other=ITA|at_war=1') +
        _end(1),
    'mixed date': () =>
        _begin() +
        _data() +
        _line(
          'phase=relation|tag=GER|other=ITA|at_war=1',
        ).replaceFirst('1936.03.05.24', '1936.03.04.24') +
        _end(1),
    'incomplete header': () =>
        _begin().replaceFirst('|policy=own_war_participants_v1', '') +
        _data() +
        _end(),
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key}', () async {
      await file.writeAsString(entry.value());
      final result = await TelemetryLogReader(file).poll();
      expect(result.latest, isNull);
      expect(result.status, TelemetryStreamStatus.incompleteFrame);
    });
  }

  testWidgets(
    'V3 read from a log reaches the telemetry screen with date and values',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final result = await tester.runAsync(() async {
        await file.writeAsString(_begin() + _data() + _end());
        return TelemetryLogReader(file).poll();
      });
      final language = ValueNotifier(GameLanguage.russian);
      addTearDown(language.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: TelemetryScreen(
            language: language,
            onChangeSource: () {},
            reader: _ReadyReader(result!),
            localizationRepository: _EmptyNames(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Стабильность: 80.0 %'), findsOneWidget);
      final lastComplete = tester.widget<Text>(
        find.byKey(const Key('telemetry-last-complete')),
      );
      expect(lastComplete.data, contains('1936.03.05.24'));
      expect(find.text('Ожидание следующего игрового дня.'), findsOneWidget);
      expect(find.byKey(const Key('focus-summary')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
