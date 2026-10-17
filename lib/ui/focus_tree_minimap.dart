import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/focus_tree.dart';

/// Fixed overview of the same displayed nodes as the main focus canvas.
class FocusTreeMiniMap extends StatelessWidget {
  const FocusTreeMiniMap({
    super.key,
    required this.focuses,
    required this.points,
    required this.sceneSize,
    required this.viewportSize,
    required this.transform,
    required this.onNavigate,
    required this.russian,
    required this.currentFocus,
    required this.completedFocuses,
  });

  final List<FocusDefinition> focuses;
  final Map<String, Offset> points;
  final Size sceneSize;
  final Size viewportSize;
  final TransformationController transform;
  final ValueChanged<Offset> onNavigate;
  final bool russian;
  final String? currentFocus;
  final Set<String> completedFocuses;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('focus-tree-navigation'),
    color: const Color(0xFF152019),
    elevation: 8,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: Color(0xFF526357)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 3),
          child: Row(
            children: [
              const Icon(
                Icons.map_outlined,
                size: 14,
                color: Color(0xFFD7B979),
              ),
              const SizedBox(width: 6),
              Text(
                russian ? 'Обзор дерева' : 'Tree overview',
                style: const TextStyle(fontSize: 11, color: Color(0xFFCDD6CE)),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) {
              final projection = _Projection(bounds.biggest, sceneSize);
              void navigate(Offset local) =>
                  onNavigate(projection.toScene(local));
              return Semantics(
                label: russian
                    ? 'Навигация по дереву фокусов'
                    : 'Focus tree navigation',
                hint: russian
                    ? 'Нажмите или перетащите, чтобы перейти к нужной области'
                    : 'Click or drag to move to an area',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: const Key('focus-tree-minimap'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => navigate(details.localPosition),
                    onPanStart: (details) => navigate(details.localPosition),
                    onPanUpdate: (details) => navigate(details.localPosition),
                    child: CustomPaint(
                      painter: _MiniMapPainter(
                        focuses: focuses,
                        points: points,
                        projection: projection,
                        viewportSize: viewportSize,
                        transform: transform,
                        currentFocus: currentFocus,
                        completedFocuses: completedFocuses,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _Projection {
  _Projection(Size size, this.sceneSize)
    : scale = math.min(
        (size.width - 16) / sceneSize.width,
        (size.height - 16) / sceneSize.height,
      ) {
    origin = Offset(
      (size.width - sceneSize.width * scale) / 2,
      (size.height - sceneSize.height * scale) / 2,
    );
  }

  final Size sceneSize;
  final double scale;
  late final Offset origin;

  Offset toScene(Offset local) => Offset(
    ((local.dx - origin.dx) / scale).clamp(0.0, sceneSize.width).toDouble(),
    ((local.dy - origin.dy) / scale).clamp(0.0, sceneSize.height).toDouble(),
  );

  Rect toMap(Rect scene) => Rect.fromLTWH(
    origin.dx + scene.left * scale,
    origin.dy + scene.top * scale,
    scene.width * scale,
    scene.height * scale,
  );
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter({
    required this.focuses,
    required this.points,
    required this.projection,
    required this.viewportSize,
    required this.transform,
    required this.currentFocus,
    required this.completedFocuses,
  }) : super(repaint: transform);

  final List<FocusDefinition> focuses;
  final Map<String, Offset> points;
  final _Projection projection;
  final Size viewportSize;
  final TransformationController transform;
  final String? currentFocus;
  final Set<String> completedFocuses;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final lines = Paint()
      ..color = const Color(0xFF526357)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    final node = Paint();
    for (final focus in focuses) {
      final point = points[focus.id]!;
      for (final parent in focus.prerequisites) {
        final start = points[parent];
        if (start == null) continue;
        final from = start + const Offset(76, 76);
        final to = point + const Offset(76, 0);
        final middle = (from.dy + to.dy) / 2;
        Offset map(Offset scene) =>
            projection.origin + scene * projection.scale;
        final a = map(from);
        final b = map(Offset(from.dx, middle));
        final c = map(Offset(to.dx, middle));
        final d = map(to);
        canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy)
            ..lineTo(c.dx, c.dy)
            ..lineTo(d.dx, d.dy),
          lines,
        );
      }
      node.color = focus.id == currentFocus
          ? const Color(0xFFD7B979)
          : completedFocuses.contains(focus.id)
          ? const Color(0xFF80B99A)
          : const Color(0xFF7B9481);
      canvas.drawRect(projection.toMap(point & const Size(152, 76)), node);
    }

    final visible = Rect.fromPoints(
      transform.toScene(Offset.zero),
      transform.toScene(Offset(viewportSize.width, viewportSize.height)),
    ).intersect(Offset.zero & projection.sceneSize);
    if (!visible.isEmpty) {
      final frame = projection.toMap(visible);
      canvas.drawRect(frame, Paint()..color = const Color(0x22E2C785));
      canvas.drawRect(
        frame,
        Paint()
          ..color = const Color(0xFFE2C785)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.projection != projection ||
      oldDelegate.viewportSize != viewportSize ||
      oldDelegate.currentFocus != currentFocus ||
      oldDelegate.completedFocuses != completedFocuses ||
      oldDelegate.transform != transform;
}
