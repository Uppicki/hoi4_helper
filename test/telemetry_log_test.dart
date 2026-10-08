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

  test('parses the engine date, player tag and manpower', () {
    final sample = parseTelemetryLine(first.trimRight());
    expect(sample?.gameDate, '1936.01.02.02');
    expect(sample?.playerTag, 'ALB');
    expect(sample?.manpower, 5562);
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
}
