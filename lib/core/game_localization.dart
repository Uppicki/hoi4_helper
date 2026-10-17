import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

enum GameLanguage {
  russian('russian', 'Русский'),
  english('english', 'English');

  const GameLanguage(this.folder, this.label);
  final String folder;
  final String label;
}

/// Resolves save keys through the installed game's localisation files.
/// Game data stays on disk and is never copied into the application package.
class GameLocalization {
  const GameLocalization(this.language, this.entries, {this.gameRoot});

  final GameLanguage language;
  final Map<String, String> entries;
  final String? gameRoot;

  String name(String? code) {
    if (code == null || code.isEmpty) return '—';
    return _resolve(code, <String>{}) ?? code;
  }

  static final _reference = RegExp(r'\$([A-Za-z0-9_.-]+)(?:\|[^$]*)?\$');

  String? _resolve(String code, Set<String> visiting) {
    final value = entries[code] ?? _fallback[language]?[code];
    if (value == null || visiting.contains(code) || visiting.length >= 32) {
      return null;
    }
    visiting.add(code);
    final resolved = value.replaceAllMapped(
      _reference,
      (match) => _resolve(match[1]!, visiting) ?? match[0]!,
    );
    visiting.remove(code);
    return resolved;
  }

  String country(String? tag, {String? ideology}) {
    if (tag == null) return '—';
    if (ideology != null) {
      final form = '${tag}_$ideology';
      if (entries.containsKey(form)) return name(form);
    }
    return name(tag);
  }

  String state(int id) {
    final code = 'STATE_$id';
    final translated = name(code);
    return translated == code ? code : '$translated · #$id';
  }

  static const _fallback = <GameLanguage, Map<String, String>>{
    GameLanguage.russian: {
      'fascism': 'Фашизм',
      'democratic': 'Демократия',
      'communism': 'Коммунизм',
      'neutrality': 'Нейтралитет',
      'normal': 'Обычная',
      'easy': 'Лёгкая',
      'hard': 'Сложная',
      'very_easy': 'Очень лёгкая',
      'very_hard': 'Очень сложная',
      'industrial_complex': 'Фабрика',
      'arms_factory': 'Военный завод',
      'dockyard': 'Верфь',
      'infrastructure': 'Инфраструктура',
      'air_base': 'Авиабаза',
      'fuel_silo': 'Топливное хранилище',
    },
    GameLanguage.english: {
      'normal': 'Normal',
      'easy': 'Easy',
      'hard': 'Hard',
      'very_easy': 'Very easy',
      'very_hard': 'Very hard',
      'industrial_complex': 'Civilian factory',
      'arms_factory': 'Military factory',
      'dockyard': 'Dockyard',
      'infrastructure': 'Infrastructure',
      'air_base': 'Air base',
      'fuel_silo': 'Fuel silo',
    },
  };
}

class GameLocalizationRepository {
  GameLocalizationRepository({this.gameRoot});

  static final shared = GameLocalizationRepository();

  /// Optional override, useful when the game is installed in a custom folder.
  final String? gameRoot;
  final Map<GameLanguage, Future<GameLocalization>> _cache = {};

  Future<GameLocalization> load(GameLanguage language) =>
      _cache.putIfAbsent(language, () async {
        final root = gameRoot ?? await findGameRoot();
        if (root == null) return GameLocalization(language, const {});
        try {
          final entries = await _loadInIsolate(root, language.folder);
          return GameLocalization(
            language,
            Map.unmodifiable(entries),
            gameRoot: root,
          );
        } on FileSystemException {
          return GameLocalization(language, const {});
        }
      });

  static Future<Map<String, String>> _loadInIsolate(
    String root,
    String language,
  ) => Isolate.run(() => _readLanguage(root, language));

  static Future<String?> findGameRoot() async {
    final environment = Platform.environment;
    final candidates = <String>[
      if (environment['HOI4_GAME_PATH'] case final path?) path,
      if (environment['ProgramFiles(x86)'] case final path?)
        '$path\\Steam\\steamapps\\common\\Hearts of Iron IV',
      if (environment['ProgramFiles'] case final path?)
        '$path\\Steam\\steamapps\\common\\Hearts of Iron IV',
    ];
    final drive = RegExp(
      r'^([A-Za-z]:)[\\/]',
    ).firstMatch(Directory.current.absolute.path)?.group(1);
    if (drive != null) candidates.add('$drive\\games\\Hearts of Iron IV');
    for (final path in candidates) {
      final separator = Platform.pathSeparator;
      if (await Directory(
        '$path${separator}localisation${separator}russian',
      ).exists()) {
        return path;
      }
    }
    return null;
  }

  static final _entry = RegExp(
    r'^\s*([A-Za-z0-9_.-]+):(?:\d+)?\s+"((?:\\.|[^"\\])*)"',
  );

  static Future<Map<String, String>> _readLanguage(
    String root,
    String language,
  ) async {
    final separator = Platform.pathSeparator;
    final folder = Directory(
      '$root${separator}localisation$separator$language',
    );
    if (!await folder.exists()) return {};
    final files = <File>[];
    await for (final entity in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.toLowerCase().endsWith('.yml')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final values = <String, String>{};
    for (final file in files) {
      final source = utf8.decode(
        await file.readAsBytes(),
        allowMalformed: true,
      );
      for (final line in const LineSplitter().convert(source)) {
        final match = _entry.firstMatch(line);
        if (match == null) continue;
        final key = match.group(1)!;
        final value = match
            .group(2)!
            .replaceAll(r'\"', '"')
            .replaceAll(r'\n', ' ')
            .replaceAll(r'\\', r'\')
            .replaceAll(RegExp(r'§.'), '')
            .trim();
        if (value.isNotEmpty) values[key] = value;
      }
    }
    return values;
  }
}
