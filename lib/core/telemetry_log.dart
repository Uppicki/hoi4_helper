import 'dart:convert';
import 'dart:io';

import 'telemetry_catalog.dart';

enum TelemetryValueStatus { value, missing, unsupported, invalid }

/// A display-only observation. Telemetry has no verified save or campaign ID.
class TelemetryObservation {
  static const currentObservationSchemaVersion = 1;

  const TelemetryObservation({
    required this.gameDate,
    required this.playerTag,
    required this.manpower,
    this.values = const {},
    this.invalidKeys = const {},
    this.schemaVersion = 1,
    this.observationSchemaVersion = currentObservationSchemaVersion,
    this.receivedAt,
    this.logSource,
  });

  final String gameDate;
  final String playerTag;
  final int manpower;
  final Map<String, double> values;
  final Set<String> invalidKeys;

  /// Version of the mod's log format (V1 or V2).
  final int schemaVersion;

  /// Version of the application's observation contract.
  final int observationSchemaVersion;

  /// Time the application accepted this record; historical lines are not live.
  final DateTime? receivedAt;
  final String? logSource;

  String? get campaignId => null;
  String? get saveId => null;

  double? value(String key) => schemaVersion == 1 && key == 'manpower'
      ? manpower.toDouble()
      : values[key];

  TelemetryValueStatus status(String key) {
    if (!telemetryMetrics.containsKey(key)) {
      return TelemetryValueStatus.unsupported;
    }
    if (invalidKeys.contains(key)) return TelemetryValueStatus.invalid;
    if (values.containsKey(key) || (schemaVersion == 1 && key == 'manpower')) {
      return TelemetryValueStatus.value;
    }
    return schemaVersion == 1
        ? TelemetryValueStatus.unsupported
        : TelemetryValueStatus.missing;
  }

  int? count(String key) {
    final number = value(key);
    return number == null || !number.isFinite ? null : number.round();
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
final _plainCount = RegExp(r'^[-+]?[0-9]+$');
final _dotGroupedCount = RegExp(r'^[-+]?[0-9]{1,3}(?:\.[0-9]{3})+$');
final _commaGroupedCount = RegExp(r'^[-+]?[0-9]{1,3}(?:,[0-9]{3})+$');
final _spaceGroupedCount = RegExp(
  r'^[-+]?[0-9]{1,3}(?:[ \u00a0\u202f][0-9]{3})+$',
);

/// Legacy one-line format, retained for older installed mods and log history.
TelemetryObservation? parseTelemetryLine(
  String line, {
  DateTime? receivedAt,
  String? logSource,
}) {
  final prefix = _logPrefix.firstMatch(line);
  if (prefix == null) return null;
  final match = _v1.firstMatch(line.substring(prefix.end));
  if (match == null) return null;
  final manpower = int.tryParse(match.group(2)!);
  if (manpower == null ||
      manpower < 0 ||
      !telemetryMetrics['manpower']!.domain.accepts(manpower.toDouble())) {
    return null;
  }
  return TelemetryObservation(
    gameDate: prefix.group(1)!,
    playerTag: match.group(1)!,
    manpower: manpower,
    receivedAt: receivedAt,
    logSource: logSource,
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
  final input = raw.trim();
  if (metric.format == TelemetryFormat.count &&
      !_plainCount.hasMatch(input) &&
      !_dotGroupedCount.hasMatch(input) &&
      !_commaGroupedCount.hasMatch(input) &&
      !_spaceGroupedCount.hasMatch(input)) {
    return null;
  }
  final value = input.replaceAll(RegExp(r'[\s\u00a0\u202f]'), '');
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
  return metric.domain.accepts(result) ? result : null;
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

  TelemetryObservation? _readV2(String line, String logSource) {
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
        _frame =
            parts != null &&
                parts > 0 &&
                parts <= 100 &&
                manpower != null &&
                manpower >= 0 &&
                telemetryMetrics['manpower']!.domain.accepts(
                  manpower.toDouble(),
                )
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
        final invalidKeys = <String>{};
        final seen = <String>{};
        for (var part = 0; part < frame.parts; part++) {
          final data = frame.data[part];
          if (data == null) return null;
          for (final entry in data.entries) {
            if (!seen.add(entry.key)) return null;
            final metric = telemetryMetrics[entry.key];
            if (metric == null) continue;
            final number = _number(entry.value, metric);
            if (number == null) {
              invalidKeys.add(entry.key);
            } else {
              values[entry.key] = number;
            }
          }
        }
        return TelemetryObservation(
          gameDate: frame.date,
          playerTag: frame.tag,
          manpower: frame.manpower,
          values: Map.unmodifiable(values),
          invalidKeys: Set.unmodifiable(invalidKeys),
          schemaVersion: 2,
          receivedAt: DateTime.now(),
          logSource: logSource,
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
    final logSource = file.absolute.path;
    for (final line in chunk.substring(0, lastNewline).split('\n')) {
      final trimmed = line.trimRight();
      final observation =
          parseTelemetryLine(
            trimmed,
            receivedAt: DateTime.now(),
            logSource: logSource,
          ) ??
          _readV2(trimmed, logSource);
      if (observation == null) continue;
      _latest = observation;
      receivedNewLine = !initial;
    }
    return TelemetryLogPoll(latest: _latest, receivedNewLine: receivedNewLine);
  }
}
