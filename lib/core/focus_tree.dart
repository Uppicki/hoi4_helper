import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'game_localization.dart';

/// Focus definitions read from the installed game's common/national_focus files.
/// These are game data, not proof that a particular focus is available in a save.
class FocusTreeDefinition {
  const FocusTreeDefinition(this.id, this.focuses, this.sourceFile);

  final String id;
  final List<FocusDefinition> focuses;
  final String sourceFile;
}

class FocusDefinition {
  const FocusDefinition({
    required this.id,
    required this.x,
    required this.y,
    required this.prerequisites,
    this.relativeTo,
  });

  final String id;
  final double x;
  final double y;
  final String? relativeTo;
  final List<String> prerequisites;
}

class FocusTreeRepository {
  const FocusTreeRepository({this.gameRoot});

  final String? gameRoot;

  Future<List<FocusTreeDefinition>> load({
    String? treeId,
    String? countryTag,
  }) async {
    final root = gameRoot ?? await GameLocalizationRepository.findGameRoot();
    if (root == null) return const [];
    return Isolate.run(() => _readTrees(root, treeId, countryTag));
  }

  static List<FocusTreeDefinition> _readTrees(
    String root,
    String? treeId,
    String? countryTag,
  ) {
    final folder = Directory(
      '$root${Platform.pathSeparator}common${Platform.pathSeparator}national_focus',
    );
    if (!folder.existsSync()) return const [];
    final files =
        folder
            .listSync(followLinks: false)
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.txt'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final found = <FocusTreeDefinition>[];
    for (final file in files) {
      try {
        final source = utf8.decode(
          file.readAsBytesSync(),
          allowMalformed: true,
        );
        final document = _Parser(source).parse();
        for (final entry in document.where((e) => e.key == 'focus_tree')) {
          final tree = entry.children;
          if (tree == null) continue;
          final id = _scalar(tree, 'id');
          if (id == null) continue;
          if (treeId != null && treeId.isNotEmpty) {
            if (id != treeId) continue;
          } else if (countryTag == null || !_assignedTo(tree, countryTag)) {
            continue;
          }
          final focuses = <FocusDefinition>[];
          for (final focusEntry in tree.where((e) => e.key == 'focus')) {
            final fields = focusEntry.children;
            if (fields == null) continue;
            final focusId = _scalar(fields, 'id');
            if (focusId == null) continue;
            final x = double.tryParse(_scalar(fields, 'x') ?? '');
            final y = double.tryParse(_scalar(fields, 'y') ?? '');
            if (x == null || y == null) continue;
            final prerequisites = <String>[];
            for (final condition in fields.where(
              (e) => e.key == 'prerequisite',
            )) {
              prerequisites.addAll(
                condition.children
                        ?.where((e) => e.key == 'focus')
                        .map((e) => e.value)
                        .whereType<String>() ??
                    const <String>[],
              );
            }
            focuses.add(
              FocusDefinition(
                id: focusId,
                x: x,
                y: y,
                relativeTo: _scalar(fields, 'relative_position_id'),
                prerequisites: List.unmodifiable(prerequisites),
              ),
            );
          }
          found.add(
            FocusTreeDefinition(id, List.unmodifiable(focuses), file.path),
          );
          if (treeId != null && treeId.isNotEmpty) return found;
        }
      } on FileSystemException {
        // An unreadable definition cannot be shown.
      } on FormatException {
        // Other definition files can still supply the requested tree.
      }
    }
    return found;
  }

  static bool _assignedTo(List<_Entry> tree, String tag) {
    for (final country in tree.where((e) => e.key == 'country')) {
      for (final modifier
          in country.children?.where((e) => e.key == 'modifier') ??
              const <_Entry>[]) {
        if (_scalar(modifier.children ?? const [], 'tag') == tag) return true;
      }
    }
    return false;
  }

  static String? _scalar(List<_Entry> entries, String key) {
    for (final entry in entries) {
      if (entry.key == key && entry.value != null) return entry.value;
    }
    return null;
  }
}

class _Entry {
  const _Entry(this.key, {this.value, this.children});
  final String key;
  final String? value;
  final List<_Entry>? children;
}

/// Minimal Clausewitz tokenizer and nested assignment reader. Repeated keys and
/// order are retained, including repeated prerequisite blocks.
class _Parser {
  _Parser(this.source);
  final String source;
  int offset = 0;
  String? lookahead;

  List<_Entry> parse() => _entries();

  List<_Entry> _entries({bool nested = false}) {
    final entries = <_Entry>[];
    while (true) {
      final key = _take();
      if (key == null) {
        if (nested) throw const FormatException('Unclosed focus block');
        return entries;
      }
      if (key == '}') {
        if (!nested) throw const FormatException('Unexpected closing brace');
        return entries;
      }
      if (_peek() != '=') continue;
      _take();
      final value = _take();
      if (value == null) throw const FormatException('Missing focus value');
      if (value == '{') {
        entries.add(_Entry(key, children: _entries(nested: true)));
      } else {
        entries.add(_Entry(key, value: value));
      }
    }
  }

  String? _peek() => lookahead ??= _next();
  String? _take() {
    final token = _peek();
    lookahead = null;
    return token;
  }

  String? _next() {
    while (offset < source.length) {
      final char = source[offset];
      if (char == '#') {
        while (offset < source.length && source[offset] != '\n') {
          offset++;
        }
      } else if (char.trim().isEmpty) {
        offset++;
      } else {
        break;
      }
    }
    if (offset >= source.length) return null;
    final char = source[offset++];
    if (char == '=' || char == '{' || char == '}') return char;
    if (char == '"') {
      final result = StringBuffer();
      while (offset < source.length) {
        final next = source[offset++];
        if (next == '"') return result.toString();
        if (next == '\\' && offset < source.length) {
          result.write(source[offset++]);
        } else {
          result.write(next);
        }
      }
      throw const FormatException('Unclosed quoted value');
    }
    final start = offset - 1;
    while (offset < source.length) {
      final next = source[offset];
      if (next.trim().isEmpty ||
          next == '#' ||
          next == '=' ||
          next == '{' ||
          next == '}') {
        break;
      }
      offset++;
    }
    return source.substring(start, offset);
  }
}
