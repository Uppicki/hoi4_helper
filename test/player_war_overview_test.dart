import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/game_localization.dart';
import 'package:hoi4_helper/core/player_world.dart';
import 'package:hoi4_helper/core/telemetry_log.dart';
import 'package:hoi4_helper/ui/telemetry_screen.dart';
import 'package:hoi4_helper/ui/world_screen.dart';

class EmptyLocalization extends GameLocalizationRepository {
  @override
  Future<GameLocalization> load(GameLanguage language) async =>
      GameLocalization(language, const {'ITA': 'Италия'});
}

class ScriptedReader extends TelemetryLogReader {
  ScriptedReader(this.result) : super(File('unused'));
  TelemetryLogPoll result;

  @override
  Future<TelemetryLogPoll> poll() async => result;
}

TelemetryLogPoll record({
  bool peace = false,
  String policy = PlayerWorldObservation.warPolicyId,
  int version = 3,
}) => TelemetryLogPoll(
  latest: TelemetryObservation(
    gameDate: '1936.01.05.24',
    playerTag: 'ALB',
    manpower: 0,
    schemaVersion: version,
    receivedAt: DateTime(2026, 10, 17, 12, 34),
    logSource: 'synthetic.log',
    rawWorld: version == 3
        ? RawPlayerWorld(
            scopeId: PlayerWorldObservation.scopeId,
            policyId: policy,
            relations: peace
                ? []
                : [
                    RawPlayerRelation('ITA', {
                      'at_war': '1',
                      'secret': '99999999',
                    }),
                  ],
          )
        : null,
  ),
  receivedNewLine: false,
  historical: true,
  status: TelemetryStreamStatus.waitingNextDay,
);

void main() {
  testWidgets(
    'real telemetry screen projects own wars and clears on stream loss',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reader = ScriptedReader(record());
      final language = ValueNotifier(GameLanguage.russian);
      addTearDown(language.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TelemetryScreen(
            language: language,
            onChangeSource: () {},
            reader: reader,
            localizationRepository: EmptyLocalization(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Войны игрока'), findsOneWidget);
      expect(find.byKey(const Key('focus-summary')), findsOneWidget);
      expect(find.text('Италия · ITA — Война с игроком'), findsOneWidget);
      expect(find.textContaining('99999999'), findsNothing);
      expect(
        tester
            .widget<WorldScreen>(find.byType(WorldScreen))
            .telemetry
            ?.rawWorld,
        isNull,
      );
      expect(
        find.textContaining('не полный перечень стран мира'),
        findsOneWidget,
      );
      expect(
        find.textContaining('текущая игровая сессия не подтверждена'),
        findsOneWidget,
      );
      reader.result = const TelemetryLogPoll(
        latest: null,
        receivedNewLine: false,
        historical: false,
        status: TelemetryStreamStatus.noLog,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Италия · ITA — Война с игроком'), findsNothing);
      expect(find.text('Ожидаем полное наблюдение мода.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('peace, unverified policy and V2 remain distinct on screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reader = ScriptedReader(record(peace: true));
    final language = ValueNotifier(GameLanguage.russian);
    addTearDown(language.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TelemetryScreen(
          language: language,
          onChangeSource: () {},
          reader: reader,
          localizationRepository: EmptyLocalization(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('В этом полном наблюдении стран-противников нет.'),
      findsOneWidget,
    );
    reader.result = record(policy: 'unverified');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      find.text('Происхождение или правило видимости списка не подтверждено.'),
      findsOneWidget,
    );
    expect(find.textContaining('Италия'), findsNothing);
    reader.result = record(version: 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      find.text('Этот формат мода не передаёт список противников.'),
      findsOneWidget,
    );
    expect(find.textContaining('Италия'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
