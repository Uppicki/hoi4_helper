import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/binary_save_world_parser.dart';
import 'package:hoi4_helper/core/save_repository.dart';
import 'package:hoi4_helper/core/snapshot_evidence.dart';
import 'package:hoi4_helper/core/world_state.dart';
import 'package:hoi4_helper/core/world_state_source.dart';

import 'support/binary_save_fixture.dart';

void main() {
  test(
    'Full-file identity survives copies and detects changed bytes',
    () async {
      final folder = await Directory.systemTemp.createTemp('hoi4_identity_');
      addTearDown(() => folder.delete(recursive: true));
      final first = File('${folder.path}/first.hoi4');
      final copy = File('${folder.path}/copy.hoi4');
      final fixture = BinarySaveFixture()..fieldInt32(0x349D, 31);
      final bytes = fixture.build();
      await first.writeAsBytes(bytes);
      await copy.writeAsBytes(bytes);
      final repository = SaveRepository();
      final saves = await repository.list(folder.path);
      final a = await repository.load(saves.first);
      final b = await repository.load(saves.last);
      expect(a.contentSha256, sha256.convert(bytes).toString());
      expect(a.contentSha256, b.contentSha256);

      final source = WorldStateSourceFactory(repository: repository);
      final snapshot = await source
          .create(SaveFileSourceSettings(saves.first))
          .read();
      expect(snapshot.identity?.saveId, a.contentSha256);
      expect(snapshot.identity?.sourceId, saves.first.path);
      expect(snapshot.identity?.campaignId, isNull);
      expect(snapshot.identity?.gameDataId, isNull);
      expect(SnapshotIdentity.schemaVersion, 1);

      await first.writeAsBytes([...bytes, 0]);
      final changed = await repository.load(
        (await repository.list(
          folder.path,
        )).singleWhere((save) => save.name == 'first.hoi4'),
      );
      expect(changed.contentSha256, isNot(a.contentSha256));
    },
  );

  test(
    'Parser rejects a save changed between verification and parsing',
    () async {
      final folder = await Directory.systemTemp.createTemp('hoi4_digest_');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/sample.hoi4');
      final bytes = (BinarySaveFixture()..fieldInt32(0x349D, 31)).build();
      await file.writeAsBytes(bytes);
      final save = (await SaveRepository().list(folder.path)).single;
      await expectLater(
        BinarySaveWorldParser.readFile(save, expectedSha256: '0' * 64),
        throwsA(isA<SaveReadException>()),
      );
    },
  );

  test('Successor requires a known campaign, data, country and later date', () {
    SnapshotIdentity identity({
      String? campaign = 'campaign-a',
      String? data = 'data-a',
      String tag = 'GER',
      String save = 'save-b',
      GameDate date = const GameDate(1936, 2, 1, 0),
    }) => SnapshotIdentity(
      sourceId: 'file.hoi4',
      saveId: save,
      campaignId: campaign,
      playerTag: tag,
      gameDate: date,
      gameVersion: 'v1.18',
      gameDataId: data,
    );
    final previous = identity(
      save: 'save-a',
      date: const GameDate(1936, 1, 1, 0),
    );
    expect(identity().canFollow(previous), isTrue);
    expect(identity(campaign: null).canFollow(previous), isFalse);
    expect(identity(data: null).canFollow(previous), isFalse);
    expect(identity(campaign: 'campaign-b').canFollow(previous), isFalse);
    expect(identity(tag: 'FRA').canFollow(previous), isFalse);
    expect(
      SnapshotIdentity(
        sourceId: 'file.hoi4',
        saveId: 'save-b',
        campaignId: 'campaign-a',
        playerTag: 'GER',
        gameDate: const GameDate(1936, 2, 1, 0),
        gameVersion: 'v1.19',
        gameDataId: 'data-a',
      ).canFollow(previous),
      isFalse,
    );
    expect(identity(save: 'save-a').canFollow(previous), isFalse);
    expect(
      identity(date: const GameDate(1935, 12, 1, 0)).canFollow(previous),
      isFalse,
    );
  });

  test('Evidence keeps unknown separate from zero and false', () {
    final snapshot = WorldStateSnapshot(
      sourceDescription: 'save',
      readAt: DateTime(2026),
      playerTag: 'GER',
      world: const SaveWorldDetails(
        saveVersion: 31,
        ironman: false,
        countries: {
          'GER': CountryWorldState(
            tag: 'GER',
            divisionCount: 0,
            civilianFactories: 0,
          ),
        },
      ),
    );
    final fields = SnapshotEvidence.from(snapshot);
    expect(fields['ironman'].origin, FieldOrigin.save);
    expect(fields['divisionCount'].origin, FieldOrigin.calculated);
    expect(fields['civilianFactories'].origin, FieldOrigin.calculated);
    expect(fields['fleetCount'].origin, FieldOrigin.unknown);
    expect(fields['campaignId'].origin, FieldOrigin.unknown);
    expect(fields['fuel'].origin, FieldOrigin.unsupported);
    expect(fields['fileSize'].origin, FieldOrigin.unknown);
    expect(fields['localizedNames'].origin, FieldOrigin.unknown);
    expect(
      SnapshotEvidence.from(
        snapshot,
        localizationAvailable: true,
      )['localizedNames'].origin,
      FieldOrigin.installedGameData,
    );
    expect(() => fields['notRegistered'], throwsArgumentError);
  });
}
