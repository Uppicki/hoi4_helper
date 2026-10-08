import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'save_repository.dart';
import 'world_state.dart';

/// Parses the HOI4 binary token stream without retaining its full tree.
/// Only fields whose IDs and nesting have been checked against local saves are
/// projected into [SaveWorldDetails]. Unknown fields are still traversed.
class BinarySaveWorldParser {
  BinarySaveWorldParser._(this._bytes) : _data = ByteData.sublistView(_bytes);

  static const supportedSaveVersions = {31};

  static Future<SaveWorldDetails> readFile(
    SaveFile save, {
    String? expectedSha256,
  }) => Isolate.run(() async {
    final file = File(save.path);
    final before = await file.stat();
    if (before.type != FileSystemEntityType.file ||
        before.size != save.size ||
        before.modified != save.modified) {
      throw const SaveReadException(
        'Сохранение изменилось после выбора. Обновите список и загрузите его снова.',
      );
    }
    final bytes = await file.readAsBytes();
    final after = await file.stat();
    if (after.type != FileSystemEntityType.file ||
        before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed ||
        bytes.length != after.size) {
      throw const SaveReadException(
        'Сохранение изменилось во время разбора. Загрузите его снова.',
      );
    }
    if (expectedSha256 != null &&
        sha256.convert(bytes).toString() != expectedSha256) {
      throw const SaveReadException(
        'Сохранение изменилось между чтением и разбором. Загрузите его снова.',
      );
    }
    return BinarySaveWorldParser.parse(bytes);
  });

  static SaveWorldDetails parse(Uint8List bytes) =>
      BinarySaveWorldParser._(bytes)._parse();

  static const _equal = 0x0001;
  static const _open = 0x0003;
  static const _close = 0x0004;
  static const _i32 = 0x000C;
  static const _fixed = 0x000D;
  static const _bool = 0x000E;
  static const _quoted = 0x000F;
  static const _u32 = 0x0014;
  static const _unquoted = 0x0017;
  static const _f64 = 0x0167;
  static const _u64 = 0x029C;
  static const _i64 = 0x0317;

  static const _provinces = 0x2830;
  static const _states = 0x2E3B;
  static const _owner = 0x283E;
  static const _buildings = 0x2F59;
  static const _buildingLevel = 0x286C;
  static const _manpowerPool = 0x3635;
  static const _available = 0x2FE8;
  static const _locked = 0x2DE4;
  static const _total = 0x2A12;
  static const _countries = 0x2D49;
  static const _faction = 0x2A7D;
  static const _ironman = 0x2D13;
  static const _saveVersion = 0x349D;
  static const _startDate = 0x28E0;

  static const _capital = 0x284B;
  static const _major = 0x2BE9;
  static const _stability = 0x2883;
  static const _warSupport = 0x37FD;
  static const _commandPower = 0x3883;
  static const _researchSlot = 0x2F71;
  static const _numShips = 0x35BF;
  static const _focusTree = 0x33B8;
  static const _politics = 0x2FFA;
  static const _politicalPower = 0x301E;
  static const _technology = 0x285F;
  static const _technologies = 0x2E5D;
  static const _slots = 0x2E67;
  static const _units = 0x2FAA;
  static const _division = 0x01D7;
  static const _fleet = 0x3B34;
  static const _production = 0x2FB4;
  static const _militaryLines = 0x2FB0;
  static const _navalLines = 0x2FB1;
  static const _focus = 0x33B7;
  static const _current = 0x2B75;
  static const _completed = 0x3127;
  static const _experienceStatus = 0x418D;
  static const _armyExperience = 0x3392;
  static const _airExperience = 0x3394;

  final Uint8List _bytes;
  final ByteData _data;
  final Map<String, _CountryBuilder> _countriesByTag = {};
  final Set<int> _provinceIds = {};
  final Set<int> _stateIds = {};
  final Map<int, _StateBuilder> _statesById = {};
  int _offset = 7;
  int? _version;
  GameDate? _gameStartDate;
  int? _factionCount;
  bool? _isIronman;
  bool _sawProvinces = false;
  bool _sawStates = false;

  SaveWorldDetails _parse() {
    if (_bytes.length < 7 ||
        String.fromCharCodes(_bytes.sublist(0, 7)) != 'HOI4bin') {
      throw const SaveReadException(
        'Формат сохранения пока не поддерживается.',
      );
    }
    final path = <_BinaryToken?>[];
    _BinaryToken? previous;
    while (_offset < _bytes.length) {
      final token = _readToken();
      if (token.id == _equal) {
        final key = previous;
        if (key == null) {
          throw const SaveReadException('Структура сохранения повреждена.');
        }
        final value = _readToken();
        _onField(path, key, value);
        if (value.id == _open) path.add(key);
        previous = null;
      } else if (token.id == _open) {
        path.add(previous);
        previous = null;
      } else if (token.id == _close) {
        if (path.isEmpty) {
          throw const SaveReadException('Структура сохранения повреждена.');
        }
        path.removeLast();
        previous = null;
      } else {
        previous = token;
      }
    }
    if (path.isNotEmpty) {
      throw const SaveReadException(
        'Заголовок или структура сохранения неполны.',
      );
    }
    if (_version == null) {
      throw const SaveReadException('Версия бинарного сохранения не найдена.');
    }

    final stateOwners = <int, String>{};
    final ownedCounts = <String, int>{};
    final statesByOwner = <String, List<_StateBuilder>>{};
    for (final state in _statesById.values) {
      final owner = state.owner;
      if (owner == null) continue;
      stateOwners[state.id] = owner;
      ownedCounts.update(owner, (count) => count + 1, ifAbsent: () => 1);
      statesByOwner.putIfAbsent(owner, () => []).add(state);
    }
    for (final entry in statesByOwner.entries) {
      final country = _countriesByTag[entry.key];
      if (country == null) continue;
      final owned = entry.value;
      if (owned.every((state) => state.sawBuildings)) {
        int sum(String name) => owned.fold<int>(
          0,
          (total, state) => total + (state.buildings[name] ?? 0),
        );
        country.civilianFactories = sum('industrial_complex');
        country.militaryFactories = sum('arms_factory');
        country.dockyards = sum('dockyard');
      }
      if (owned.every((state) => state.availableManpower != null)) {
        country.stateAvailableManpower = owned.fold<int>(
          0,
          (total, state) => total + state.availableManpower!,
        );
      }
    }
    return SaveWorldDetails(
      saveVersion: _version,
      startDate: _gameStartDate,
      provinceCount: _sawProvinces ? _provinceIds.length : null,
      stateCount: _sawStates ? _stateIds.length : null,
      factionCount: _factionCount,
      ironman: _isIronman,
      states: Map.unmodifiable(
        _statesById.map((id, value) => MapEntry(id, value.build())),
      ),
      stateOwners: Map.unmodifiable(stateOwners),
      ownedStateCounts: Map.unmodifiable(ownedCounts),
      countries: Map.unmodifiable(
        _countriesByTag.map((tag, value) => MapEntry(tag, value.build())),
      ),
    );
  }

  void _onField(
    List<_BinaryToken?> path,
    _BinaryToken key,
    _BinaryToken value,
  ) {
    if (path.isEmpty) {
      switch (key.id) {
        case _saveVersion:
          final version = value.intValue;
          if (version == null || !supportedSaveVersions.contains(version)) {
            throw SaveReadException(
              'Версия бинарного сохранения ${version ?? 'неизвестна'} пока не '
              'поддерживается. Поддерживается версия 31.',
            );
          }
          _version = version;
        case _startDate:
          final code = value.intValue;
          if (code != null) _gameStartDate = GameDate.fromHoi4Code(code);
        case _provinces:
          if (value.id == _open) _sawProvinces = true;
        case _states:
          if (value.id == _open) _sawStates = true;
        case _faction:
          if (value.id == _open) _factionCount = (_factionCount ?? 0) + 1;
        case _ironman:
          _isIronman = value.boolValue;
      }
      return;
    }

    final root = path[0]?.id;
    if (path.length == 1 && root == _provinces) {
      final id = key.intValue;
      if (id != null) _provinceIds.add(id);
      return;
    }
    if (path.length == 1 && root == _states) {
      final id = key.intValue;
      if (id != null) {
        _stateIds.add(id);
        if (value.id == _open) _statesById[id] = _StateBuilder(id);
      }
      return;
    }
    if (root == _states && path.length >= 2) {
      final id = path[1]?.intValue;
      final state = id == null ? null : _statesById[id];
      if (state == null) return;
      if (path.length == 2) {
        if (key.id == _owner) {
          final owner = value.stringValue;
          state.owner = owner != null && _tagPattern.hasMatch(owner)
              ? owner
              : null;
        } else if (key.id == _buildings && value.id == _open) {
          state.sawBuildings = true;
        }
      } else if (path.length == 3 && path[2]?.id == _manpowerPool) {
        switch (key.id) {
          case _available:
            state.availableManpower = value.intValue;
          case _locked:
            state.lockedManpower = value.intValue;
          case _total:
            state.totalManpower = value.intValue;
        }
      } else if (path.length == 4 &&
          path[2]?.id == _buildings &&
          key.id == _buildingLevel) {
        final building = _buildingName(path[3]);
        final level = value.intValue;
        if (building != null && level != null) {
          state.buildings[building] = level;
        }
      }
      return;
    }
    if (root != _countries) return;
    if (path.length == 1) {
      final tag = key.stringValue;
      if (value.id == _open && tag != null && _tagPattern.hasMatch(tag)) {
        _countriesByTag.putIfAbsent(tag, () => _CountryBuilder(tag));
      }
      return;
    }
    final tag = path[1]?.stringValue;
    if (tag == null) return;
    final country = _countriesByTag[tag];
    if (country == null) return;
    if (path.length == 2) {
      switch (key.id) {
        case _capital:
          country.capitalStateId = value.intValue;
        case _major:
          country.major = value.boolValue;
        case _stability:
          country.stability = value.fixedValue;
        case _warSupport:
          country.warSupport = value.fixedValue;
        case _commandPower:
          country.commandPower = value.fixedValue;
        case _researchSlot:
          country.researchSlots = value.intValue;
        case _numShips:
          country.shipCount = value.intValue;
        case _focusTree:
          country.focusTree = value.stringValue;
        case _units:
          if (value.id == _open) country.sawUnits = true;
        case _production:
          if (value.id == _open) country.sawProduction = true;
      }
      return;
    }
    final section = path[2]?.id;
    if (path.length == 3) {
      switch (section) {
        case _politics:
          if (key.id == _politicalPower) {
            country.politicalPower = value.fixedValue;
          }
        case _units:
          if (key.id == _division && value.id == _open) {
            country.divisionCount++;
          } else if (key.id == _fleet && value.id == _open) {
            country.fleetCount++;
          }
        case _production:
          if (key.id == _militaryLines && value.id == _open) {
            country.militaryProductionLines++;
          } else if (key.id == _navalLines && value.id == _open) {
            country.navalProductionLines++;
          }
        case _focus:
          if (key.id == _current) {
            country.currentFocus = value.stringValue;
          } else if (key.id == _completed) {
            final name = value.stringValue;
            if (name != null) country.completedFocuses.add(name);
          }
        case _experienceStatus:
          if (key.id == _armyExperience) {
            country.armyExperience = value.fixedValue;
          } else if (key.id == _airExperience) {
            country.airExperience = value.fixedValue;
          }
      }
      return;
    }
    if (path.length == 4 && section == _technology) {
      final name = key.stringValue;
      if (name == null) return;
      if (path[3]?.id == _technologies) {
        country.researchedTechnologies.add(name);
      } else if (path[3]?.id == _slots) {
        country.activeResearch.add(name);
      }
    }
  }

  static final _tagPattern = RegExp(r'^[A-Z0-9]{3}$');

  static String? _buildingName(_BinaryToken? token) {
    if (token == null) return null;
    if (token.stringValue case final name?) return name;
    return switch (token.id) {
      0x2FAB => 'infrastructure',
      0x2FB6 => 'air_base',
      0x4BF6 => 'dockyard',
      _ =>
        token.id >= 0x0100
            ? '0x${token.id.toRadixString(16).padLeft(4, '0')}'
            : null,
    };
  }

  _BinaryToken _readToken() {
    _ensure(2);
    final id = _data.getUint16(_offset, Endian.little);
    _offset += 2;
    switch (id) {
      case _quoted:
      case _unquoted:
        _ensure(2);
        final length = _data.getUint16(_offset, Endian.little);
        _offset += 2;
        _ensure(length);
        final value = utf8.decode(
          _bytes.sublist(_offset, _offset + length),
          allowMalformed: true,
        );
        _offset += length;
        return _BinaryToken(id, value);
      case _i32:
        _ensure(4);
        final value = _data.getInt32(_offset, Endian.little);
        _offset += 4;
        return _BinaryToken(id, value);
      case _u32:
        _ensure(4);
        final value = _data.getUint32(_offset, Endian.little);
        _offset += 4;
        return _BinaryToken(id, value);
      case _i64:
      case _u64:
      case _f64:
        _ensure(8);
        final value = _data.getInt64(_offset, Endian.little);
        _offset += 8;
        return _BinaryToken(id, value);
      case _fixed:
        final width = (_version ?? 30) >= 30 ? 8 : 4;
        _ensure(width);
        final value = width == 8
            ? _data.getInt64(_offset, Endian.little) / 100000.0
            : _data.getInt32(_offset, Endian.little) / 1000.0;
        _offset += width;
        return _BinaryToken(id, value);
      case _bool:
        _ensure(1);
        final value = _bytes[_offset++] != 0;
        return _BinaryToken(id, value);
      default:
        return _BinaryToken(id, null);
    }
  }

  void _ensure(int count) {
    if (count < 0 || count > _bytes.length - _offset) {
      throw const SaveReadException(
        'Данные сохранения обрываются внутри токена.',
      );
    }
  }
}

class _BinaryToken {
  const _BinaryToken(this.id, this.value);

  final int id;
  final Object? value;

  int? get intValue => value is int ? value as int : null;
  String? get stringValue => value is String ? value as String : null;
  bool? get boolValue => value is bool ? value as bool : null;
  double? get fixedValue =>
      id == 0x000D && value is double ? value as double : null;
}

class _CountryBuilder {
  _CountryBuilder(this.tag);

  final String tag;
  int? capitalStateId;
  bool? major;
  double? stability;
  double? warSupport;
  double? politicalPower;
  double? commandPower;
  int? researchSlots;
  int? shipCount;
  String? focusTree;
  String? currentFocus;
  int divisionCount = 0;
  int fleetCount = 0;
  int militaryProductionLines = 0;
  int navalProductionLines = 0;
  bool sawUnits = false;
  bool sawProduction = false;
  int? stateAvailableManpower;
  int? civilianFactories;
  int? militaryFactories;
  int? dockyards;
  double? armyExperience;
  double? airExperience;
  final List<String> researchedTechnologies = [];
  final List<String> activeResearch = [];
  final List<String> completedFocuses = [];

  CountryWorldState build() => CountryWorldState(
    tag: tag,
    capitalStateId: capitalStateId,
    major: major,
    stability: stability,
    warSupport: warSupport,
    politicalPower: politicalPower,
    commandPower: commandPower,
    researchSlots: researchSlots,
    shipCount: shipCount,
    focusTree: focusTree,
    currentFocus: currentFocus,
    divisionCount: sawUnits ? divisionCount : null,
    fleetCount: sawUnits ? fleetCount : null,
    militaryProductionLines: sawProduction ? militaryProductionLines : null,
    navalProductionLines: sawProduction ? navalProductionLines : null,
    stateAvailableManpower: stateAvailableManpower,
    civilianFactories: civilianFactories,
    militaryFactories: militaryFactories,
    dockyards: dockyards,
    armyExperience: armyExperience,
    airExperience: airExperience,
    researchedTechnologies: List.unmodifiable(researchedTechnologies),
    activeResearch: List.unmodifiable(activeResearch),
    completedFocuses: List.unmodifiable(completedFocuses),
  );
}

class _StateBuilder {
  _StateBuilder(this.id);

  final int id;
  String? owner;
  bool sawBuildings = false;
  int? availableManpower;
  int? lockedManpower;
  int? totalManpower;
  final Map<String, int> buildings = {};

  StateWorldState build() => StateWorldState(
    id: id,
    owner: owner,
    availableManpower: availableManpower,
    lockedManpower: lockedManpower,
    totalManpower: totalManpower,
    buildings: Map.unmodifiable(buildings),
  );
}
