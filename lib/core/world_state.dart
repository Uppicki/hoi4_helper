import 'save_repository.dart';

/// The in-game date represented by a completed save, not the current wall time.
class GameDate implements Comparable<GameDate> {
  const GameDate(this.year, this.month, this.day, this.hour);

  static GameDate fromHoi4Code(int code) {
    final hours = code + 1;
    final year = hours ~/ (365 * 24) - 5000;
    var dayOfYear = (hours % (365 * 24)) ~/ 24;
    final hour = hours % 24;
    if (year < 1 || year > 9999) {
      throw const SaveReadException('Игровая дата в сохранении не распознана.');
    }
    const monthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    var month = 1;
    for (final length in monthLengths) {
      if (dayOfYear < length) {
        return GameDate(year, month, dayOfYear + 1, hour);
      }
      dayOfYear -= length;
      month++;
    }
    throw const SaveReadException('Игровая дата в сохранении не распознана.');
  }

  final int year;
  final int month;
  final int day;
  final int hour;

  @override
  int compareTo(GameDate other) {
    final byYear = year.compareTo(other.year);
    if (byYear != 0) return byYear;
    final byMonth = month.compareTo(other.month);
    if (byMonth != 0) return byMonth;
    final byDay = day.compareTo(other.day);
    return byDay != 0 ? byDay : hour.compareTo(other.hour);
  }

  @override
  String toString() {
    String two(int value) => value.toString().padLeft(2, '0');
    return '$year.${two(month)}.${two(day)} ${two(hour)}:00';
  }
}

/// Versioned identity of one completed save. Null means no reliable evidence.
class SnapshotIdentity {
  const SnapshotIdentity({
    required this.sourceId,
    required this.saveId,
    required this.playerTag,
    required this.gameDate,
    required this.gameVersion,
    this.campaignId,
    this.gameDataId,
  });

  static const schemaVersion = 1;

  /// Absolute source path for file-backed snapshots.
  final String? sourceId;

  /// SHA-256 of the entire save, not its filename or modification time.
  final String? saveId;

  /// Only set when a campaign identifier is verified from source data.
  final String? campaignId;
  final String? playerTag;
  final GameDate? gameDate;
  final String? gameVersion;

  /// Identity of installed game data and enabled mods, when verified.
  final String? gameDataId;

  /// A successor must have positive evidence of a shared campaign and data.
  /// This deliberately rejects unknown campaign identities.
  bool canFollow(SnapshotIdentity previous) {
    if (campaignId == null ||
        previous.campaignId == null ||
        campaignId != previous.campaignId ||
        playerTag == null ||
        playerTag != previous.playerTag ||
        gameDataId == null ||
        gameDataId != previous.gameDataId ||
        gameVersion == null ||
        gameVersion != previous.gameVersion ||
        gameDate == null ||
        previous.gameDate == null ||
        saveId == null ||
        saveId == previous.saveId) {
      return false;
    }
    return gameDate!.compareTo(previous.gameDate!) > 0;
  }
}

/// A verified snapshot from one source. Unknown fields remain null.
class WorldStateSnapshot {
  const WorldStateSnapshot({
    required this.sourceDescription,
    required this.readAt,
    this.gameDate,
    this.playerTag,
    this.ideology,
    this.difficulty,
    this.gameVersion,
    this.world,
    this.loadedSave,
    this.identity,
  });

  final String sourceDescription;
  final DateTime readAt;
  final GameDate? gameDate;
  final String? playerTag;
  final String? ideology;
  final String? difficulty;
  final String? gameVersion;
  final SaveWorldDetails? world;
  final LoadedSave? loadedSave;
  final SnapshotIdentity? identity;
}

/// Facts extracted from a completed save. Missing values stay null.
class SaveWorldDetails {
  const SaveWorldDetails({
    this.saveVersion,
    this.startDate,
    this.provinceCount,
    this.stateCount,
    this.factionCount,
    this.ironman,
    this.states = const {},
    this.stateOwners = const {},
    this.ownedStateCounts = const {},
    this.countries = const {},
  });

  final int? saveVersion;
  final GameDate? startDate;
  final int? provinceCount;
  final int? stateCount;
  final int? factionCount;
  final bool? ironman;
  final Map<int, StateWorldState> states;
  final Map<int, String> stateOwners;
  final Map<String, int> ownedStateCounts;
  final Map<String, CountryWorldState> countries;

  CountryWorldState? playerCountry(String? tag) =>
      tag == null ? null : countries[tag];
}

/// A state as stored in the save, before applying player-visibility rules.
class StateWorldState {
  const StateWorldState({
    required this.id,
    this.owner,
    this.availableManpower,
    this.lockedManpower,
    this.totalManpower,
    this.buildings = const {},
  });

  final int id;
  final String? owner;
  final int? availableManpower;
  final int? lockedManpower;
  final int? totalManpower;
  final Map<String, int> buildings;
}

class CountryWorldState {
  const CountryWorldState({
    required this.tag,
    this.capitalStateId,
    this.major,
    this.stability,
    this.warSupport,
    this.politicalPower,
    this.commandPower,
    this.researchSlots,
    this.shipCount,
    this.focusTree,
    this.currentFocus,
    this.divisionCount,
    this.fleetCount,
    this.militaryProductionLines,
    this.navalProductionLines,
    this.availableManpower,
    this.stateAvailableManpower,
    this.armyExperience,
    this.airExperience,
    this.civilianFactories,
    this.militaryFactories,
    this.dockyards,
    this.researchedTechnologies = const [],
    this.activeResearch = const [],
    this.completedFocuses = const [],
  });

  final String tag;
  final int? capitalStateId;
  final bool? major;
  final double? stability;
  final double? warSupport;
  final double? politicalPower;
  final double? commandPower;
  final int? researchSlots;
  final int? shipCount;
  final String? focusTree;
  final String? currentFocus;
  final int? divisionCount;
  final int? fleetCount;
  final int? militaryProductionLines;
  final int? navalProductionLines;
  final int? availableManpower;

  /// Sum of available population in owned states, not the army reserve.
  final int? stateAvailableManpower;
  final double? armyExperience;
  final double? airExperience;
  final int? civilianFactories;
  final int? militaryFactories;
  final int? dockyards;
  final List<String> researchedTechnologies;
  final List<String> activeResearch;
  final List<String> completedFocuses;
}
