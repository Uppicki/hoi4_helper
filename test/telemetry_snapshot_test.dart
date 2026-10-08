import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/telemetry_log.dart';
import 'package:hoi4_helper/core/telemetry_snapshot.dart';

void main() {
  test('telemetry carries known fields without inventing a save identity', () {
    final readAt = DateTime(2026, 10, 8, 21);
    final snapshot = telemetryDisplaySnapshot(
      const TelemetryObservation(
        gameDate: '1936.01.02.02',
        playerTag: 'ALB',
        manpower: 5562,
      ),
      readAt: readAt,
    );
    expect(snapshot.playerTag, 'ALB');
    expect(snapshot.gameDate.toString(), '1936.01.02 02:00');
    expect(snapshot.readAt, readAt);
    expect(snapshot.world, isNull);
    expect(snapshot.identity, isNull);
    expect(snapshot.loadedSave, isNull);
  });

  test('display snapshot uses receipt and source attached to observation', () {
    final receivedAt = DateTime(2026, 10, 8, 21, 15);
    final snapshot = telemetryDisplaySnapshot(
      TelemetryObservation(
        gameDate: '1936.01.02.02',
        playerTag: 'ALB',
        manpower: 5562,
        receivedAt: receivedAt,
        logSource: r'C:\logs\game.log',
      ),
      readAt: DateTime(2026, 10, 8, 22),
    );
    expect(snapshot.readAt, receivedAt);
    expect(snapshot.sourceDescription, r'C:\logs\game.log');
    expect(snapshot.identity, isNull);
  });

  test('invalid telemetry dates remain unknown', () {
    expect(parseTelemetryGameDate('1936.02.29.02'), isNull);
    expect(parseTelemetryGameDate('1936.01.02.24'), isNull);
    expect(
      telemetryDisplaySnapshot(null, readAt: DateTime(2026)).gameDate,
      isNull,
    );
  });
}
