import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/focus_tree.dart';
import 'package:hoi4_helper/core/game_localization.dart';
import 'package:hoi4_helper/core/world_state.dart';
import 'package:hoi4_helper/ui/world_screen.dart';

class _Names extends GameLocalizationRepository {
  @override
  Future<GameLocalization> load(GameLanguage language) async =>
      GameLocalization(language, const {
        'GER': 'Германия',
        'german_focus': 'Германские фокусы',
        'GER_first': 'Первый фокус',
        'GER_second': 'Второй фокус',
        'GER_third': 'Третий фокус',
      });
}

class _LoadedRepository extends FocusTreeRepository {
  const _LoadedRepository();

  @override
  Future<List<FocusTreeDefinition>> load({
    String? treeId,
    String? countryTag,
  }) async => const [
    FocusTreeDefinition('german_focus', [
      FocusDefinition(id: 'GER_first', x: 4, y: 0, prerequisites: []),
      FocusDefinition(
        id: 'GER_second',
        x: -1,
        y: 1,
        relativeTo: 'GER_first',
        prerequisites: ['GER_first'],
      ),
      FocusDefinition(id: 'GER_third', x: 8, y: 2, prerequisites: []),
    ], 'fixture.txt'),
  ];
}

void main() {
  late Directory root;
  late FocusTreeRepository repository;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hoi-focus-test-');
    final folder = Directory('${root.path}/common/national_focus')
      ..createSync(recursive: true);
    File('${folder.path}/germany.txt').writeAsStringSync('''
# Based on the nested shape of installed national_focus definitions.
focus_tree = {
  id = german_focus
  country = { factor = 0 modifier = { add = 10 tag = GER } }
  focus = {
    id = GER_first x = 4 y = 0 cost = 5
    completion_reward = { add_stability = 0.1 }
  }
  focus = {
    id = GER_second x = -1 y = 1
    relative_position_id = GER_first
    prerequisite = { focus = GER_first }
    prerequisite = { focus = "GER_third" } # repeated key
  }
  focus = { id = GER_third x = 8 y = 2 }
}
''');
    repository = FocusTreeRepository(gameRoot: root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test(
    'reads ordered focuses, relative positions and repeated prerequisites',
    () async {
      final trees = await repository.load(treeId: 'german_focus');
      expect(trees, hasLength(1));
      expect(trees.single.focuses.map((focus) => focus.id), [
        'GER_first',
        'GER_second',
        'GER_third',
      ]);
      expect(trees.single.focuses[1].relativeTo, 'GER_first');
      expect(trees.single.focuses[1].prerequisites, ['GER_first', 'GER_third']);
      expect(
        (await repository.load(countryTag: 'GER')).single.id,
        'german_focus',
      );
      expect(await repository.load(treeId: 'other_tree'), isEmpty);
    },
  );

  testWidgets('focus panel opens a real tree matched to a save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final snapshot = WorldStateSnapshot(
      sourceDescription: 'test save',
      readAt: DateTime(2026),
      playerTag: 'GER',
      world: const SaveWorldDetails(
        countries: {
          'GER': CountryWorldState(
            tag: 'GER',
            focusTree: 'german_focus',
            currentFocus: 'GER_second',
            completedFocuses: ['GER_first'],
          ),
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: WorldScreen(
          snapshot: snapshot,
          localizationRepository: _Names(),
          focusTreeRepository: const _LoadedRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Второй фокус'), findsWidgets);
    await tester.tap(find.byKey(const Key('focus-summary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('focus-tree-canvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-GER_first')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-GER_second')), findsOneWidget);
    expect(
      find.text(
        'Перетаскивайте дерево; масштабируйте колесом мыши или жестом.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('telemetry does not invent current focus or progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: WorldScreen(
          snapshot: WorldStateSnapshot(
            sourceDescription: 'telemetry',
            readAt: DateTime(2026),
            playerTag: 'GER',
          ),
          telemetryMode: true,
          localizationRepository: _Names(),
          focusTreeRepository: const _LoadedRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('focus-summary')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Источник не подтверждает'), findsOneWidget);
    expect(find.byKey(const Key('focus-tree-canvas')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
