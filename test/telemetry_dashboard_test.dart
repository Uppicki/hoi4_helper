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
  testWidgets('V2 telemetry populates dashboard and detailed tables', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final observation = TelemetryObservation(
      receivedAt: DateTime(2026, 10, 8, 21, 15),
      logSource:
          r'C:\Documents\Paradox Interactive\Hearts of Iron IV\logs\game.log',
      gameDate: '1936.01.03.02',
      playerTag: 'ALB',
      manpower: 5590,
      schemaVersion: 2,
      values: {
        'political_power': 20,
        'stability': 0.42,
        'war_support': 0.31,
        'civilian_factories': 4,
        'military_factories': 8,
        'available_civ': 0,
        'fuel': 3.25,
        'research_slots': 2,
        'researched_count': 6,
        'divisions': 3,
        'ships': 1,
        'navy_xp': 12.5,
        'planes': 24,
        'owned_states': 2,
        'res_steel_balance': -3,
        'eq_infantry_equipment_stock': 50,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: WorldScreen(
          snapshot: telemetryDisplaySnapshot(
            observation,
            readAt: DateTime(2026, 10, 8),
          ),
          telemetryMode: true,
          telemetry: observation,
          localizationRepository: EmptyLocalization(),
          onChangeSource: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save-summary')));
    await tester.pumpAndSettle();
    expect(find.text('Путь журнала'), findsOneWidget);
    expect(
      find.text(
        r'C:\Documents\Paradox Interactive\Hearts of Iron IV\logs\game.log',
      ),
      findsOneWidget,
    );
    expect(find.text('Получено приложением'), findsOneWidget);
    expect(find.text('08.10.2026 21:15'), findsOneWidget);
    expect(find.text('Формат записи мода'), findsOneWidget);
    expect(find.text('Схема наблюдения'), findsOneWidget);
    expect(find.text('Стабильность: 42.0 %'), findsOneWidget);
    expect(find.text('Поддержка войны: 31.0 %'), findsOneWidget);
    expect(find.text('5 590'), findsOneWidget);
    expect(find.text('Доступные фабрики'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text('Топливо, тыс.'), findsOneWidget);
    expect(find.textContaining('16 показателей'), findsOneWidget);
    expect(find.text('Сырьевые ресурсы'), findsOneWidget);
    expect(find.text('Снаряжение'), findsOneWidget);
    expect(find.text('Сталь'), findsNothing);

    await tester.ensureVisible(find.text('Политика'));
    await tester.tap(find.text('Политика'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .any(
            (tooltip) =>
                tooltip.message?.contains(
                  'переменная страны political_power',
                ) ==
                true,
          ),
      isTrue,
    );

    await tester.ensureVisible(find.text('Сырьевые ресурсы'));
    await tester.tap(find.text('Сырьевые ресурсы'));
    await tester.pumpAndSettle();
    expect(find.text('Сталь'), findsOneWidget);
    expect(find.text('-3'), findsOneWidget);
    expect(find.text('Нефть'), findsNothing);

    await tester.ensureVisible(find.text('Снаряжение'));
    await tester.tap(find.text('Снаряжение'));
    await tester.pumpAndSettle();
    expect(find.text('infantry_equipment'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
