import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/save_repository.dart';
import 'package:hoi4_helper/core/world_state.dart';
import 'package:hoi4_helper/core/world_state_source.dart';
import 'package:hoi4_helper/ui/app_router.dart';
import 'package:hoi4_helper/ui/saves_controller.dart';
import 'package:hoi4_helper/ui/saves_screen.dart';
import 'package:hoi4_helper/ui/world_screen.dart';

import 'support/binary_header_fixture.dart';

class MemorySaves extends SaveRepository {
  final file = SaveFile(
    path: r'C:\saves\Кампания.hoi4',
    name: 'Кампания.hoi4',
    size: 4096,
    modified: DateTime(2026, 10, 2, 18, 30),
  );

  @override
  Future<List<SaveFile>> list(String folderPath) async {
    if (folderPath == 'missing') {
      throw const SaveReadException('Папка не найдена. Проверьте путь.');
    }
    return folderPath == 'empty' ? [] : [file];
  }

  @override
  Future<LoadedSave> load(SaveFile save) async => LoadedSave(
    file: save,
    bytesRead: save.size,
    loadedAt: DateTime(2026, 10, 2, 19),
  );

  @override
  Future<List<int>> readHeader(SaveFile save) async => binaryHeader();
}

class MemoryWorldSource implements WorldStateSource {
  MemoryWorldSource(this.file, this.repository);

  final SaveFile file;
  final SaveRepository repository;

  @override
  Future<WorldStateSnapshot> read() async {
    final loaded = await repository.load(file);
    return WorldStateSnapshot(
      sourceDescription: 'Файл сохранения',
      readAt: loaded.loadedAt,
      gameDate: const GameDate(1936, 1, 1, 15),
      playerTag: 'GER',
      ideology: 'fascism',
      difficulty: 'normal',
      gameVersion: 'v1.18',
      loadedSave: loaded,
    );
  }
}

void main() {
  Future<SavesController> mount(
    WidgetTester tester, {
    double width = 1280,
    Future<String?> Function()? picker,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemorySaves();
    final factory = WorldStateSourceFactory(repository: repository);
    factory.register<SaveFileSourceSettings>(
      (settings) => MemoryWorldSource(settings.save, repository),
    );
    final controller = SavesController(
      repository: repository,
      sourceFactory: factory,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: AppRouter(controller: controller, pickDirectory: picker),
      ),
    );
    return controller;
  }

  testWidgets('Selecting a save loads preview and Use opens the world page', (
    tester,
  ) async {
    await mount(tester, picker: () async => r'C:\saves');
    expect(find.text('Использовать'), findsNothing);

    await tester.tap(find.text('Выбрать папку'));
    await tester.pumpAndSettle();
    expect(find.text('Кампания.hoi4'), findsOneWidget);
    expect(find.text('1936 · GER · normal · v1.18.0.0'), findsOneWidget);
    expect(find.textContaining('Оригинальные файлы остаются'), findsNothing);
    expect(
      tester.getSize(find.byType(ListView).first).height,
      greaterThan(340),
    );
    await tester.tap(find.text('Кампания.hoi4'));
    await tester.pumpAndSettle();
    expect(find.text('1936.01.01 15:00'), findsOneWidget);
    expect(find.text('GER'), findsOneWidget);
    expect(find.text('fascism'), findsOneWidget);

    await tester.ensureVisible(find.text('Использовать'));
    await tester.tap(find.text('Использовать'));
    await tester.pumpAndSettle();
    expect(find.text('Состояние мира'), findsOneWidget);
    expect(find.text('Сведения о снимке'), findsOneWidget);
    expect(find.text('Исследования'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Только просмотр'));
    await tester.pumpAndSettle();
    expect(find.text('Использовать'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Desktop content slides left while the sidebar remains fixed', (
    tester,
  ) async {
    await mount(tester, picker: () async => r'C:\saves');
    await tester.tap(find.text('Выбрать папку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Кампания.hoi4'));
    await tester.pumpAndSettle();

    final sidebar = find.text('Локальный помощник');
    expect(sidebar, findsOneWidget);
    final sidebarPosition = tester.getTopLeft(sidebar);

    await tester.tap(find.text('Использовать'));
    await tester.pump();
    final world = find.byType(WorldScreen);
    expect(world, findsOneWidget);
    final initialWorldX = tester.getTopLeft(world).dx;
    expect(tester.getTopLeft(sidebar), sidebarPosition);

    await tester.pump(const Duration(milliseconds: 80));
    final movingWorldX = tester.getTopLeft(world).dx;
    expect(movingWorldX, lessThan(initialWorldX));
    expect(movingWorldX, greaterThan(240));
    expect(tester.getTopLeft(sidebar), sidebarPosition);

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(world).dx, closeTo(240, 0.1));
    expect(tester.getTopLeft(sidebar), sidebarPosition);

    await tester.pageBack();
    await tester.pump();
    final initialReturnX = tester.getTopLeft(world).dx;
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getTopLeft(world).dx, greaterThan(initialReturnX));
    expect(tester.getTopLeft(sidebar), sidebarPosition);

    await tester.pumpAndSettle();
    expect(find.byType(SavesScreen), findsOneWidget);
    expect(find.text('Использовать'), findsOneWidget);
    expect(tester.getTopLeft(sidebar), sidebarPosition);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Horizontal swipes navigate between saves and the world', (
    tester,
  ) async {
    await mount(tester, picker: () async => r'C:\saves');
    await tester.tap(find.text('Выбрать папку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Кампания.hoi4'));
    await tester.pumpAndSettle();

    await tester.timedDragFrom(
      const Offset(900, 500),
      const Offset(-500, 0),
      const Duration(milliseconds: 180),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorldScreen), findsOneWidget);
    expect(find.text('Сведения о снимке'), findsOneWidget);

    await tester.timedDragFrom(
      const Offset(350, 500),
      const Offset(500, 0),
      const Duration(milliseconds: 180),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SavesScreen), findsOneWidget);
    expect(find.text('Использовать'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Manual path and missing/empty folders reset the previous selection',
    (tester) async {
      final controller = await mount(tester);
      await tester.enterText(find.byType(TextField), r'C:\saves');
      await tester.tap(find.text('Обновить список'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Кампания.hoi4'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'missing');
      await tester.tap(find.text('Обновить список'));
      await tester.pumpAndSettle();
      expect(find.text('Папка не найдена. Проверьте путь.'), findsOneWidget);
      expect(controller.selected, isNull);
      expect(controller.loaded, isNull);
      expect(controller.worldState, isNull);
      expect(find.text('Кампания.hoi4'), findsNothing);

      await tester.enterText(find.byType(TextField), 'empty');
      await tester.tap(find.text('Обновить список'));
      await tester.pumpAndSettle();
      expect(find.text('Сохранения .hoi4 не найдены'), findsOneWidget);
      expect(find.text('Папка не найдена. Проверьте путь.'), findsNothing);
    },
  );

  testWidgets('Cancelling picker preserves folder and preview', (tester) async {
    final controller = await mount(tester, picker: () async => null);
    await controller.openFolder(r'C:\saves');
    controller.select(controller.saves.single);
    await tester.pumpAndSettle();
    final loaded = controller.loaded;

    await tester.tap(find.text('Выбрать папку'));
    await tester.pumpAndSettle();
    expect(controller.folder, r'C:\saves');
    expect(controller.loaded, same(loaded));
  });

  testWidgets('Narrow layout remains usable', (tester) async {
    await mount(tester, width: 480);
    expect(find.text('Только просмотр'), findsOneWidget);
    await tester.tap(find.text('Только просмотр'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), r'C:\saves');
    await tester.ensureVisible(find.text('Обновить список'));
    await tester.tap(find.text('Обновить список'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Кампания.hoi4'));
    await tester.tap(find.text('Кампания.hoi4'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Использовать'));
    await tester.tap(find.text('Использовать'));
    await tester.pumpAndSettle();
    expect(find.text('Состояние мира'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
