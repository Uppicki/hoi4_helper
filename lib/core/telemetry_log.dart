import 'dart:convert';
import 'dart:io';

/// An observation emitted by the optional in-game telemetry mod.
/// It is not a verified save snapshot or a campaign identity.
class TelemetryObservation {
  const TelemetryObservation({
    required this.gameDate,
    required this.playerTag,
    required this.manpower,
  });

  final String gameDate;
  final String playerTag;
  final int manpower;
}

TelemetryObservation? parseTelemetryLine(String line) {
  final match = RegExp(
    r'^\[[^\]]+\]\[(\d{4}\.\d{2}\.\d{2}\.\d{2})\]\[[^\]]+\]: '
    r'HOI4_HELPER_V1\|date=[^|]*\|tag=([A-Z0-9]{3})\|manpower=(\d+)\s*$',
  ).firstMatch(line);
  if (match == null) return null;
  final manpower = int.tryParse(match.group(3)!);
  if (manpower == null) return null;
  return TelemetryObservation(
    gameDate: match.group(1)!,
    playerTag: match.group(2)!,
    manpower: manpower,
  );
}

class TelemetryLogPoll {
  const TelemetryLogPoll({required this.latest, required this.receivedNewLine});

  final TelemetryObservation? latest;
  final bool receivedNewLine;
}

/// Reads only the tail of game.log and then follows appended lines.
/// A partial line is never published. Truncation clears the previous value.
class TelemetryLogReader {
  TelemetryLogReader(this.file);

  final File file;
  int? _offset;
  String _pending = '';
  TelemetryObservation? _latest;

  static File? findDefaultLog() {
    final env = Platform.environment;
    final home = env['USERPROFILE'] ?? env['HOME'];
    if (home == null) return null;
    final candidates = <String>[
      '$home${Platform.pathSeparator}Documents',
      if (env['OneDrive'] case final oneDrive?)
        '$oneDrive${Platform.pathSeparator}Documents',
    ];
    for (final documents in candidates) {
      final file = File(
        '$documents${Platform.pathSeparator}Paradox Interactive'
        '${Platform.pathSeparator}Hearts of Iron IV'
        '${Platform.pathSeparator}logs${Platform.pathSeparator}game.log',
      );
      if (file.existsSync()) return file;
    }
    return null;
  }

  Future<TelemetryLogPoll> poll() async {
    if (!await file.exists()) {
      _offset = null;
      _pending = '';
      _latest = null;
      return const TelemetryLogPoll(latest: null, receivedNewLine: false);
    }
    final size = await file.length();
    final initial = _offset == null || size < _offset!;
    if (initial) {
      _offset = size > 65536 ? size - 65536 : 0;
      _pending = '';
      _latest = null;
    }
    if (size == _offset) {
      return TelemetryLogPoll(latest: _latest, receivedNewLine: false);
    }

    final handle = await file.open(mode: FileMode.read);
    late final List<int> bytes;
    try {
      await handle.setPosition(_offset!);
      bytes = await handle.read(size - _offset!);
    } finally {
      await handle.close();
    }
    _offset = size;
    final chunk = _pending + utf8.decode(bytes, allowMalformed: true);
    final lastNewline = chunk.lastIndexOf('\n');
    if (lastNewline < 0) {
      _pending = chunk;
      return TelemetryLogPoll(latest: _latest, receivedNewLine: false);
    }
    _pending = chunk.substring(lastNewline + 1);
    var receivedNewLine = false;
    for (final line in chunk.substring(0, lastNewline).split('\n')) {
      final observation = parseTelemetryLine(line.trimRight());
      if (observation == null) continue;
      _latest = observation;
      receivedNewLine = !initial;
    }
    return TelemetryLogPoll(latest: _latest, receivedNewLine: receivedNewLine);
  }
}
