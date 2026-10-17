import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/telemetry_log.dart';

String v2(String date, String body, {String tag = 'ALB'}) =>
    '[21:28:00][$date][effectbase.cpp:1782]: HOI4_HELPER_V2|${body.replaceAll('{tag}', tag)}\n';

String frame(String date, String tag, String metric) =>
    v2(date, 'phase=begin|tag={tag}|parts=1|manpower=5590', tag: tag) +
    v2(date, 'phase=data|tag={tag}|part=0|$metric', tag: tag) +
    v2(date, 'phase=end|tag={tag}|parts=1', tag: tag);

Future<File> logFile() async {
  final folder = await Directory.systemTemp.createTemp('hoi4-stream-');
  addTearDown(() => folder.delete(recursive: true));
  return File('${folder.path}${Platform.pathSeparator}game.log');
}

void main() {
  test(
    'no log, no mod records, partial frame, complete frame, then pause',
    () async {
      final file = await logFile();
      final reader = TelemetryLogReader(file);
      expect((await reader.poll()).status, TelemetryStreamStatus.noLog);
      await file.writeAsString(
        '[21:00:00][1936.01.02.02][effectbase.cpp:1]: ordinary\n',
      );
      expect((await reader.poll()).status, TelemetryStreamStatus.noModRecords);

      final begin = v2(
        '1936.01.03.02',
        'phase=begin|tag={tag}|parts=1|manpower=5590',
      );
      final data = v2(
        '1936.01.03.02',
        'phase=data|tag={tag}|part=0|available_civ=0|war_support=bad',
      );
      final end = v2('1936.01.03.02', 'phase=end|tag={tag}|parts=1');
      await file.writeAsString(begin + data, mode: FileMode.append);
      final partial = await reader.poll();
      expect(partial.status, TelemetryStreamStatus.incompleteFrame);
      expect(partial.latest, isNull);
      await file.writeAsString(
        end.substring(0, end.length - 1),
        mode: FileMode.append,
      );
      expect((await reader.poll()).latest, isNull);
      await file.writeAsString('\n', mode: FileMode.append);
      final complete = await reader.poll();
      expect(complete.status, TelemetryStreamStatus.completeObservation);
      expect(complete.receivedNewLine, isTrue);
      expect(complete.historical, isFalse);
      expect(complete.latest?.value('available_civ'), 0);
      expect(
        complete.latest?.status('available_civ'),
        TelemetryValueStatus.value,
      );
      expect(
        complete.latest?.status('war_support'),
        TelemetryValueStatus.invalid,
      );
      expect(complete.latest?.status('fuel'), TelemetryValueStatus.missing);
      expect(
        complete.latest?.status('unknown_field'),
        TelemetryValueStatus.unsupported,
      );
      final waiting = await reader.poll();
      expect(waiting.status, TelemetryStreamStatus.waitingNextDay);
      expect(waiting.latest, same(complete.latest));
    },
  );

  test('malformed parts and dates never complete a V2 observation', () async {
    final file = await logFile();
    await file.writeAsString('');
    final reader = TelemetryLogReader(file);
    await reader.poll();

    Future<void> reject(String contents) async {
      await file.writeAsString(contents, mode: FileMode.append);
      final result = await reader.poll();
      expect(result.status, TelemetryStreamStatus.incompleteFrame);
      expect(result.latest, isNull);
    }

    await reject(
      v2('1936.02.30.02', 'phase=begin|tag={tag}|parts=1|manpower=1') +
          v2('1936.02.30.02', 'phase=data|tag={tag}|part=0|fuel=2') +
          v2('1936.02.30.02', 'phase=end|tag={tag}|parts=1'),
    );
    await reject(
      v2('1936.11.30.02', 'phase=begin|tag={tag}|parts=2|manpower=1') +
          v2('1936.11.30.02', 'phase=data|tag={tag}|part=0|fuel=2') +
          v2('1936.11.30.02', 'phase=data|tag={tag}|part=0|stability=0.5') +
          v2('1936.11.30.02', 'phase=end|tag={tag}|parts=2'),
    );
    await reject(
      v2('1936.12.01.02', 'phase=begin|tag={tag}|parts=2|manpower=1') +
          v2('1936.12.01.02', 'phase=data|tag={tag}|part=0|fuel=2') +
          v2('1936.12.01.02', 'phase=data|tag={tag}|part=1|fuel=3') +
          v2('1936.12.01.02', 'phase=end|tag={tag}|parts=2'),
    );
    await reject(
      v2('1936.12.02.02', 'phase=begin|tag={tag}|parts=1|manpower=1') +
          v2('1936.12.02.02', 'phase=data|tag={tag}|part=0|fuel=2|fuel=3') +
          v2('1936.12.02.02', 'phase=end|tag={tag}|parts=1'),
    );
    await reject(
      v2('1936.12.03.02', 'phase=begin|tag={tag}|parts=1|manpower=1') +
          v2('1936.12.03.02', 'phase=data|tag=GER|part=0|fuel=2') +
          v2('1936.12.03.02', 'phase=end|tag={tag}|parts=1'),
    );
    await reject(
      v2('1936.12.04.02', 'phase=begin|tag={tag}|parts=1|manpower=1') +
          v2('1936.12.04.02', 'phase=data|tag={tag}|part=0|fuel=2') +
          v2('1936.12.05.02', 'phase=end|tag={tag}|parts=1'),
    );
    await reject(
      v2('1936.12.05.02', 'phase=begin|tag={tag}|parts=1|manpower=1') +
          v2('1936.12.05.02', 'phase=data|tag={tag}|part=0|fuel=2') +
          v2(
            '1936.12.05.02',
            'phase=data|tag={tag}|part=0|fuel=3',
          ).replaceFirst('HOI4_HELPER_V2|', 'broken HOI4_HELPER_V2|') +
          v2('1936.12.05.02', 'phase=end|tag={tag}|parts=1'),
    );
    await file.writeAsString(
      frame('1936.12.06.02', 'ALB', 'fuel=0'),
      mode: FileMode.append,
    );
    final result = await reader.poll();
    expect(result.latest?.gameDate, '1936.12.06.02');
    expect(result.latest?.value('fuel'), 0);
  });

  test('accepts the hour 24 used by real on_daily log rows', () async {
    final file = await logFile();
    await file.writeAsString(frame('1936.01.05.24', 'ALB', 'fuel=0'));
    final result = await TelemetryLogReader(file).poll();
    expect(result.latest?.gameDate, '1936.01.05.24');
    expect(result.latest?.value('fuel'), 0);
  });

  test('country change and date rollback clear old values at begin', () async {
    final file = await logFile();
    await file.writeAsString(frame('1936.01.05.02', 'ALB', 'fuel=10'));
    final reader = TelemetryLogReader(file);
    final historical = await reader.poll();
    expect(historical.historical, isTrue);
    expect(historical.latest?.playerTag, 'ALB');
    await file.writeAsString(
      v2('1936.01.06.02', 'phase=begin|tag=GER|parts=1|manpower=1'),
      mode: FileMode.append,
    );
    final changed = await reader.poll();
    expect(changed.latest, isNull);
    expect(changed.status, TelemetryStreamStatus.incompleteFrame);
    await file.writeAsString(
      frame('1936.01.06.02', 'GER', 'fuel=2'),
      mode: FileMode.append,
    );
    final german = await reader.poll();
    expect(german.latest?.playerTag, 'GER');
    expect(german.historical, isFalse);
    await file.writeAsString(
      v2('1936.01.02.02', 'phase=begin|tag=GER|parts=1|manpower=1'),
      mode: FileMode.append,
    );
    final rolledBack = await reader.poll();
    expect(rolledBack.latest, isNull);
    expect(rolledBack.status, TelemetryStreamStatus.incompleteFrame);
  });

  test(
    'deletion, truncation and same or larger replacement clear history',
    () async {
      final file = await logFile();
      final oldFrame = frame('1936.01.05.02', 'ALB', 'fuel=10');
      await file.writeAsString(oldFrame);
      final reader = TelemetryLogReader(file);
      expect((await reader.poll()).latest?.playerTag, 'ALB');
      await file.delete();
      expect((await reader.poll()).status, TelemetryStreamStatus.noLog);
      expect((await reader.poll()).latest, isNull);
      await file.writeAsString(frame('1936.01.02.02', 'GER', 'fuel=2'));
      expect((await reader.poll()).latest?.playerTag, 'GER');
      await file.writeAsString('');
      expect((await reader.poll()).latest, isNull);
      await file.writeAsString(oldFrame);
      expect((await reader.poll()).latest?.playerTag, 'ALB');

      final sameSize = frame('1936.01.05.02', 'GER', 'fuel=10');
      expect(sameSize.length, oldFrame.length);
      await file.writeAsString(sameSize);
      final replacedSame = await reader.poll();
      expect(replacedSame.latest?.playerTag, 'GER');
      expect(replacedSame.historical, isTrue);

      await file.writeAsString(
        frame('1936.01.06.02', 'USA', 'fuel=1000') +
            frame('1936.01.07.02', 'USA', 'fuel=2000'),
      );
      final replacedLarger = await reader.poll();
      expect(replacedLarger.latest?.playerTag, 'USA');
      expect(replacedLarger.latest?.gameDate, '1936.01.07.02');
      expect(replacedLarger.historical, isTrue);
    },
  );

  test('byte-identical file replacement starts a new log session', () async {
    final file = await logFile();
    final content = frame('1936.01.05.24', 'ALB', 'fuel=10');
    await file.writeAsString(content);
    final reader = TelemetryLogReader(file);
    final original = (await reader.poll()).latest!;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final replacement = File('${file.path}.replacement');
    await replacement.writeAsString(content);
    if (Platform.isWindows) {
      expect(
        (await replacement.stat()).changed,
        isNot((await file.stat()).changed),
      );
    }
    await file.delete();
    await replacement.rename(file.path);
    final result = await reader.poll();
    if (Platform.isWindows) {
      expect(result.latest, isNot(same(original)));
      expect(result.historical, isTrue);
    }
  });

  test(
    'shrink between measuring and reading discards old observation',
    () async {
      final file = await logFile();
      await file.writeAsString(frame('1936.01.05.02', 'ALB', 'fuel=10'));
      var change = false;
      final reader = TelemetryLogReader(
        file,
        afterLengthMeasured: () async {
          if (change) {
            change = false;
            await file.writeAsString('');
          }
        },
      );
      await reader.poll();
      await file.writeAsString(
        frame('1936.01.06.02', 'ALB', 'fuel=20'),
        mode: FileMode.append,
      );
      change = true;
      final raced = await reader.poll();
      expect(raced.latest, isNull);
      expect(raced.receivedNewLine, isFalse);
      expect((await reader.poll()).latest, isNull);
    },
  );

  test('same-size replacement after length measurement is discarded', () async {
    final file = await logFile();
    final oldFrame = frame('1936.01.05.02', 'ALB', 'fuel=10');
    await file.writeAsString(oldFrame);
    var change = false;
    final reader = TelemetryLogReader(
      file,
      afterLengthMeasured: () async {
        if (change) {
          change = false;
          await file.writeAsString(frame('1936.01.06.02', 'GER', 'fuel=20'));
        }
      },
    );
    await reader.poll();
    await file.writeAsString(
      frame('1936.01.06.02', 'ALB', 'fuel=20'),
      mode: FileMode.append,
    );
    change = true;
    final raced = await reader.poll();
    expect(raced.latest, isNull);
    expect(raced.receivedNewLine, isFalse);
    final recovered = await reader.poll();
    expect(recovered.latest?.playerTag, 'GER');
    expect(recovered.historical, isTrue);
  });

  test(
    'large append is consumed in bounded polls without mixing frames',
    () async {
      final file = await logFile();
      await file.writeAsString('');
      final reader = TelemetryLogReader(file);
      await reader.poll();
      await file.writeAsString(
        ('[21:00][1936.01.02.02][other]: line\n' * 4000) +
            frame('1936.01.03.02', 'ALB', 'fuel=3'),
        mode: FileMode.append,
      );
      final first = await reader.poll();
      expect(first.latest, isNull);
      TelemetryLogPoll current = first;
      for (var i = 0; i < 6 && current.latest == null; i++) {
        current = await reader.poll();
      }
      expect(current.latest?.gameDate, '1936.01.03.02');
      expect(current.latest?.value('fuel'), 3);
    },
  );
}
