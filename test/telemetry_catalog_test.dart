import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/telemetry_catalog.dart';

void main() {
  test('every declared metric has units, provenance and a usable domain', () {
    expect(telemetryMetrics.length, 221);
    for (final metric in telemetryMetrics.values) {
      expect(metric.unitRu, isNotEmpty, reason: metric.key);
      expect(metric.unitEn, isNotEmpty, reason: metric.key);
      expect(metric.sourceRu, contains(metric.variable), reason: metric.key);
      expect(metric.sourceEn, contains(metric.variable), reason: metric.key);
      expect(metric.domain.descriptionRu, isNotEmpty, reason: metric.key);
      expect(metric.domain.descriptionEn, isNotEmpty, reason: metric.key);
      expect(metric.domain.accepts(double.nan), isFalse, reason: metric.key);
      expect(
        metric.domain.accepts(double.infinity),
        isFalse,
        reason: metric.key,
      );
      if (metric.format == TelemetryFormat.count) {
        expect(
          metric.domain,
          anyOf(
            TelemetryDomain.nonNegativeInteger,
            TelemetryDomain.signedInteger,
          ),
          reason: metric.key,
        );
      }
      if (metric.format == TelemetryFormat.percent) {
        expect(metric.unitRu, '%', reason: metric.key);
      }
    }
  });

  test('keeps zero distinct from invalid values and allows signed flows', () {
    final factory = telemetryMetrics['civilian_factories']!;
    expect(factory.domain.accepts(0), isTrue);
    expect(factory.domain.accepts(-1), isFalse);
    expect(factory.domain.accepts(1.5), isFalse);

    final balance = telemetryMetrics['res_steel_balance']!;
    expect(balance.domain.accepts(-3), isTrue);
    expect(balance.domain.accepts(-3.5), isFalse);

    final produced = telemetryMetrics['res_steel_produced']!;
    expect(produced.domain.accepts(-1), isFalse);

    final daily = telemetryMetrics['political_power_daily']!;
    expect(daily.domain.accepts(-0.5), isTrue);
    expect(daily.unitEn, 'points/day');
  });

  test('uses verified fraction bounds without inventing other hard caps', () {
    for (final key in ['war_support', 'party_democratic', 'energy_ratio']) {
      final domain = telemetryMetrics[key]!.domain;
      expect(domain.accepts(0), isTrue, reason: key);
      expect(domain.accepts(1), isTrue, reason: key);
      expect(domain.accepts(-0.01), isFalse, reason: key);
      expect(domain.accepts(1.01), isFalse, reason: key);
    }

    expect(telemetryMetrics['stability']!.domain, TelemetryDomain.finite);
    expect(telemetryMetrics['stability']!.domain.accepts(1.01), isTrue);
  });
}
