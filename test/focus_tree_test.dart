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
      FocusDefinition(
        id: 'GER_third',
        x: 8,
        y: 2,
        prerequisites: [],
        visibility: FocusVisibility.unknown,
      ),
      FocusDefinition(
        id: 'GER_hidden',
        x: 4,
        y: 1,
        prerequisites: [],
        visibility: FocusVisibility.hidden,
      ),
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

  void writeBranches() {
    File('${root.path}/common/national_focus/germany.txt').writeAsStringSync('''
focus_tree = {
  id = german_focus
  country = { modifier = { tag = GER } }
  focus = {
    id = modern x = 0 y = 0
    allow_branch = { has_dlc = "Test Expansion" }
    available = { always = no }
    completion_reward = {
      country_event = { id = event.1 }
      focus = { id = nested_reward x = 99 y = 99 }
    }
  }
  focus = {
    id = legacy x = 10 y = 0
    allow_branch = { NOT = { has_dlc = "Test Expansion" } }
  }
  focus = {
    id = legacy_child x = 0 y = 1 relative_position_id = legacy
    prerequisite = { focus = legacy }
  }
  focus = {
    id = alternative x = 2 y = 1
    prerequisite = { focus = legacy focus = modern }
  }
  focus = {
    id = requires_both x = 4 y = 1
    prerequisite = { focus = legacy }
    prerequisite = { focus = modern }
  }
  focus = {
    id = dynamic x = 6 y = 1
    allow_branch = { has_country_flag = example_flag }
  }
  focus = {
    id = dynamic_child x = 6 y = 2
    prerequisite = { focus = dynamic }
  }
}
''');
  }

  test(
    'filters incompatible DLC branches and descendants, never reward events',
    () async {
      writeBranches();
      final withDlc = (await FocusTreeRepository(
        gameRoot: root.path,
        activeDlcs: const {'Test Expansion'},
      ).load(treeId: 'german_focus')).single;
      expect(withDlc.displayedFocuses.map((f) => f.id), [
        'modern',
        'alternative',
        'dynamic',
        'dynamic_child',
      ]);
      expect(withDlc.focuses.any((f) => f.id == 'nested_reward'), isFalse);
      expect(withDlc.focuses.first.visibility, FocusVisibility.visible);
      expect(withDlc.focuses.last.visibility, FocusVisibility.unknown);
      final withoutDlc = (await FocusTreeRepository(
        gameRoot: root.path,
        activeDlcs: const {},
      ).load(treeId: 'german_focus')).single;
      expect(withoutDlc.displayedFocuses.map((f) => f.id), [
        'legacy',
        'legacy_child',
        'alternative',
        'dynamic',
        'dynamic_child',
      ]);
      final unknown = (await repository.load(treeId: 'german_focus')).single;
      expect(
        unknown.focuses.every((f) => f.visibility == FocusVisibility.unknown),
        isTrue,
      );
      final integrated = Directory('${root.path}/integrated_dlc/test')
        ..createSync(recursive: true);
      File(
        '${integrated.path}/test.dlc',
      ).writeAsStringSync('name = "Test Expansion"');
      final integratedTree = (await FocusTreeRepository(
        gameRoot: root.path,
        activeDlcs: const {},
      ).load(treeId: 'german_focus')).single;
      expect(integratedTree.focuses.first.visibility, FocusVisibility.unknown);
    },
  );

  test(
    'uses only a complete DLC list from the telemetry sibling system log',
    () async {
      writeBranches();
      final logs = Directory('${root.path}/logs')..createSync();
      final systemLog = File('${logs.path}/system.log');
      systemLog.writeAsStringSync('''
[time][system] Active DLC Count: 1
[time][system] Active DLC: Test Expansion
''');
      final fromLog = FocusTreeRepository(
        gameRoot: root.path,
        runtimeLogSource: '${logs.path}/game.log',
      );
      final tree = (await fromLog.load(treeId: 'german_focus')).single;
      expect(tree.activeDlcCount, 1);
      expect(File(tree.dlcSourceFile!).existsSync(), isTrue);
      expect(tree.displayedFocuses.any((f) => f.id == 'legacy_child'), isFalse);
      systemLog.writeAsStringSync(
        '[time] Active DLC Count: 2\n[time] Active DLC: Test Expansion\n',
      );
      final incomplete = (await fromLog.load(treeId: 'german_focus')).single;
      expect(incomplete.activeDlcCount, isNull);
      expect(incomplete.focuses.first.visibility, FocusVisibility.unknown);
      systemLog.writeAsBytesSync([0xff]);
      expect(
        (await fromLog.load(treeId: 'german_focus')).single.activeDlcCount,
        isNull,
      );
    },
  );

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
    expect(find.byKey(const ValueKey('focus-GER_hidden')), findsNothing);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
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
