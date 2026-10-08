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
    expect(sample?.observationSchemaVersion, 1);
    expect(sample?.status('manpower'), TelemetryValueStatus.value);
    expect(sample?.value('manpower'), 5562);
    expect(sample?.count('manpower'), 5562);
    expect(sample?.status('stability'), TelemetryValueStatus.unsupported);
    expect(sample?.status('no_such_field'), TelemetryValueStatus.unsupported);
    expect(sample?.receivedAt, isNull);
    expect(sample?.logSource, isNull);
    expect(sample?.campaignId, isNull);
    expect(sample?.saveId, isNull);
    expect(parseTelemetryLine('not a telemetry line'), isNull);
    expect(
      parseTelemetryLine(first.replaceFirst('manpower=5562', 'manpower=-1')),
      isNull,
    );
  });

  test('follows complete lines and clears on log truncation', () async {
    final folder = await Directory.systemTemp.createTemp(
      'hoi4-telemetry-test-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}${Platform.pathSeparator}game.log');
    await file.writeAsString(first);
    final reader = TelemetryLogReader(file);

    final beforeReceipt = DateTime.now();
    final historical = await reader.poll();
    final afterReceipt = DateTime.now();
    expect(historical.latest?.gameDate, '1936.01.02.02');
    expect(historical.receivedNewLine, isFalse);
    expect(historical.latest?.logSource, file.absolute.path);
    final receivedAt = historical.latest?.receivedAt;
    expect(receivedAt, isNotNull);
    expect(receivedAt!.isBefore(beforeReceipt), isFalse);
    expect(receivedAt.isAfter(afterReceipt), isFalse);
    expect((await reader.poll()).latest?.receivedAt, receivedAt);

    await file.writeAsString(
      second.substring(0, second.length - 1),
      mode: FileMode.append,
    );
    expect((await reader.poll()).latest?.gameDate, '1936.01.02.02');
    await file.writeAsString('\n', mode: FileMode.append);
    final fresh = await reader.poll();
    expect(fresh.latest?.gameDate, '1936.01.03.02');
    expect(fresh.receivedNewLine, isTrue);
    expect(fresh.latest?.logSource, file.absolute.path);
    expect(fresh.latest?.receivedAt, isNot(receivedAt));

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
          'eq_infantry_equipment_stock=50|war_support=unknown|'
          'available_civ=0|manpower=6000|unknown_wire_metric=9',
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
    expect(result.latest?.observationSchemaVersion, 1);
    expect(result.latest?.logSource, file.absolute.path);
    expect(result.latest?.receivedAt, isNotNull);
    expect(result.latest?.campaignId, isNull);
    expect(result.latest?.saveId, isNull);
    expect(result.latest?.gameDate, '1936.01.03.02');
    expect(result.latest?.manpower, 5590);
    expect(result.latest?.value('political_power'), 21.5);
    expect(result.latest?.value('stability'), 0.42);
    expect(result.latest?.value('res_steel_balance'), -3);
    expect(result.latest?.count('civilian_factories'), 1234);
    expect(result.latest?.value('army_xp'), 1.5);
    expect(result.latest?.value('war_support'), isNull);
    expect(result.latest?.status('war_support'), TelemetryValueStatus.invalid);
    expect(result.latest?.value('available_civ'), 0);
    expect(result.latest?.status('available_civ'), TelemetryValueStatus.value);
    expect(result.latest?.value('manpower'), 6000);
    expect(result.latest?.status('manpower'), TelemetryValueStatus.value);
    expect(result.latest?.status('fuel'), TelemetryValueStatus.missing);
    expect(
      result.latest?.status('unknown_wire_metric'),
      TelemetryValueStatus.unsupported,
    );
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

  test(
    'complete frames do not carry old values; bad header is rejected',
    () async {
      final folder = await Directory.systemTemp.createTemp('hoi4-v2-status-');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}${Platform.pathSeparator}game.log');
      await file.writeAsString('');
      final reader = TelemetryLogReader(file);
      await reader.poll();

      String frame(String date, String manpower, String data) =>
          v2(date, 'phase=begin|tag=ALB|parts=1|manpower=$manpower') +
          v2(date, 'phase=data|tag=ALB|part=0|$data') +
          v2(date, 'phase=end|tag=ALB|parts=1');

      await file.writeAsString(
        frame('1936.01.03.02', '5590', 'war_support=0.5|political_power=10'),
        mode: FileMode.append,
      );
      final firstFrame = (await reader.poll()).latest!;
      expect(firstFrame.status('war_support'), TelemetryValueStatus.value);
      expect(firstFrame.value('political_power'), 10);

      await file.writeAsString(
        frame(
          '1936.01.04.02',
          '5600',
          'war_support=1.5|political_power=0|civilian_factories=1,2',
        ),
        mode: FileMode.append,
      );
      final secondFrame = (await reader.poll()).latest!;
      expect(secondFrame.gameDate, '1936.01.04.02');
      expect(secondFrame.status('war_support'), TelemetryValueStatus.invalid);
      expect(secondFrame.value('war_support'), isNull);
      expect(secondFrame.status('political_power'), TelemetryValueStatus.value);
      expect(secondFrame.value('political_power'), 0);
      expect(
        secondFrame.status('civilian_factories'),
        TelemetryValueStatus.invalid,
      );
      expect(secondFrame.count('civilian_factories'), isNull);

      await file.writeAsString(
        frame('1936.01.05.02', '5700', 'political_power=5'),
        mode: FileMode.append,
      );
      final thirdFrame = (await reader.poll()).latest!;
      expect(thirdFrame.status('war_support'), TelemetryValueStatus.missing);
      expect(thirdFrame.value('war_support'), isNull);
      expect(thirdFrame.value('political_power'), 5);

      await file.writeAsString(
        frame('1936.01.06.02', '-1', 'political_power=9'),
        mode: FileMode.append,
      );
      final rejected = await reader.poll();
      expect(rejected.latest, same(thirdFrame));
      expect(rejected.receivedNewLine, isFalse);
    },
  );
}
