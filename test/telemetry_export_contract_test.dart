import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/telemetry_log.dart';

void main() {
  test('generated mod and reader agree on a complete V3 record', () async {
    final mod = File(
      'telemetry_mod/hoi4_helper_telemetry/common/on_actions/'
      'hoi4_helper_telemetry.txt',
    ).readAsStringSync();
    final templates = RegExp(r'\blog = "([^"]+)"')
        .allMatches(mod)
        .map((match) => match.group(1)!)
        .where((line) => line.startsWith('HOI4_HELPER_V3|'))
        .toList();
    expect(templates.length, greaterThan(10));

    final folder = await Directory.systemTemp.createTemp('hoi4-contract-');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}${Platform.pathSeparator}game.log');
    final lines = templates.map((template) {
      final resolved = template
          .replaceAll('[ROOT.GetTag]', 'ALB')
          .replaceAll('[THIS.GetTag]', 'ITA')
          .replaceAll('[ROOT.GetManpower]', '5590')
          .replaceAll(RegExp(r'\[\?[^\]]+\]'), '1');
      return '[21:28:00][1936.01.03.02][effectbase.cpp:1782]: $resolved\n';
    }).join();
    await file.writeAsString(lines);
    final result = await TelemetryLogReader(file).poll();
    expect(result.receivedNewLine, isFalse);
    expect(result.latest?.schemaVersion, 3);
    expect(result.latest?.rawWorld?.relations.single.otherTag, 'ITA');
    expect(result.latest?.playerTag, 'ALB');
    expect(result.latest?.manpower, 5590);
    expect(result.latest?.values.length, greaterThan(150));
    expect(result.latest?.value('res_steel_balance'), 1);
    expect(result.latest?.value('eq_infantry_equipment_stock'), 1);
  });
}
