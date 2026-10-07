import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/save_repository.dart';
import 'package:hoi4_helper/core/world_state.dart';
import 'package:hoi4_helper/core/world_state_source.dart';
import 'package:hoi4_helper/ui/saves_controller.dart';

import 'support/binary_header_fixture.dart';
import 'support/binary_save_fixture.dart';

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
    final fixture = BinarySaveFixture()..fieldInt32(0x349D, 31);
    await file.writeAsBytes(fixture.build());
    final repository = SaveRepository();
    final save = (await repository.list(folder.path)).single;

    final snapshot = await WorldStateSourceFactory(
      repository: repository,
    ).create(SaveFileSourceSettings(save)).read();

    expect(snapshot.playerTag, 'GER');
    expect(snapshot.ideology, 'fascism');
    expect(snapshot.difficulty, 'normal');
    expect(snapshot.gameDate.toString(), '1936.01.01 15:00');
    expect(snapshot.gameVersion, 'Case Green v1.18.0.0');
    expect(snapshot.world?.saveVersion, 31);
    expect(snapshot.loadedSave?.bytesRead, await file.length());
    expect(snapshot.sourceDescription, 'Файл сохранения');
  });

  test(
    'Reads world data beyond the list header without changing the file',
    () async {
      final folder = await Directory.systemTemp.createTemp('hoi4_world_test_');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/extended.hoi4');
      final fixture = BinarySaveFixture();
      fixture.fieldString(0x7FFE, 'x' * 5000);
      fixture.fieldInt32(0x349D, 31);
      fixture.object(0x2D49, (world) {
        world.stringKeyObject('GER', (country) {
          country.fieldInt32(0x284B, 64);
          country.fieldFixed(0x2883, 0.70);
        });
      });
      final bytes = fixture.build();
      await file.writeAsBytes(bytes);
      final modifiedBefore = (await file.stat()).modified;
      final repository = SaveRepository();
      final save = (await repository.list(folder.path)).single;

      final snapshot = await WorldStateSourceFactory(
        repository: repository,
      ).create(SaveFileSourceSettings(save)).read();

      expect(bytes.length, greaterThan(SaveRepository.headerLength));
      expect(snapshot.world?.saveVersion, 31);
      expect(snapshot.world?.playerCountry('GER')?.capitalStateId, 64);
      expect(
        snapshot.world?.playerCountry('GER')?.stability,
        closeTo(0.7, 0.00001),
      );
      expect(snapshot.loadedSave?.bytesRead, bytes.length);
      expect(await file.readAsBytes(), bytes);
      expect((await file.stat()).modified, modifiedBefore);
    },
  );

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
