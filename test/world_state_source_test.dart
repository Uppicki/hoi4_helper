import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/save_repository.dart';
import 'package:hoi4_helper/core/world_state.dart';
import 'package:hoi4_helper/core/world_state_source.dart';
import 'package:hoi4_helper/ui/saves_controller.dart';

List<int> binaryHeader({int dateCode = 60759374, String player = 'GER'}) {
  final bytes = <int>[...ascii.encode('HOI4bin')];
  void u16(int value) => bytes.addAll([value & 255, (value >> 8) & 255]);
  void fieldString(int key, int type, String value) {
    u16(key);
    u16(1);
    u16(type);
    final encoded = utf8.encode(value);
    u16(encoded.length);
    bytes.addAll(encoded);
  }

  fieldString(0x2A35, 0x000F, player);
  fieldString(0x2E3E, 0x0017, 'fascism');
  u16(0x284A);
  u16(1);
  u16(0x000C);
  bytes.addAll([
    dateCode & 255,
    (dateCode >> 8) & 255,
    (dateCode >> 16) & 255,
    (dateCode >> 24) & 255,
  ]);
  fieldString(0x299F, 0x000F, 'normal');
  fieldString(0x00EE, 0x000F, 'Case Green v1.18.0.0');
  return bytes;
}

class OtherSettings extends WorldStateSourceSettings {
  const OtherSettings();
}

class OtherSource implements WorldStateSource {
  @override
  Future<WorldStateSnapshot> read() async => WorldStateSnapshot(
    sourceDescription: 'Другой источник',
    readAt: DateTime(2026),
    playerTag: 'GER',
  );
}

void main() {
  test('Reads a binary save snapshot through the source factory', () async {
    final folder = await Directory.systemTemp.createTemp('hoi4_state_test_');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/sample.hoi4');
    await file.writeAsBytes([...binaryHeader(), ...List.filled(1024, 0)]);
    final repository = SaveRepository();
    final save = (await repository.list(folder.path)).single;

    final snapshot = await WorldStateSourceFactory(
      repository: repository,
    ).create(SaveFileSourceSettings(save)).read();

    expect(snapshot.playerTag, 'GER');
    expect(snapshot.gameDate.toString(), '1936.01.01 15:00');
    expect(snapshot.gameVersion, 'Case Green v1.18.0.0');
    expect(snapshot.loadedSave?.bytesRead, await file.length());
    expect(snapshot.sourceDescription, 'Файл сохранения');
  });

  test(
    'Decodes a later game date without treating leap years as calendar days',
    () {
      // 1937-03-01 15:00 in the game's 365-day calendar.
      final header = BinarySaveHeader.parse(binaryHeader(dateCode: 60769550));
      expect(header.date.toString(), '1937.03.01 15:00');
    },
  );

  test('Rejects unsupported and truncated formats explicitly', () {
    expect(
      () => BinarySaveHeader.parse(ascii.encode('HOI4txtplayer=GER')),
      throwsA(isA<SaveReadException>()),
    );
    expect(
      () => BinarySaveHeader.parse(binaryHeader().sublist(0, 20)),
      throwsA(isA<SaveReadException>()),
    );
    final changedLayout = binaryHeader();
    changedLayout[7] = 0;
    expect(
      () => BinarySaveHeader.parse(changedLayout),
      throwsA(isA<SaveReadException>()),
    );
  });

  test(
    'Factory accepts another source without changing the controller contract',
    () async {
      final factory = WorldStateSourceFactory();
      expect(
        () => factory.create(const OtherSettings()),
        throwsUnsupportedError,
      );
      factory.register<OtherSettings>((_) => OtherSource());
      final snapshot = await factory.create(const OtherSettings()).read();
      expect(snapshot.sourceDescription, 'Другой источник');
      expect(snapshot.playerTag, 'GER');
      expect(snapshot.gameDate, isNull);

      final controller = SavesController(sourceFactory: factory);
      addTearDown(controller.dispose);
      await controller.loadFromSource(const OtherSettings());
      expect(controller.worldState?.sourceDescription, 'Другой источник');
      expect(controller.loaded, isNull);
    },
  );
}
