import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/telemetry_log.dart';
import 'package:hoi4_helper/core/game_localization.dart';
import 'package:hoi4_helper/core/telemetry_snapshot.dart';
import 'package:hoi4_helper/ui/app_router.dart';
import 'package:hoi4_helper/ui/saves_screen.dart';
import 'package:hoi4_helper/ui/source_screen.dart';
import 'package:hoi4_helper/ui/telemetry_screen.dart';
import 'package:hoi4_helper/ui/world_screen.dart';

class EmptyLocalization extends GameLocalizationRepository {
  @override
  Future<GameLocalization> load(GameLanguage language) async =>
      GameLocalization(language, const {});
}

void main() {
  testWidgets('telemetry is the default and precedes saves in sources', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: AppRouter(
          telemetryReader: TelemetryLogReader(File('missing-telemetry.log')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TelemetryScreen), findsOneWidget);
    expect(find.byType(WorldScreen), findsOneWidget);
    expect(find.text('НАБЛЮДЕНИЕ МОДА'), findsOneWidget);
    expect(find.byType(SavesScreen), findsNothing);

    await tester.tap(find.byKey(const Key('change-source-from-telemetry')));
    await tester.pumpAndSettle();
    expect(find.byType(SourceScreen), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('telemetry-source'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('file-source'))).dy),
    );

    await tester.tap(find.byKey(const Key('file-source')));
    await tester.pumpAndSettle();
    expect(find.byType(SavesScreen), findsOneWidget);
    expect(find.text('ИСТОЧНИК 02'), findsOneWidget);

    await tester.tap(find.byKey(const Key('change-source-from-saves')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('telemetry-source')));
    await tester.pumpAndSettle();
    expect(find.byType(TelemetryScreen), findsOneWidget);
    expect(find.byType(WorldScreen), findsOneWidget);
    expect(find.byType(SavesScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('telemetry fills only verified fields on the main dashboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const first = TelemetryObservation(
      gameDate: '1936.01.02.02',
      playerTag: 'ALB',
      manpower: 5562,
    );
    Widget dashboard(TelemetryObservation observation) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: WorldScreen(
        snapshot: telemetryDisplaySnapshot(
          observation,
          readAt: DateTime(2026, 10, 8),
        ),
        telemetryMode: true,
        telemetryManpower: observation.manpower,
        localizationRepository: EmptyLocalization(),
        onChangeSource: () {},
      ),
    );
    await tester.pumpWidget(dashboard(first));
    await tester.pumpAndSettle();
    expect(find.text('НАБЛЮДЕНИЕ МОДА'), findsOneWidget);
    expect(find.textContaining('1936.01.02 02:00'), findsWidgets);
    expect(find.text('Армейский резерв'), findsOneWidget);
    expect(find.text('5 562'), findsOneWidget);
    expect(find.text('Схема снимка'), findsNothing);

    await tester.pumpWidget(
      dashboard(
        const TelemetryObservation(
          gameDate: '1936.01.03.02',
          playerTag: 'ALB',
          manpower: 5590,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5 590'), findsOneWidget);
    expect(find.text('5 562'), findsNothing);
  });
}
