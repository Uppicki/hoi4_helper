import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/focus_tree.dart';
import '../core/game_localization.dart';

/// Displays definitions from the installed game without treating them as a
/// verified observation of the current campaign.
class FocusTreeScreen extends StatefulWidget {
  const FocusTreeScreen({
    super.key,
    required this.names,
    required this.countryTag,
    this.treeId,
    this.currentFocus,
    this.completedFocuses = const [],
    this.repository,
  });

  final GameLocalization names;
  final String? countryTag;
  final String? treeId;
  final String? currentFocus;
  final List<String> completedFocuses;
  final FocusTreeRepository? repository;

  @override
  State<FocusTreeScreen> createState() => _FocusTreeScreenState();
}

class _FocusTreeScreenState extends State<FocusTreeScreen> {
  late final Future<List<FocusTreeDefinition>> _trees;
  int _selected = 0;

  bool get _ru => widget.names.language == GameLanguage.russian;
  String _ui(String ru, String en) => _ru ? ru : en;

  @override
  void initState() {
    super.initState();
    _trees = (widget.repository ?? const FocusTreeRepository()).load(
      treeId: widget.treeId,
      countryTag: widget.countryTag,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_ui('Дерево фокусов', 'Focus tree'))),
    body: FutureBuilder<List<FocusTreeDefinition>>(
      future: _trees,
      builder: (context, result) {
        final trees = result.data;
        if (result.hasError) {
          return _message(
            _ui(
              'Не удалось прочитать файлы фокусов установленной игры.',
              'Could not read focus files from the installed game.',
            ),
          );
        }
        if (trees == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (trees.isEmpty) {
          return _message(
            widget.treeId != null
                ? _ui(
                    'Дерево «${widget.treeId}» не найдено в установленной игре. Проверьте версию игры и активные моды.',
                    'Tree “${widget.treeId}” was not found in the installed game. Check the game version and active mods.',
                  )
                : _ui(
                    'Для страны не найдено дерево в файлах установленной игры. Источник не сообщает выбранное дерево.',
                    'No tree was found for this country in installed game files. The source does not identify the selected tree.',
                  ),
          );
        }
        final tree = trees[_selected.clamp(0, trees.length - 1)];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (trees.length > 1)
                    DropdownButton<int>(
                      key: const Key('focus-tree-select'),
                      value: _selected,
                      items: [
                        for (var i = 0; i < trees.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(widget.names.name(trees[i].id)),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _selected = value ?? 0),
                    )
                  else
                    Text(
                      widget.names.name(tree.id),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  const SizedBox(height: 5),
                  Text(
                    widget.treeId == null
                        ? _ui(
                            'Возможное дерево по тегу страны из файлов игры. Источник не подтверждает активное дерево и прогресс.',
                            'Possible tree by country tag from game files. The source does not confirm the active tree or progress.',
                          )
                        : _ui(
                            'Дерево из установленной игры по ID сохранения. Разблокировка, DLC и моды не проверены; общие и динамические ветки могут отсутствовать.',
                            'Installed game tree matched by save ID. Unlocks, DLC and mods are not verified; shared and dynamic branches may be missing.',
                          ),
                    style: const TextStyle(
                      color: Color(0xFFAAB7AD),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _ui(
                      'Перетаскивайте дерево; масштабируйте колесом мыши или жестом.',
                      'Drag to pan; use the mouse wheel or pinch to zoom.',
                    ),
                    style: const TextStyle(
                      color: Color(0xFFAAB7AD),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: tree.focuses.isEmpty
                  ? _message(
                      _ui(
                        'В этом файле нет фокусов с координатами.',
                        'This file has no focuses with coordinates.',
                      ),
                    )
                  : _FocusGraph(
                      key: ValueKey(tree.id),
                      tree: tree,
                      names: widget.names,
                      currentFocus: widget.currentFocus,
                      completedFocuses: widget.completedFocuses.toSet(),
                    ),
            ),
          ],
        );
      },
    ),
  );

  Widget _message(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class _FocusGraph extends StatefulWidget {
  const _FocusGraph({
    super.key,
    required this.tree,
    required this.names,
    required this.currentFocus,
    required this.completedFocuses,
  });

  final FocusTreeDefinition tree;
  final GameLocalization names;
  final String? currentFocus;
  final Set<String> completedFocuses;

  @override
  State<_FocusGraph> createState() => _FocusGraphState();
}

class _FocusGraphState extends State<_FocusGraph> {
  final _transform = TransformationController();
  bool _positioned = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  static const _nodeWidth = 152.0;
  static const _nodeHeight = 76.0;
  static const _column = 174.0;
  static const _row = 112.0;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final focus in widget.tree.focuses) focus.id: focus};
    final locations = <String, Offset>{};
    Offset position(String id, Set<String> visiting) {
      if (locations[id] case final cached?) return cached;
      final focus = byId[id];
      if (focus == null || visiting.contains(id)) return Offset.zero;
      visiting.add(id);
      final base = focus.relativeTo == null
          ? Offset.zero
          : position(focus.relativeTo!, visiting);
      visiting.remove(id);
      return locations[id] = base + Offset(focus.x, focus.y);
    }

    for (final focus in widget.tree.focuses) {
      position(focus.id, <String>{});
    }
    final minX = locations.values.map((p) => p.dx).reduce(math.min);
    final minY = locations.values.map((p) => p.dy).reduce(math.min);
    final maxX = locations.values.map((p) => p.dx).reduce(math.max);
    final maxY = locations.values.map((p) => p.dy).reduce(math.max);
    final points = {
      for (final entry in locations.entries)
        entry.key: Offset(
          24 + (entry.value.dx - minX) * _column,
          24 + (entry.value.dy - minY) * _row,
        ),
    };
    final width = math.max(360.0, 48 + (maxX - minX) * _column + _nodeWidth);
    final height = math.max(300.0, 48 + (maxY - minY) * _row + _nodeHeight);

    return LayoutBuilder(
      builder: (context, bounds) {
        final current = points[widget.currentFocus];
        if (!_positioned && current != null) {
          _positioned = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            const scale = 0.8;
            _transform.value = Matrix4.identity()
              ..translate(
                bounds.maxWidth / 2 - (current.dx + _nodeWidth / 2) * scale,
                bounds.maxHeight / 2 - (current.dy + _nodeHeight / 2) * scale,
              )
              ..scale(scale);
          });
        }
        return ClipRect(
          child: InteractiveViewer(
            key: const Key('focus-tree-canvas'),
            transformationController: _transform,
            constrained: false,
            minScale: 0.15,
            maxScale: 2.5,
            boundaryMargin: const EdgeInsets.all(120),
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FocusEdges(widget.tree.focuses, points),
                    ),
                  ),
                  for (final focus in widget.tree.focuses)
                    Positioned(
                      left: points[focus.id]!.dx,
                      top: points[focus.id]!.dy,
                      width: _nodeWidth,
                      height: _nodeHeight,
                      child: Tooltip(
                        message: focus.id,
                        child: Container(
                          key: ValueKey('focus-${focus.id}'),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: focus.id == widget.currentFocus
                                ? const Color(0xFF4A4228)
                                : widget.completedFocuses.contains(focus.id)
                                ? const Color(0xFF294738)
                                : const Color(0xFF1C2922),
                            border: Border.all(
                              color: focus.id == widget.currentFocus
                                  ? const Color(0xFFD7B979)
                                  : widget.completedFocuses.contains(focus.id)
                                  ? const Color(0xFF80B99A)
                                  : const Color(0xFF526357),
                              width: focus.id == widget.currentFocus ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            widget.names.name(focus.id),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FocusEdges extends CustomPainter {
  const _FocusEdges(this.focuses, this.points);
  final List<FocusDefinition> focuses;
  final Map<String, Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF657669)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final focus in focuses) {
      final end = points[focus.id];
      if (end == null) continue;
      for (final dependency in focus.prerequisites) {
        final start = points[dependency];
        if (start == null) continue;
        final from = start + const Offset(76, 76);
        final to = end + const Offset(76, 0);
        final middle = (from.dy + to.dy) / 2;
        canvas.drawPath(
          Path()
            ..moveTo(from.dx, from.dy)
            ..lineTo(from.dx, middle)
            ..lineTo(to.dx, middle)
            ..lineTo(to.dx, to.dy),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FocusEdges oldDelegate) =>
      oldDelegate.focuses != focuses || oldDelegate.points != points;
}
