import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'game_localization.dart';

/// Focus definitions read from the installed game's common/national_focus files.
/// These are game data, not proof that a particular focus is available in a save.
class FocusTreeDefinition {
  const FocusTreeDefinition(
    this.id,
    this.focuses,
    this.sourceFile, {
    this.activeDlcCount,
    this.dlcSourceFile,
  });

  final String id;
  final List<FocusDefinition> focuses;
  final String sourceFile;
  final int? activeDlcCount;
  final String? dlcSourceFile;

  List<FocusDefinition> get displayedFocuses => focuses
      .where((focus) => focus.visibility != FocusVisibility.hidden)
      .toList(growable: false);
}

enum FocusVisibility { visible, hidden, unknown }

class FocusDefinition {
  const FocusDefinition({
    required this.id,
    required this.x,
    required this.y,
    required this.prerequisites,
    this.relativeTo,
    this.prerequisiteGroups = const [],
    this.visibility = FocusVisibility.visible,
  });

  final String id;
  final double x;
  final double y;
  final String? relativeTo;
  final List<String> prerequisites;

  /// Repeated blocks are AND; focus IDs inside one block are alternatives (OR).
  final List<List<String>> prerequisiteGroups;
  final FocusVisibility visibility;

  FocusDefinition withVisibility(FocusVisibility value) => FocusDefinition(
    id: id,
    x: x,
    y: y,
    relativeTo: relativeTo,
    prerequisites: prerequisites,
    prerequisiteGroups: prerequisiteGroups,
    visibility: value,
  );
}

class FocusTreeRepository {
  const FocusTreeRepository({
    this.gameRoot,
    this.runtimeLogSource,
    this.activeDlcs,
  });

  final String? gameRoot;

  /// Only supplied for telemetry, never inferred from an unrelated save.
  final String? runtimeLogSource;
  final Set<String>? activeDlcs;

  Future<List<FocusTreeDefinition>> load({
    String? treeId,
    String? countryTag,
  }) async {
    final root = gameRoot ?? await GameLocalizationRepository.findGameRoot();
    if (root == null) return const [];
    final logSource = runtimeLogSource;
    final dlcs = activeDlcs;
    return Isolate.run(
      () => _readTrees(root, treeId, countryTag, logSource, dlcs),
    );
  }

  static List<FocusTreeDefinition> _readTrees(
    String root,
    String? treeId,
    String? countryTag,
    String? logSource,
    Set<String>? activeDlcs,
  ) {
    final dlcEvidence = activeDlcs == null
        ? _readActiveDlcs(logSource)
        : _DlcEvidence(activeDlcs, null);
    final integratedDlcs = _readIntegratedDlcs(root);
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
          final conditions = <String, List<_Entry>>{};
          for (final focusEntry in tree.where((e) => e.key == 'focus')) {
            final fields = focusEntry.children;
            if (fields == null) continue;
            final focusId = _scalar(fields, 'id');
            if (focusId == null) continue;
            final x = double.tryParse(_scalar(fields, 'x') ?? '');
            final y = double.tryParse(_scalar(fields, 'y') ?? '');
            if (x == null || y == null) continue;
            final prerequisites = <String>[];
            final prerequisiteGroups = <List<String>>[];
            for (final condition in fields.where(
              (e) => e.key == 'prerequisite',
            )) {
              final group =
                  condition.children
                      ?.where((e) => e.key == 'focus')
                      .map((e) => e.value)
                      .whereType<String>()
                      .toList() ??
                  const <String>[];
              prerequisites.addAll(group);
              if (group.isNotEmpty) {
                prerequisiteGroups.add(List.unmodifiable(group));
              }
            }
            conditions[focusId] = [
              for (final branch in fields.where((e) => e.key == 'allow_branch'))
                ...branch.children ?? const [_Entry('__unsupported')],
            ];
            focuses.add(
              FocusDefinition(
                id: focusId,
                x: x,
                y: y,
                relativeTo: _scalar(fields, 'relative_position_id'),
                prerequisites: List.unmodifiable(prerequisites),
                prerequisiteGroups: List.unmodifiable(prerequisiteGroups),
              ),
            );
          }
          found.add(
            FocusTreeDefinition(
              id,
              _applyVisibility(
                focuses,
                conditions,
                dlcEvidence.names,
                integratedDlcs,
                countryTag,
              ),
              file.path,
              activeDlcCount: dlcEvidence.names?.length,
              dlcSourceFile: dlcEvidence.sourceFile,
            ),
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

  static _DlcEvidence _readActiveDlcs(String? logSource) {
    if (logSource == null) return const _DlcEvidence(null, null);
    final file = File(
      '${File(logSource).parent.path}${Platform.pathSeparator}system.log',
    );
    try {
      int? expected;
      final names = <String>{};
      for (final line in file.readAsLinesSync()) {
        final count = RegExp(r'Active DLC Count:\s*(\d+)\s*$').firstMatch(line);
        if (count != null) {
          expected = int.parse(count[1]!);
          names.clear();
        }
        final name = RegExp(r'Active DLC:\s*(.+)$').firstMatch(line);
        if (expected != null && name != null) names.add(name[1]!.trim());
      }
      if (expected == null || names.length != expected) {
        return const _DlcEvidence(null, null);
      }
      return _DlcEvidence(Set.unmodifiable(names), file.path);
    } on FileSystemException {
      return const _DlcEvidence(null, null);
    } on FormatException {
      return const _DlcEvidence(null, null);
    }
  }

  static Set<String> _readIntegratedDlcs(String root) {
    final names = <String>{};
    final folder = Directory('$root${Platform.pathSeparator}integrated_dlc');
    if (!folder.existsSync()) return names;
    for (final file
        in folder
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()) {
      if (!file.path.endsWith('.dlc')) continue;
      try {
        final name = _scalar(_Parser(file.readAsStringSync()).parse(), 'name');
        if (name != null) names.add(name);
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return names;
  }

  static List<FocusDefinition> _applyVisibility(
    List<FocusDefinition> focuses,
    Map<String, List<_Entry>> conditions,
    Set<String>? dlcs,
    Set<String> integratedDlcs,
    String? countryTag,
  ) {
    final byId = {for (final focus in focuses) focus.id: focus};
    final resolved = <String, FocusVisibility>{};
    final evaluator = _BranchConditions(dlcs, integratedDlcs, countryTag);
    FocusVisibility resolve(String id, Set<String> visiting) {
      if (resolved[id] case final cached?) return cached;
      final focus = byId[id];
      if (focus == null || !visiting.add(id)) return FocusVisibility.unknown;
      final own = evaluator.all(conditions[id] ?? const []);
      final dependencies = [
        for (final group in focus.prerequisiteGroups)
          _BranchConditions.any([
            for (final parent in group) resolve(parent, visiting),
          ]),
      ];
      visiting.remove(id);
      return resolved[id] = _BranchConditions.every([own, ...dependencies]);
    }

    return List.unmodifiable([
      for (final focus in focuses)
        focus.withVisibility(resolve(focus.id, <String>{})),
    ]);
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

class _DlcEvidence {
  const _DlcEvidence(this.names, this.sourceFile);
  final Set<String>? names;
  final String? sourceFile;
}

/// Evaluates only supported visibility conditions. Dynamic campaign triggers
/// remain unknown. `available` and completion rewards do not control visibility.
class _BranchConditions {
  const _BranchConditions(this.dlcs, this.integratedDlcs, this.countryTag);
  final Set<String>? dlcs;
  final Set<String> integratedDlcs;
  final String? countryTag;

  static FocusVisibility every(Iterable<FocusVisibility> values) {
    var unknown = false;
    for (final value in values) {
      if (value == FocusVisibility.hidden) return FocusVisibility.hidden;
      unknown |= value == FocusVisibility.unknown;
    }
    return unknown ? FocusVisibility.unknown : FocusVisibility.visible;
  }

  static FocusVisibility any(Iterable<FocusVisibility> values) {
    var unknown = false;
    for (final value in values) {
      if (value == FocusVisibility.visible) return FocusVisibility.visible;
      unknown |= value == FocusVisibility.unknown;
    }
    return unknown ? FocusVisibility.unknown : FocusVisibility.hidden;
  }

  FocusVisibility all(List<_Entry> entries) => every(entries.map(evaluate));

  FocusVisibility evaluate(_Entry entry) {
    FocusVisibility truth(bool value) =>
        value ? FocusVisibility.visible : FocusVisibility.hidden;
    final children = entry.children ?? const <_Entry>[];
    switch (entry.key) {
      case 'always':
        return entry.value == 'yes'
            ? FocusVisibility.visible
            : entry.value == 'no'
            ? FocusVisibility.hidden
            : FocusVisibility.unknown;
      case 'has_dlc':
        if (dlcs == null || entry.value == null) return FocusVisibility.unknown;
        if (dlcs!.contains(entry.value)) return FocusVisibility.visible;
        // Integrated content can be absent from the runtime DLC list. Absence
        // there is not proof that its features are disabled.
        return integratedDlcs.contains(entry.value)
            ? FocusVisibility.unknown
            : FocusVisibility.hidden;
      case 'tag':
        return countryTag == null || entry.value == null
            ? FocusVisibility.unknown
            : truth(countryTag == entry.value);
      case 'AND':
        return all(children);
      case 'OR':
        return any(children.map(evaluate));
      case 'NOT':
        if (children.length != 1) return FocusVisibility.unknown;
        return switch (evaluate(children.single)) {
          FocusVisibility.visible => FocusVisibility.hidden,
          FocusVisibility.hidden => FocusVisibility.visible,
          FocusVisibility.unknown => FocusVisibility.unknown,
        };
      case 'if':
        final limits = children.where((e) => e.key == 'limit').toList();
        if (limits.length != 1) return FocusVisibility.unknown;
        final condition = all(limits.single.children ?? const []);
        final body = all(children.where((e) => e.key != 'limit').toList());
        if (condition == FocusVisibility.hidden) return FocusVisibility.visible;
        if (condition == FocusVisibility.visible) return body;
        return body == FocusVisibility.visible ? body : FocusVisibility.unknown;
      default:
        return FocusVisibility.unknown;
    }
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
