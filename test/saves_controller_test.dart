import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/save_repository.dart';
import 'package:hoi4_helper/core/world_state.dart';
import 'package:hoi4_helper/core/world_state_source.dart';
import 'package:hoi4_helper/ui/saves_controller.dart';

import 'support/binary_header_fixture.dart';

class TwoSaves extends SaveRepository {
  final first = SaveFile(
    path: 'first.hoi4',
    name: 'first.hoi4',
    size: 1,
    modified: DateTime(2026),
  );
  final second = SaveFile(
    path: 'second.hoi4',
    name: 'second.hoi4',
    size: 1,
    modified: DateTime(2026),
  );

  @override
  Future<List<SaveFile>> list(String folderPath) async =>
      folderPath == 'empty' ? [] : [first, second];

  @override
  Future<List<int>> readHeader(SaveFile save) async =>
      binaryHeader(player: save.path == first.path ? 'GER' : 'FRA');
}

class DeferredSource implements WorldStateSource {
  DeferredSource(this.result);
  final Future<WorldStateSnapshot> result;

  @override
  Future<WorldStateSnapshot> read() => result;
}

void main() {
  test('Only the most recently selected save may update the preview', () async {
    final repository = TwoSaves();
    final first = Completer<WorldStateSnapshot>();
    final second = Completer<WorldStateSnapshot>();
    final factory = WorldStateSourceFactory(repository: repository);
    factory.register<SaveFileSourceSettings>(
      (settings) => DeferredSource(
        settings.save.path == repository.first.path
            ? first.future
            : second.future,
      ),
    );
    final controller = SavesController(
      repository: repository,
      sourceFactory: factory,
    );
    addTearDown(controller.dispose);
    await controller.openFolder('folder');

    controller.select(repository.first);
    controller.select(repository.second);
    expect(controller.previewLoading, isTrue);
    second.complete(
      WorldStateSnapshot(
        sourceDescription: 'Файл сохранения',
        readAt: DateTime(2026),
        playerTag: 'FRA',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    first.complete(
      WorldStateSnapshot(
        sourceDescription: 'Файл сохранения',
        readAt: DateTime(2026),
        playerTag: 'GER',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.selected, same(repository.second));
    expect(controller.worldState?.playerTag, 'FRA');
    expect(controller.previewLoading, isFalse);
  });

  test('Changing folders discards an in-flight preview', () async {
    final repository = TwoSaves();
    final pending = Completer<WorldStateSnapshot>();
    final factory = WorldStateSourceFactory(repository: repository);
    factory.register<SaveFileSourceSettings>(
      (_) => DeferredSource(pending.future),
    );
    final controller = SavesController(
      repository: repository,
      sourceFactory: factory,
    );
    addTearDown(controller.dispose);
    await controller.openFolder('folder');
    controller.select(repository.first);
    await controller.openFolder('empty');
    pending.complete(
      WorldStateSnapshot(
        sourceDescription: 'Файл сохранения',
        readAt: DateTime(2026),
        playerTag: 'GER',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.selected, isNull);
    expect(controller.worldState, isNull);
    expect(controller.previewLoading, isFalse);
  });

  test(
    'Changing source clears selection and discards pending preview',
    () async {
      final repository = TwoSaves();
      final pending = Completer<WorldStateSnapshot>();
      final factory = WorldStateSourceFactory(repository: repository);
      factory.register<SaveFileSourceSettings>(
        (_) => DeferredSource(pending.future),
      );
      final controller = SavesController(
        repository: repository,
        sourceFactory: factory,
      );
      addTearDown(controller.dispose);
      await controller.openFolder('folder');
      controller.select(repository.first);
      controller.clearSelection();
      pending.complete(
        WorldStateSnapshot(
          sourceDescription: 'Файл сохранения',
          readAt: DateTime(2026),
          playerTag: 'GER',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.selected, isNull);
      expect(controller.worldState, isNull);
      expect(controller.previewLoading, isFalse);
      expect(controller.saves, isNotEmpty);
    },
  );
}
