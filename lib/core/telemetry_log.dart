import 'dart:convert';
import 'dart:io';

import 'telemetry_catalog.dart';

/// A display-only observation. Telemetry has no verified save or campaign ID.
class TelemetryObservation {
  const TelemetryObservation({
    required this.gameDate,
    required this.playerTag,
    required this.manpower,
    this.values = const {},
    this.schemaVersion = 1,
  });

  final String gameDate;
  final String playerTag;
  final int manpower;
  final Map<String, double> values;
  final int schemaVersion;

  double? value(String key) => values[key];

  int? count(String key) {
    final value = values[key];
    return value == null || !value.isFinite ? null : value.round();
  }
}

final _logPrefix = RegExp(
  r'^\[[^\]]+\]\[(\d{4}\.\d{2}\.\d{2}\.\d{2})\]\[[^\]]+\]: ',
);
final _v1 = RegExp(
  r'^HOI4_HELPER_V1\|date=[^|]*\|tag=([A-Z0-9]{3})\|manpower=(\d+)\s*$',
);
final _tag = RegExp(r'^[A-Z0-9]{3}$');
final _fieldName = RegExp(r'^[a-z_][a-z_0-9]*$');

/// Legacy one-line format, retained for older installed mods and log history.
TelemetryObservation? parseTelemetryLine(String line) {
  final prefix = _logPrefix.firstMatch(line);
  if (prefix == null) return null;
  final match = _v1.firstMatch(line.substring(prefix.end));
  if (match == null) return null;
  final manpower = int.tryParse(match.group(2)!);
  if (manpower == null) return null;
  return TelemetryObservation(
    gameDate: prefix.group(1)!,
    playerTag: match.group(1)!,
    manpower: manpower,
  );
}

class TelemetryLogPoll {
  const TelemetryLogPoll({required this.latest, required this.receivedNewLine});
  final TelemetryObservation? latest;
  final bool receivedNewLine;
}

class _Frame {
  _Frame(this.date, this.tag, this.parts, this.manpower);
  final String date, tag;
  final int parts, manpower;
  final Map<int, Map<String, String>> data = {};
}

Map<String, String>? _fields(String text) {
  final result = <String, String>{};
  for (final field in text.split('|')) {
    final equals = field.indexOf('=');
    if (equals <= 0) return null;
    final key = field.substring(0, equals);
    if (!_fieldName.hasMatch(key) || result.containsKey(key)) return null;
    result[key] = field.substring(equals + 1);
  }
  return result;
}

/// Parses HOI4's localized number formatting without turning bad values into 0.
double? _number(String raw, TelemetryMetric metric) {
  final value = raw.trim().replaceAll(RegExp(r'[\s\u00a0\u202f]'), '');
  if (!RegExp(r'^[-+]?[0-9][0-9.,]*$').hasMatch(value)) return null;
  String normalized = value;
  final comma = normalized.lastIndexOf(',');
  final dot = normalized.lastIndexOf('.');
  if (comma >= 0 && dot >= 0) {
    final decimal = comma > dot ? ',' : '.';
    final grouping = decimal == ',' ? '.' : ',';
    normalized = normalized.replaceAll(grouping, '').replaceAll(decimal, '.');
  } else if (metric.format == TelemetryFormat.count) {
    // Count fields are emitted with |0; a three-digit group is a separator.
    normalized = normalized.replaceAll(RegExp(r'[.,]'), '');
  } else if (comma >= 0) {
    normalized = normalized.replaceAll(',', '.');
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null || !parsed.isFinite) return null;
  final result = parsed * metric.scale;
  return result.isFinite ? result : null;
}

/// Follows only appended bytes. A V2 observation is published after every
/// numbered part and the end marker arrive for the same country and game day.
class TelemetryLogReader {
  TelemetryLogReader(this.file);

  final File file;
  int? _offset;
  String _pending = '';
  TelemetryObservation? _latest;
  _Frame? _frame;

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

  TelemetryObservation? _readV2(String line) {
    final prefix = _logPrefix.firstMatch(line);
    if (prefix == null) return null;
    final body = line.substring(prefix.end).trimRight();
    if (!body.startsWith('HOI4_HELPER_V2|')) return null;
    final fields = _fields(body.substring('HOI4_HELPER_V2|'.length));
    if (fields == null) {
      _frame = null;
      return null;
    }
    final date = prefix.group(1)!;
    final tag = fields['tag'];
    if (tag == null || !_tag.hasMatch(tag)) {
      _frame = null;
      return null;
    }
    switch (fields['phase']) {
      case 'begin':
        final parts = int.tryParse(fields['parts'] ?? '');
        final manpower = int.tryParse(fields['manpower'] ?? '');
        _frame = parts != null && parts > 0 && parts <= 100 && manpower != null
            ? _Frame(date, tag, parts, manpower)
            : null;
        return null;
      case 'data':
        final frame = _frame;
        final part = int.tryParse(fields['part'] ?? '');
        if (frame == null ||
            frame.date != date ||
            frame.tag != tag ||
            part == null ||
            part < 0 ||
            part >= frame.parts ||
            frame.data.containsKey(part)) {
          _frame = null;
          return null;
        }
        frame.data[part] = {
          for (final entry in fields.entries)
            if (entry.key != 'phase' &&
                entry.key != 'tag' &&
                entry.key != 'part')
              entry.key: entry.value,
        };
        return null;
      case 'end':
        final frame = _frame;
        _frame = null;
        if (frame == null ||
            frame.date != date ||
            frame.tag != tag ||
            int.tryParse(fields['parts'] ?? '') != frame.parts ||
            frame.data.length != frame.parts) {
          return null;
        }
        final values = <String, double>{};
        final seen = <String>{};
        for (var part = 0; part < frame.parts; part++) {
          final data = frame.data[part];
          if (data == null) return null;
          for (final entry in data.entries) {
            if (!seen.add(entry.key)) return null;
            final metric = telemetryMetrics[entry.key];
            if (metric == null) continue;
            final number = _number(entry.value, metric);
            if (number != null) values[entry.key] = number;
          }
        }
        return TelemetryObservation(
          gameDate: frame.date,
          playerTag: frame.tag,
          manpower: frame.manpower,
          values: Map.unmodifiable(values),
          schemaVersion: 2,
        );
      default:
        _frame = null;
        return null;
    }
  }

  Future<TelemetryLogPoll> poll() async {
    if (!await file.exists()) {
      _offset = null;
      _pending = '';
      _frame = null;
      _latest = null;
      return const TelemetryLogPoll(latest: null, receivedNewLine: false);
    }
    final size = await file.length();
    final initial = _offset == null || size < _offset!;
    if (initial) {
      _offset = size > 65536 ? size - 65536 : 0;
      _pending = '';
      _frame = null;
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
      _pending = chunk.length < 16384 ? chunk : '';
      return TelemetryLogPoll(latest: _latest, receivedNewLine: false);
    }
    _pending = chunk.substring(lastNewline + 1);
    if (_pending.length > 16384) _pending = '';
    var receivedNewLine = false;
    for (final line in chunk.substring(0, lastNewline).split('\n')) {
      final trimmed = line.trimRight();
      final observation = parseTelemetryLine(trimmed) ?? _readV2(trimmed);
      if (observation == null) continue;
      _latest = observation;
      receivedNewLine = !initial;
    }
    return TelemetryLogPoll(latest: _latest, receivedNewLine: receivedNewLine);
  }
}
