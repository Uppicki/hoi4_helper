import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/telemetry_log.dart';
import 'package:hoi4_helper/ui/app_router.dart';
import 'package:hoi4_helper/ui/saves_screen.dart';
import 'package:hoi4_helper/ui/source_screen.dart';
import 'package:hoi4_helper/ui/telemetry_screen.dart';

void main() {
  testWidgets('telemetry is the default and precedes saves in sources', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: AppRouter(
          telemetryReader: TelemetryLogReader(File('missing-telemetry.log')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TelemetryScreen), findsOneWidget);
    expect(find.text('Телеметрия'), findsOneWidget);
    expect(find.byType(SavesScreen), findsNothing);

    await tester.tap(find.byKey(const Key('change-source-from-telemetry')));
    await tester.pumpAndSettle();
    expect(find.byType(SourceScreen), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('telemetry-source'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('file-source'))).dy),
    );

    await tester.tap(find.byKey(const Key('file-source')));
    await tester.pumpAndSettle();
    expect(find.byType(SavesScreen), findsOneWidget);
    expect(find.text('ИСТОЧНИК 02'), findsOneWidget);

    await tester.tap(find.byKey(const Key('change-source-from-saves')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('telemetry-source')));
    await tester.pumpAndSettle();
    expect(find.byType(TelemetryScreen), findsOneWidget);
    expect(find.byType(SavesScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
