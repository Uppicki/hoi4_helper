import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/save_repository.dart';
import 'package:hoi4_helper/core/world_state.dart';
import 'package:hoi4_helper/core/world_state_source.dart';
import 'package:hoi4_helper/ui/saves_controller.dart';
import 'package:hoi4_helper/ui/saves_screen.dart';

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
        home: SavesScreen(controller: controller, pickDirectory: picker),
      ),
    );
    return controller;
  }

  testWidgets(
    'Pick folder, select and load file; view mode hides analyzer placeholder',
    (tester) async {
      await mount(tester, picker: () async => r'C:\saves');
      final loadButton = find.ancestor(
        of: find.text('Загрузить сохранение'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(tester.widget<FilledButton>(loadButton).onPressed, isNull);

      await tester.tap(find.text('Выбрать папку'));
      await tester.pumpAndSettle();
      expect(find.text('Кампания.hoi4'), findsOneWidget);
      await tester.tap(find.text('Кампания.hoi4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Загрузить сохранение'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Файл прочитан'), findsOneWidget);
      expect(find.text('1936.01.01 15:00'), findsOneWidget);
      expect(find.text('GER'), findsOneWidget);

      await tester.tap(find.text('Только просмотр'));
      await tester.pumpAndSettle();
      expect(find.text('Анализ появится на следующем этапе.'), findsNothing);
      expect(find.textContaining('Файл прочитан'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('Cancelling picker preserves folder and loaded save', (
    tester,
  ) async {
    final controller = await mount(tester, picker: () async => null);
    await controller.openFolder(r'C:\saves');
    controller.select(controller.saves.single);
    await controller.loadSelected();
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
    await tester.ensureVisible(find.text('Загрузить сохранение'));
    await tester.tap(find.text('Загрузить сохранение'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Файл прочитан'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
