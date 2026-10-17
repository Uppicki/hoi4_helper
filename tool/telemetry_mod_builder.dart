import 'package:hoi4_helper/core/telemetry_catalog.dart';

/// The narrow policy depends on these documented commands and player war UI.
/// A missing capability must stop generation rather than silently emit a list.
void validateWarOverviewSupport({
  required String effects,
  required String triggers,
  required String warInterface,
}) {
  for (final command in [
    'every_enemy_country',
    'set_temp_variable',
    'add_to_temp_variable',
  ]) {
    if (!RegExp(
      '^## $command'
      r'\r?$',
      multiLine: true,
    ).hasMatch(effects)) {
      throw FormatException('Missing documented effect: $command');
    }
  }
  if (!RegExp(r'^## has_war_with\r?$', multiLine: true).hasMatch(triggers) ||
      !warInterface.contains('attacker_participants') ||
      !warInterface.contains('defender_participants')) {
    throw const FormatException(
      'Player war membership capability is unverified.',
    );
  }
}

/// Generates only player metrics and positive direct war membership.
/// The source loop never reads a foreign country's hidden numeric values.
String buildTelemetryMod(List<TelemetryMetric> metrics) {
  final chunks = <List<TelemetryMetric>>[
    for (var offset = 0; offset < metrics.length; offset += 12)
      metrics.skip(offset).take(12).toList(),
  ];
  final output = StringBuffer()
    ..writeln('# Generated from documented values of the installed game.')
    ..writeln(
      '# Only temp variables are changed. World scope: own war opponents.',
    )
    ..writeln('on_actions = {')
    ..writeln('  on_daily = {')
    ..writeln('    effect = {')
    ..writeln('      if = {')
    ..writeln('        limit = { is_ai = no }')
    ..writeln(
      '        log = "HOI4_HELPER_V3|phase=begin|tag=[ROOT.GetTag]|parts=${chunks.length}|manpower=[ROOT.GetManpower]|world=player_war_opponents|policy=own_war_participants_v1"',
    );
  for (var part = 0; part < chunks.length; part++) {
    final fields = <String>[];
    for (var index = 0; index < chunks[part].length; index++) {
      final metric = chunks[part][index];
      final variable = 'hh_${part}_$index';
      output.writeln(
        '        set_temp_variable = { var = $variable value = ${metric.variable} }',
      );
      final digits = metric.format == TelemetryFormat.count ? 0 : 3;
      fields.add('${metric.key}=[?$variable|$digits]');
    }
    output.writeln(
      '        log = "HOI4_HELPER_V3|phase=data|tag=[ROOT.GetTag]|part=$part|${fields.join('|')}"',
    );
  }
  output
    ..writeln('        set_temp_variable = { hh_war_opponents = 0 }')
    ..writeln('        every_enemy_country = {')
    ..writeln('          if = {')
    ..writeln('            limit = { has_war_with = ROOT }')
    ..writeln('            ROOT = {')
    ..writeln('              add_to_temp_variable = { hh_war_opponents = 1 }')
    ..writeln('            }')
    ..writeln(
      '            log = "HOI4_HELPER_V3|phase=relation|tag=[ROOT.GetTag]|other=[THIS.GetTag]|at_war=1"',
    )
    ..writeln('          }')
    ..writeln('        }')
    ..writeln(
      '        log = "HOI4_HELPER_V3|phase=end|tag=[ROOT.GetTag]|parts=${chunks.length}|enemies=[?hh_war_opponents|0]"',
    )
    ..writeln('      }')
    ..writeln('    }')
    ..writeln('  }')
    ..writeln('}');
  return output.toString();
}
