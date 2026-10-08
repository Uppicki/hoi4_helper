import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/telemetry_log.dart';

void main() {
  const first =
      '[21:27:21][1936.01.02.02][effectbase.cpp:1782]: '
      'HOI4_HELPER_V1|date= 2:00, 2 Января, 1936|tag=ALB|manpower=5562\n';
  const second =
      '[21:27:22][1936.01.03.02][effectbase.cpp:1782]: '
      'HOI4_HELPER_V1|date= 2:00, 3 Января, 1936|tag=ALB|manpower=5590\n';
  String v2(String date, String body) =>
      '[21:28:00][$date][effectbase.cpp:1782]: HOI4_HELPER_V2|$body\n';

  test('parses the old single line and keeps invalid input unknown', () {
    final sample = parseTelemetryLine(first.trimRight());
    expect(sample?.gameDate, '1936.01.02.02');
    expect(sample?.playerTag, 'ALB');
    expect(sample?.manpower, 5562);
    expect(sample?.schemaVersion, 1);
    expect(parseTelemetryLine('not a telemetry line'), isNull);
  });

  test('follows complete lines and clears on log truncation', () async {
    final folder = await Directory.systemTemp.createTemp(
      'hoi4-telemetry-test-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}${Platform.pathSeparator}game.log');
    await file.writeAsString(first);
    final reader = TelemetryLogReader(file);

    final historical = await reader.poll();
    expect(historical.latest?.gameDate, '1936.01.02.02');
    expect(historical.receivedNewLine, isFalse);

    await file.writeAsString(
      second.substring(0, second.length - 1),
      mode: FileMode.append,
    );
    expect((await reader.poll()).latest?.gameDate, '1936.01.02.02');
    await file.writeAsString('\n', mode: FileMode.append);
    final fresh = await reader.poll();
    expect(fresh.latest?.gameDate, '1936.01.03.02');
    expect(fresh.receivedNewLine, isTrue);

    await file.writeAsString('');
    expect((await reader.poll()).latest, isNull);
  });

  test('publishes a V2 frame only after all parts and end marker', () async {
    final folder = await Directory.systemTemp.createTemp('hoi4-v2-');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}${Platform.pathSeparator}game.log');
    await file.writeAsString('');
    final reader = TelemetryLogReader(file);
    await reader.poll();
    final begin = v2(
      '1936.01.03.02',
      'phase=begin|tag=ALB|parts=2|manpower=5590',
    );
    final data0 = v2(
      '1936.01.03.02',
      'phase=data|tag=ALB|part=0|political_power=21,500|stability=0,42|'
          'res_steel_balance=-3|civilian_factories=1.234',
    );
    final data1 = v2(
      '1936.01.03.02',
      'phase=data|tag=ALB|part=1|army_xp=1.500|'
          'eq_infantry_equipment_stock=50|war_support=unknown',
    );
    final end = v2('1936.01.03.02', 'phase=end|tag=ALB|parts=2');
    await file.writeAsString(begin + data0, mode: FileMode.append);
    expect((await reader.poll()).latest, isNull);
    await file.writeAsString(
      data1 + end.substring(0, end.length - 1),
      mode: FileMode.append,
    );
    expect((await reader.poll()).latest, isNull);
    await file.writeAsString('\n', mode: FileMode.append);
    final result = await reader.poll();
    expect(result.receivedNewLine, isTrue);
    expect(result.latest?.schemaVersion, 2);
    expect(result.latest?.gameDate, '1936.01.03.02');
    expect(result.latest?.manpower, 5590);
    expect(result.latest?.value('political_power'), 21.5);
    expect(result.latest?.value('stability'), 0.42);
    expect(result.latest?.value('res_steel_balance'), -3);
    expect(result.latest?.count('civilian_factories'), 1234);
    expect(result.latest?.value('army_xp'), 1.5);
    expect(result.latest?.value('war_support'), isNull);
    expect(result.latest?.value('no_such_field'), isNull);
  });

  test(
    'rejects mixed dates and incomplete frames without losing last value',
    () async {
      final folder = await Directory.systemTemp.createTemp('hoi4-v2-');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}${Platform.pathSeparator}game.log');
      await file.writeAsString(first);
      final reader = TelemetryLogReader(file);
      await reader.poll();
      await file.writeAsString(
        v2('1936.01.03.02', 'phase=begin|tag=ALB|parts=2|manpower=5590') +
            v2(
              '1936.01.03.02',
              'phase=data|tag=ALB|part=0|political_power=20',
            ) +
            v2('1936.01.04.02', 'phase=data|tag=ALB|part=1|stability=0.5') +
            v2('1936.01.03.02', 'phase=end|tag=ALB|parts=2'),
        mode: FileMode.append,
      );
      final result = await reader.poll();
      expect(result.latest?.schemaVersion, 1);
      expect(result.latest?.manpower, 5562);
      expect(result.receivedNewLine, isFalse);
    },
  );
}
