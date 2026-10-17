import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/focus_tree.dart';
import 'package:hoi4_helper/core/game_localization.dart';
import 'package:hoi4_helper/ui/focus_tree_screen.dart';

class _NavigationRepository extends FocusTreeRepository {
  const _NavigationRepository({this.small = false});
  final bool small;

  @override
  Future<List<FocusTreeDefinition>> load({
    String? treeId,
    String? countryTag,
  }) async => [
    FocusTreeDefinition('test_tree', [
      const FocusDefinition(id: 'left', x: 0, y: 0, prerequisites: []),
      if (!small) ...const [
        FocusDefinition(id: 'middle', x: 15, y: 6, prerequisites: ['left']),
        FocusDefinition(id: 'right', x: 30, y: 12, prerequisites: ['middle']),
      ],
    ], 'fixture.txt'),
  ];
}

Widget _screen({bool small = false}) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: FocusTreeScreen(
    names: const GameLocalization(GameLanguage.russian, {}),
    countryTag: 'TEST',
    repository: _NavigationRepository(small: small),
  ),
);

void main() {
  testWidgets('minimap click and drag navigate without changing zoom', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    final viewer = find.byKey(const Key('focus-tree-canvas'));
    final map = find.byKey(const Key('focus-tree-minimap'));
    final panel = find.byKey(const Key('focus-tree-navigation'));
    final controller = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    Offset sceneCenter() =>
        controller.toScene(tester.getSize(viewer).center(Offset.zero));
    final originalCenter = sceneCenter();
    final mapRect = tester.getRect(map);
    final panelRect = tester.getRect(panel);

    await tester.tapAt(
      mapRect.topLeft + Offset(mapRect.width * 0.78, mapRect.height * 0.6),
    );
    await tester.pump();
    expect(sceneCenter().dx, greaterThan(originalCenter.dx + 1500));
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(tester.getRect(panel), panelRect);

    controller.value = Matrix4.identity()
      ..translate(-1000.0, -200.0)
      ..scale(0.6);
    await tester.pump();
    final zoomedCenter = sceneCenter();
    await tester.tapAt(
      mapRect.topLeft + Offset(mapRect.width * 0.2, mapRect.height * 0.5),
    );
    await tester.pump();
    expect(sceneCenter().dx, lessThan(zoomedCenter.dx - 1000));
    expect(controller.value.getMaxScaleOnAxis(), closeTo(0.6, 0.001));

    final beforeDrag = sceneCenter();
    await tester.dragFrom(mapRect.center, const Offset(70, 0));
    await tester.pumpAndSettle();
    expect(sceneCenter().dx, greaterThan(beforeDrag.dx + 500));
    expect(controller.value.getMaxScaleOnAxis(), closeTo(0.6, 0.001));
    expect(tester.getRect(panel), panelRect);

    tester.view.physicalSize = const Size(480, 800);
    await tester.pumpAndSettle();
    final narrowPanel = tester.getRect(panel);
    expect(narrowPanel.left, greaterThanOrEqualTo(0));
    expect(narrowPanel.right, lessThanOrEqualTo(480));
    expect(narrowPanel.bottom, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimap handles a tree smaller than the viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_screen(small: true));
    await tester.pumpAndSettle();
    final mapRect = tester.getRect(find.byKey(const Key('focus-tree-minimap')));
    await tester.tapAt(mapRect.bottomRight - const Offset(2, 2));
    await tester.pump();
    final controller = tester
        .widget<InteractiveViewer>(find.byKey(const Key('focus-tree-canvas')))
        .transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(tester.takeException(), isNull);
  });
}
