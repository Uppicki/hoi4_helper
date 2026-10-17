import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'telemetry_catalog.dart';
import 'player_world.dart';

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
    this.rawWorld,
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

  /// Untrusted source data; world widgets receive only a knowledge projection.
  final RawPlayerWorld? rawWorld;

  /// Numeric UI consumers never receive the untrusted world payload.
  TelemetryObservation withoutRawWorld() => rawWorld == null
      ? this
      : TelemetryObservation(
          gameDate: gameDate,
          playerTag: playerTag,
          manpower: manpower,
          values: values,
          invalidKeys: invalidKeys,
          schemaVersion: schemaVersion,
          observationSchemaVersion: observationSchemaVersion,
          receivedAt: receivedAt,
          logSource: logSource,
        );

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

bool isValidTelemetryGameDate(String code) {
  final match = RegExp(
    r'^(\d{4})\.(\d{2})\.(\d{2})\.(\d{2})$',
  ).firstMatch(code);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return year >= 1 &&
      year <= 9999 &&
      month >= 1 &&
      month <= 12 &&
      day >= 1 &&
      day <= days[month - 1] &&
      hour <= 24;
}

/// Legacy one-line format, retained for older installed mods and log history.
TelemetryObservation? parseTelemetryLine(
  String line, {
  DateTime? receivedAt,
  String? logSource,
}) {
  final prefix = _logPrefix.firstMatch(line);
  if (prefix == null || !isValidTelemetryGameDate(prefix.group(1)!)) {
    return null;
  }
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

enum TelemetryStreamStatus {
  noLog,
  noModRecords,
  incompleteFrame,
  completeObservation,
  waitingNextDay,
}

class TelemetryLogPoll {
  const TelemetryLogPoll({
    required this.latest,
    required this.receivedNewLine,
    required this.status,
    required this.historical,
  });

  final TelemetryObservation? latest;
  final bool receivedNewLine;
  final TelemetryStreamStatus status;
  final bool historical;
}

class _Frame {
  _Frame(
    this.date,
    this.tag,
    this.parts,
    this.manpower, {
    required this.version,
    this.scopeId,
    this.policyId,
  });
  final String date, tag;
  final int parts, manpower, version;
  final String? scopeId, policyId;
  final Map<int, Map<String, String>> data = {};
  final Map<String, RawPlayerRelation> relations = {};
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
  TelemetryLogReader(this.file, {this.afterLengthMeasured});

  final File file;

  /// Allows a test to change the file between measuring and reading.
  final Future<void> Function()? afterLengthMeasured;
  int? _offset;
  String _pending = '';
  TelemetryObservation? _latest;
  _Frame? _frame;
  bool _seenMod = false;
  bool _incomplete = false;
  bool _historical = false;
  bool _skipFirstLine = false;
  List<int> _head = const [];
  List<int> _middle = const [];
  List<int> _tail = const [];
  DateTime? _modified;
  DateTime? _changed;

  void _reset() {
    _offset = null;
    _pending = '';
    _latest = null;
    _frame = null;
    _seenMod = false;
    _incomplete = false;
    _historical = false;
    _skipFirstLine = false;
    _head = const [];
    _middle = const [];
    _tail = const [];
    _modified = null;
    _changed = null;
  }

  TelemetryLogPoll _result(bool receivedNewLine, {bool noLog = false}) =>
      TelemetryLogPoll(
        latest: _latest,
        receivedNewLine: receivedNewLine,
        historical: _historical,
        status: noLog
            ? TelemetryStreamStatus.noLog
            : _frame != null || _incomplete || _pending.contains('HOI4_HELPER_')
            ? TelemetryStreamStatus.incompleteFrame
            : receivedNewLine
            ? TelemetryStreamStatus.completeObservation
            : _latest != null
            ? TelemetryStreamStatus.waitingNextDay
            : _seenMod
            ? TelemetryStreamStatus.incompleteFrame
            : TelemetryStreamStatus.noModRecords,
      );

  void _startRecord(String date, String tag) {
    final latest = _latest;
    if (latest != null &&
        (tag != latest.playerTag || date.compareTo(latest.gameDate) <= 0)) {
      _latest = null;
      _historical = false;
    }
  }

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

  TelemetryObservation? _readFramed(String line, String logSource) {
    final prefix = _logPrefix.firstMatch(line);
    if (prefix == null) {
      _frame = null;
      _incomplete = true;
      return null;
    }
    final body = line.substring(prefix.end).trimRight();
    final record = RegExp(r'^HOI4_HELPER_V([23])\|').firstMatch(body);
    if (record == null) {
      _frame = null;
      _incomplete = true;
      return null;
    }
    final version = int.parse(record.group(1)!);
    _seenMod = true;
    if (!isValidTelemetryGameDate(prefix.group(1)!)) {
      _frame = null;
      _incomplete = true;
      return null;
    }
    final fields = _fields(body.substring(record.end));
    if (fields == null) {
      _frame = null;
      _incomplete = true;
      return null;
    }
    final date = prefix.group(1)!;
    final tag = fields['tag'];
    if (tag == null || !_tag.hasMatch(tag)) {
      _frame = null;
      _incomplete = true;
      return null;
    }
    if (fields['phase'] != 'begin' && _frame?.version != version) {
      _frame = null;
      _incomplete = true;
      return null;
    }
    switch (fields['phase']) {
      case 'begin':
        _startRecord(date, tag);
        final parts = int.tryParse(fields['parts'] ?? '');
        final manpower = int.tryParse(fields['manpower'] ?? '');
        _frame =
            parts != null &&
                parts > 0 &&
                parts <= 100 &&
                manpower != null &&
                manpower >= 0 &&
                fields.length == (version == 3 ? 6 : 4) &&
                (version != 3 ||
                    ((fields['world']?.isNotEmpty ?? false) &&
                        (fields['policy']?.isNotEmpty ?? false))) &&
                telemetryMetrics['manpower']!.domain.accepts(
                  manpower.toDouble(),
                )
            ? _Frame(
                date,
                tag,
                parts,
                manpower,
                version: version,
                scopeId: fields['world'],
                policyId: fields['policy'],
              )
            : null;
        _incomplete = true;
        return null;
      case 'data':
        final frame = _frame;
        final part = int.tryParse(fields['part'] ?? '');
        if (frame == null ||
            fields.length < 4 ||
            frame.date != date ||
            frame.tag != tag ||
            part == null ||
            part < 0 ||
            part >= frame.parts ||
            frame.data.containsKey(part)) {
          _frame = null;
          _incomplete = true;
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
      case 'relation':
        final frame = _frame;
        final other = fields['other'];
        if (version != 3 ||
            frame == null ||
            frame.date != date ||
            frame.tag != tag ||
            other == null ||
            !_tag.hasMatch(other) ||
            other == tag ||
            frame.relations.containsKey(other) ||
            frame.relations.length >= 10000) {
          _frame = null;
          _incomplete = true;
          return null;
        }
        frame.relations[other] = RawPlayerRelation(other, {
          for (final entry in fields.entries)
            if (entry.key != 'phase' &&
                entry.key != 'tag' &&
                entry.key != 'other')
              entry.key: entry.value,
        });
        return null;
      case 'end':
        final frame = _frame;
        _frame = null;
        final opponents = version == 3
            ? _number(
                fields['enemies'] ?? '',
                telemetryMetrics['faction_members']!,
              )
            : null;
        if (frame == null ||
            frame.date != date ||
            frame.tag != tag ||
            int.tryParse(fields['parts'] ?? '') != frame.parts ||
            frame.data.length != frame.parts ||
            fields.length != (version == 3 ? 4 : 3) ||
            (version == 3 &&
                (opponents == null ||
                    opponents > 10000 ||
                    opponents != frame.relations.length))) {
          _incomplete = true;
          return null;
        }
        final values = <String, double>{};
        final invalidKeys = <String>{};
        final seen = <String>{};
        for (var part = 0; part < frame.parts; part++) {
          final data = frame.data[part];
          if (data == null) {
            _incomplete = true;
            return null;
          }
          for (final entry in data.entries) {
            if (!seen.add(entry.key)) {
              _incomplete = true;
              return null;
            }
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
        _incomplete = false;
        return TelemetryObservation(
          gameDate: frame.date,
          playerTag: frame.tag,
          manpower: frame.manpower,
          values: Map.unmodifiable(values),
          invalidKeys: Set.unmodifiable(invalidKeys),
          schemaVersion: version,
          rawWorld: version == 3
              ? RawPlayerWorld(
                  scopeId: frame.scopeId!,
                  policyId: frame.policyId!,
                  relations: frame.relations.values,
                )
              : null,
          receivedAt: DateTime.now(),
          logSource: logSource,
        );
      default:
        _frame = null;
        _incomplete = true;
        return null;
    }
  }

  Future<List<int>> _sample(
    RandomAccessFile handle,
    int start,
    int count,
  ) async {
    await handle.setPosition(start);
    return handle.read(count);
  }

  bool _same(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Future<void> _captureWitness(RandomAccessFile handle, int offset) async {
    _head = await _sample(handle, 0, math.min(256, offset));
    final middleStart = math.max(0, offset ~/ 2 - 128);
    _middle = await _sample(
      handle,
      middleStart,
      math.min(256, offset - middleStart),
    );
    _tail = await _sample(
      handle,
      math.max(0, offset - 256),
      math.min(256, offset),
    );
  }

  Future<bool> _matchesWitness(RandomAccessFile handle, int offset) async {
    if (await handle.length() < offset) return false;
    final head = await _sample(handle, 0, _head.length);
    final middleStart = math.max(0, offset ~/ 2 - 128);
    final middle = await _sample(handle, middleStart, _middle.length);
    final tail = await _sample(handle, offset - _tail.length, _tail.length);
    return _same(head, _head) && _same(middle, _middle) && _same(tail, _tail);
  }

  Future<TelemetryLogPoll> poll() async {
    RandomAccessFile? handle;
    try {
      if (!await file.exists()) {
        _reset();
        return _result(false, noLog: true);
      }
      handle = await file.open(mode: FileMode.read);
      final size = await handle.length();
      final stat = await file.stat();
      final modified = stat.modified;
      if (_offset != null &&
          (size < _offset! ||
              (Platform.isWindows && stat.changed != _changed) ||
              (size == _offset && modified != _modified) ||
              !await _matchesWitness(handle, _offset!))) {
        _reset();
      }
      final initial = _offset == null;
      if (initial) {
        _offset = math.max(0, size - 65536);
        _skipFirstLine = _offset! > 0;
      }
      final start = _offset!;
      final count = math.min(65536, size - start);
      if (count == 0) {
        _modified = modified;
        _changed = stat.changed;
        return _result(false);
      }
      await afterLengthMeasured?.call();
      await handle.setPosition(start);
      final bytes = await handle.read(count);
      if (bytes.length != count ||
          await handle.length() < size ||
          (!initial && !await _matchesWitness(handle, start))) {
        _reset();
        return _result(false);
      }
      final nextOffset = start + count;
      await _captureWitness(handle, nextOffset);
      // A replaced path can point to a different file while the old handle
      // remains readable. Check the current path before accepting its bytes.
      final current = await file.open(mode: FileMode.read);
      try {
        if (!await _matchesWitness(current, nextOffset)) {
          _reset();
          return _result(false);
        }
      } finally {
        await current.close();
      }
      final afterRead = await file.stat();
      if (Platform.isWindows && afterRead.changed != stat.changed) {
        _reset();
        return _result(false);
      }
      _offset = nextOffset;
      _modified = afterRead.modified;
      _changed = afterRead.changed;
      var chunk = _pending + utf8.decode(bytes, allowMalformed: true);
      if (_skipFirstLine) {
        final firstNewline = chunk.indexOf('\n');
        if (firstNewline < 0) return _result(false);
        chunk = chunk.substring(firstNewline + 1);
        _skipFirstLine = false;
      }
      final lastNewline = chunk.lastIndexOf('\n');
      if (lastNewline < 0) {
        _pending = chunk.length <= 16384 ? chunk : '';
        if (chunk.length > 16384) {
          _frame = null;
          _incomplete = true;
        }
        return _result(false);
      }
      _pending = chunk.substring(lastNewline + 1);
      if (_pending.length > 16384) {
        _pending = '';
        _frame = null;
        _incomplete = true;
      }
      var receivedNewLine = false;
      final logSource = file.absolute.path;
      for (final line in chunk.substring(0, lastNewline).split('\n')) {
        final trimmed = line.trimRight();
        if (!trimmed.contains('HOI4_HELPER_')) continue;
        _seenMod = true;
        final observation = parseTelemetryLine(
          trimmed,
          receivedAt: DateTime.now(),
          logSource: logSource,
        );
        if (observation != null) {
          _startRecord(observation.gameDate, observation.playerTag);
          _frame = null;
          _incomplete = false;
          _latest = observation;
          _historical = initial;
          receivedNewLine = !initial;
        } else if (RegExp(r'HOI4_HELPER_V[23]\|').hasMatch(trimmed)) {
          final complete = _readFramed(trimmed, logSource);
          if (complete != null) {
            _latest = complete;
            _historical = initial;
            receivedNewLine = !initial;
          }
        } else {
          _frame = null;
          _incomplete = true;
        }
      }
      return _result(receivedNewLine);
    } on FileSystemException {
      _reset();
      return _result(false, noLog: true);
    } finally {
      await handle?.close();
    }
  }
}
