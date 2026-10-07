import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/game_localization.dart';
import 'package:hoi4_helper/core/save_repository.dart';
import 'package:hoi4_helper/core/world_state.dart';
import 'package:hoi4_helper/ui/world_screen.dart';

class MemoryLocalization extends GameLocalizationRepository {
  @override
  Future<GameLocalization> load(GameLanguage language) async =>
      GameLocalization(
        language,
        language == GameLanguage.russian
            ? {
                'GER_fascism': 'Третий рейх',
                'GER_rhineland': 'Рейнская область',
                'basic_machine_tools': 'Базовые станки',
              }
            : {
                'GER_fascism': 'German Reich',
                'GER_rhineland': 'Rhineland',
                'basic_machine_tools': 'Basic Machine Tools',
              },
      );
}

void main() {
  testWidgets('Dashboard translates names and expands compact save details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = SaveFile(
      path: r'C:\saves\GER.hoi4',
      name: 'GER.hoi4',
      size: 1024,
      modified: DateTime(2026, 10, 7),
    );
    final snapshot = WorldStateSnapshot(
      sourceDescription: 'Файл сохранения',
      readAt: DateTime(2026, 10, 7),
      gameDate: const GameDate(1936, 1, 1, 15),
      playerTag: 'GER',
      ideology: 'fascism',
      difficulty: 'normal',
      loadedSave: LoadedSave(
        file: file,
        bytesRead: 1024,
        loadedAt: DateTime(2026, 10, 7),
      ),
      world: const SaveWorldDetails(
        countries: {
          'GER': CountryWorldState(
            tag: 'GER',
            divisionCount: 30,
            currentFocus: 'GER_rhineland',
            activeResearch: ['basic_machine_tools'],
          ),
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: WorldScreen(
          snapshot: snapshot,
          localizationRepository: MemoryLocalization(),
          onChangeSource: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Третий рейх'), findsOneWidget);
    expect(find.text('Рейнская область'), findsOneWidget);
    expect(find.text('Топливо'), findsNothing);
    expect(find.text('Опыт флота'), findsNothing);

    await tester.tap(find.byKey(const Key('save-summary')));
    await tester.pumpAndSettle();
    expect(find.text('1,0 КБ'), findsNothing);
    expect(find.text('1.0 КБ'), findsOneWidget);
    expect(find.byKey(const Key('change-source')), findsOneWidget);

    await tester.tap(find.byKey(const Key('game-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('German Reich'), findsOneWidget);
    expect(find.text('Rhineland'), findsOneWidget);
  });
}
