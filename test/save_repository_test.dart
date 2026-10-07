import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/save_repository.dart';

void main() {
  late Directory folder;
  final repository = SaveRepository();

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('hoi4_ui_test_');
  });

  tearDown(() async {
    await folder.delete(recursive: true);
  });

  test(
    'Lists only direct .hoi4 files, newest first, including Unicode names',
    () async {
      final older = File('${folder.path}/Старая кампания.hoi4');
      final newer = File('${folder.path}/New.HOI4');
      await older.writeAsString('synthetic old file');
      await newer.writeAsString('synthetic new file');
      await older.setLastModified(DateTime(2020));
      await newer.setLastModified(DateTime(2021));
      await File('${folder.path}/notes.txt').writeAsString('not a save');
      final nested = await Directory('${folder.path}/nested').create();
      await File('${nested.path}/hidden.hoi4').writeAsString('nested');

      final saves = await repository.list(folder.path);

      expect(saves.map((save) => save.name), [
        'New.HOI4',
        'Старая кампания.hoi4',
      ]);
      expect(saves.first.path, newer.uri.toFilePath());
    },
  );

  test(
    'Reads all bytes without changing source content or modification time',
    () async {
      final file = File('${folder.path}/sample.hoi4');
      final bytes = List<int>.generate(160000, (index) => index % 256);
      await file.writeAsBytes(bytes);
      final before = await file.stat();

      final loaded = await repository.load(
        (await repository.list(folder.path)).single,
      );

      expect(loaded.bytesRead, bytes.length);
      expect(await file.readAsBytes(), bytes);
      expect((await file.stat()).modified, before.modified);
    },
  );

  test(
    'Empty folder is valid; missing folder produces a clear error',
    () async {
      expect(await repository.list(folder.path), isEmpty);
      await expectLater(
        repository.list('${folder.path}/missing'),
        throwsA(isA<SaveReadException>()),
      );
    },
  );

  test(
    'Rejects empty and deleted files instead of claiming a successful load',
    () async {
      final file = await File('${folder.path}/empty.hoi4').create();
      final save = (await repository.list(folder.path)).single;
      await expectLater(
        repository.load(save),
        throwsA(isA<SaveReadException>()),
      );
      await file.delete();
      await expectLater(
        repository.load(save),
        throwsA(isA<SaveReadException>()),
      );
    },
  );
}
