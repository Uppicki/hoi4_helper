import 'save_repository.dart';

/// The in-game date represented by a completed save, not the current wall time.
class GameDate {
  const GameDate(this.year, this.month, this.day, this.hour);

  final int year;
  final int month;
  final int day;
  final int hour;

  @override
  String toString() {
    String two(int value) => value.toString().padLeft(2, '0');
    return '$year.${two(month)}.${two(day)} ${two(hour)}:00';
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
    this.loadedSave,
  });

  final String sourceDescription;
  final DateTime readAt;
  final GameDate? gameDate;
  final String? playerTag;
  final String? ideology;
  final String? difficulty;
  final String? gameVersion;
  final LoadedSave? loadedSave;
}
