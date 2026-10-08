import 'world_state.dart';

enum FieldOrigin {
  save,
  calculated,
  fileMetadata,
  installedGameData,
  unknown,
  unsupported,
}

class FieldEvidence {
  const FieldEvidence(this.origin, {this.basis});

  final FieldOrigin origin;
  final String? basis;
}

/// Provenance of the fields shown on the 0.1.0 world screen.
/// A missing parsed value is unknown, even when zero or false would be valid.
class SnapshotEvidence {
  SnapshotEvidence._(this.fields);

  final Map<String, FieldEvidence> fields;

  FieldEvidence operator [](String name) =>
      fields[name] ??
      (throw ArgumentError.value(name, 'name', 'Unregistered screen field'));

  factory SnapshotEvidence.from(
    WorldStateSnapshot snapshot, {
    bool localizationAvailable = false,
  }) {
    final fields = <String, FieldEvidence>{};
    final world = snapshot.world;
    final country = world?.playerCountry(snapshot.playerTag);

    void record(
      String name,
      Object? value, {
      FieldOrigin origin = FieldOrigin.save,
      String? basis,
    }) {
      fields[name] = FieldEvidence(
        value == null || value is Iterable && value.isEmpty
            ? FieldOrigin.unknown
            : origin,
        basis: basis,
      );
    }

    void unsupported(String name) =>
        fields[name] = const FieldEvidence(FieldOrigin.unsupported);

    record(
      'source',
      snapshot.sourceDescription,
      origin: FieldOrigin.fileMetadata,
    );
    record(
      'saveId',
      snapshot.identity?.saveId,
      origin: FieldOrigin.fileMetadata,
    );
    record('campaignId', snapshot.identity?.campaignId);
    record(
      'gameDataId',
      snapshot.identity?.gameDataId,
      origin: FieldOrigin.installedGameData,
    );
    record('readAt', snapshot.readAt, origin: FieldOrigin.fileMetadata);
    record(
      'fileName',
      snapshot.loadedSave?.file.name,
      origin: FieldOrigin.fileMetadata,
    );
    record(
      'fileSize',
      snapshot.loadedSave?.bytesRead,
      origin: FieldOrigin.fileMetadata,
    );
    record(
      'fileModified',
      snapshot.loadedSave?.file.modified,
      origin: FieldOrigin.fileMetadata,
    );
    record('gameDate', snapshot.gameDate);
    record('playerTag', snapshot.playerTag);
    record('ideology', snapshot.ideology);
    record('difficulty', snapshot.difficulty);
    record('gameVersion', snapshot.gameVersion);
    record('saveVersion', world?.saveVersion);
    record('startDate', world?.startDate);
    record(
      'provinceCount',
      world?.provinceCount,
      origin: FieldOrigin.calculated,
      basis: 'distinct province keys',
    );
    record(
      'stateCount',
      world?.stateCount,
      origin: FieldOrigin.calculated,
      basis: 'distinct state keys',
    );
    record(
      'factionCount',
      world?.factionCount,
      origin: FieldOrigin.calculated,
      basis: 'faction blocks',
    );
    record('ironman', world?.ironman);
    record(
      'countryCount',
      world?.countries.isEmpty == true ? null : world?.countries.length,
      origin: FieldOrigin.calculated,
      basis: 'country blocks',
    );
    record(
      'ownedStateCount',
      snapshot.playerTag == null
          ? null
          : world?.ownedStateCounts[snapshot.playerTag!],
      origin: FieldOrigin.calculated,
      basis: 'states owned by player',
    );
    record('capital', country?.capitalStateId);
    record('major', country?.major);
    record('stability', country?.stability);
    record('warSupport', country?.warSupport);
    record(
      'divisionCount',
      country?.divisionCount,
      origin: FieldOrigin.calculated,
      basis: 'division blocks',
    );
    record(
      'fleetCount',
      country?.fleetCount,
      origin: FieldOrigin.calculated,
      basis: 'fleet blocks',
    );
    record('shipCount', country?.shipCount);
    record('armyExperience', country?.armyExperience);
    record('airExperience', country?.airExperience);
    record(
      'civilianFactories',
      country?.civilianFactories,
      origin: FieldOrigin.calculated,
      basis: 'industrial_complex levels in owned states',
    );
    record(
      'militaryFactories',
      country?.militaryFactories,
      origin: FieldOrigin.calculated,
      basis: 'arms_factory levels in owned states',
    );
    record(
      'dockyards',
      country?.dockyards,
      origin: FieldOrigin.calculated,
      basis: 'dockyard levels in owned states',
    );
    record(
      'militaryProductionLines',
      country?.militaryProductionLines,
      origin: FieldOrigin.calculated,
      basis: 'military line blocks',
    );
    record(
      'navalProductionLines',
      country?.navalProductionLines,
      origin: FieldOrigin.calculated,
      basis: 'naval line blocks',
    );
    record(
      'stateAvailableManpower',
      country?.stateAvailableManpower,
      origin: FieldOrigin.calculated,
      basis: 'available manpower in owned states',
    );
    record('politicalPower', country?.politicalPower);
    record('commandPower', country?.commandPower);
    record('focusTree', country?.focusTree);
    record('currentFocus', country?.currentFocus);
    record('completedFocuses', country?.completedFocuses);
    record('researchSlots', country?.researchSlots);
    record('activeResearch', country?.activeResearch);
    record('researchedTechnologies', country?.researchedTechnologies);
    record(
      'stateOwners',
      world?.stateOwners.isEmpty == true ? null : world?.stateOwners,
      origin: FieldOrigin.calculated,
      basis: 'owner of each parsed state',
    );
    record(
      'ownedStates',
      world?.states.values
          .where((state) => state.owner == snapshot.playerTag)
          .toList(),
      origin: FieldOrigin.calculated,
      basis: 'states owned by player',
    );
    fields['localizedNames'] = FieldEvidence(
      localizationAvailable
          ? FieldOrigin.installedGameData
          : FieldOrigin.unknown,
    );
    for (final name in [
      'airWings',
      'navalExperience',
      'fuel',
      'rawResources',
      'armyReserve',
      'specialProjects',
    ]) {
      unsupported(name);
    }
    return SnapshotEvidence._(Map.unmodifiable(fields));
  }
}
