import 'binary_save_world_parser.dart';
import 'save_repository.dart';
import 'world_state.dart';

/// Source settings are deliberately open for a future MCP or other adapter.
abstract class WorldStateSourceSettings {
  const WorldStateSourceSettings();
}

class SaveFileSourceSettings extends WorldStateSourceSettings {
  const SaveFileSourceSettings(this.save);
  final SaveFile save;
}

abstract class WorldStateSource {
  Future<WorldStateSnapshot> read();
}

typedef WorldStateSourceBuilder =
    WorldStateSource Function(WorldStateSourceSettings settings);

/// Creates sources without coupling the controller to their transport.
class WorldStateSourceFactory {
  WorldStateSourceFactory({SaveRepository? repository}) {
    final saves = repository ?? SaveRepository();
    register<SaveFileSourceSettings>(
      (settings) => SaveFileWorldStateSource(settings.save, saves),
    );
  }

  final Map<Type, WorldStateSourceBuilder> _builders = {};

  void register<T extends WorldStateSourceSettings>(
    WorldStateSource Function(T settings) builder,
  ) {
    _builders[T] = (settings) => builder(settings as T);
  }

  WorldStateSource create(WorldStateSourceSettings settings) {
    final builder = _builders[settings.runtimeType];
    if (builder == null) {
      throw UnsupportedError(
        'Источник ${settings.runtimeType} пока не поддерживается.',
      );
    }
    return builder(settings);
  }
}

class SaveFileWorldStateSource implements WorldStateSource {
  const SaveFileWorldStateSource(this.save, this.repository);

  final SaveFile save;
  final SaveRepository repository;

  @override
  Future<WorldStateSnapshot> read() async {
    final loaded = await repository.load(save);
    final metadata = BinarySaveHeader.parse(loaded.prefixBytes);
    final world = await BinarySaveWorldParser.readFile(loaded.file);
    return WorldStateSnapshot(
      sourceDescription: 'Файл сохранения',
      readAt: loaded.loadedAt,
      gameDate: metadata.date,
      playerTag: metadata.playerTag,
      ideology: metadata.ideology,
      difficulty: metadata.difficulty,
      gameVersion: metadata.version,
      world: world,
      loadedSave: loaded,
    );
  }
}

class BinarySaveHeader {
  const BinarySaveHeader({
    required this.playerTag,
    required this.ideology,
    required this.difficulty,
    required this.date,
    required this.version,
  });

  final String playerTag;
  final String ideology;
  final String difficulty;
  final GameDate date;
  final String version;

  /// Reads only the verified top-level metadata layout seen in HOI4bin saves.
  /// A different layout fails explicitly; it is never guessed from a filename.
  static BinarySaveHeader parse(List<int> bytes) {
    final reader = _HeaderReader(bytes);
    if (reader.ascii(7) != 'HOI4bin') {
      throw const SaveReadException(
        'Формат сохранения пока не поддерживается: ожидается HOI4bin.',
      );
    }

    final player = reader.fieldString(0x2A35);
    final ideology = reader.fieldString(0x2E3E);
    final dateCode = reader.fieldInt32(0x284A);
    final difficulty = reader.fieldString(0x299F);
    final version = reader.fieldString(0x00EE);

    if (!RegExp(r'^[A-Z0-9]{3}$').hasMatch(player) ||
        !RegExp(r'\bv\d+\.\d+').hasMatch(version)) {
      throw const SaveReadException(
        'Заголовок сохранения не распознан. Версия формата может отличаться.',
      );
    }
    return BinarySaveHeader(
      playerTag: player,
      ideology: ideology,
      difficulty: difficulty,
      date: GameDate.fromHoi4Code(dateCode),
      version: version,
    );
  }
}

class _HeaderReader {
  _HeaderReader(this.bytes);
  final List<int> bytes;
  int offset = 0;

  int _byte() {
    if (offset >= bytes.length) {
      throw const SaveReadException('Заголовок сохранения неполон.');
    }
    return bytes[offset++];
  }

  int _uint16() => _byte() | (_byte() << 8);

  int _int32() {
    final value = _byte() | (_byte() << 8) | (_byte() << 16) | (_byte() << 24);
    return value.toSigned(32);
  }

  String ascii(int length) {
    if (length < 0 || length > bytes.length - offset) {
      throw const SaveReadException('Заголовок сохранения неполон.');
    }
    final value = String.fromCharCodes(bytes.sublist(offset, offset + length));
    offset += length;
    return value;
  }

  void _field(int token, int type) {
    if (_uint16() != token || _uint16() != 1 || _uint16() != type) {
      throw const SaveReadException(
        'Структура бинарного сохранения пока не поддерживается.',
      );
    }
  }

  String fieldString(int token) {
    final actualToken = _uint16();
    final operator = _uint16();
    final type = _uint16();
    if (actualToken != token ||
        operator != 1 ||
        (type != 0x000F && type != 0x0017)) {
      throw const SaveReadException(
        'Структура бинарного сохранения пока не поддерживается.',
      );
    }
    return ascii(_uint16());
  }

  int fieldInt32(int token) {
    _field(token, 0x000C);
    return _int32();
  }
}
