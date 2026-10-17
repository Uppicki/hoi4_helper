import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/game_localization.dart';
import 'package:hoi4_helper/core/telemetry_log.dart';
import 'package:hoi4_helper/core/telemetry_snapshot.dart';
import 'package:hoi4_helper/ui/world_screen.dart';

class EmptyLocalization extends GameLocalizationRepository {
  @override
  Future<GameLocalization> load(GameLanguage language) async =>
      GameLocalization(language, const {});
}

void main() {
  testWidgets('stream states explain absence, partial input and waiting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> show(TelemetryStreamStatus status) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorldScreen(
            snapshot: telemetryDisplaySnapshot(null, readAt: DateTime(2026)),
            telemetryMode: true,
            telemetryStatus: status,
            localizationRepository: EmptyLocalization(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(TelemetryStreamStatus.noLog);
    expect(find.text('Лог game.log не найден.'), findsOneWidget);
    await show(TelemetryStreamStatus.noModRecords);
    expect(find.text('В логе нет записей мода.'), findsOneWidget);
    await show(TelemetryStreamStatus.incompleteFrame);
    expect(
      find.text('Неполный или повреждённый набор; ждём полный.'),
      findsOneWidget,
    );
    expect(find.textContaining('на паузе обновления нет'), findsOneWidget);
  });

  testWidgets('historical complete observation shows date and receipt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final observation = TelemetryObservation(
      gameDate: '1936.12.31.02',
      playerTag: 'ALB',
      manpower: 42,
      receivedAt: DateTime(2026, 10, 16, 12, 34),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorldScreen(
          snapshot: telemetryDisplaySnapshot(
            observation,
            readAt: DateTime(2026, 10, 16),
          ),
          telemetryMode: true,
          telemetry: observation,
          telemetryStatus: TelemetryStreamStatus.waitingNextDay,
          telemetryHistorical: true,
          localizationRepository: EmptyLocalization(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ожидание следующего игрового дня.'), findsOneWidget);
    expect(
      find.textContaining('1936.12.31.02 · получено 16.10.2026 12:34'),
      findsOneWidget,
    );
    expect(
      find.textContaining('текущая игровая сессия не подтверждена'),
      findsOneWidget,
    );
  });
}
