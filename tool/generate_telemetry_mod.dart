import 'dart:io';

import 'package:hoi4_helper/core/telemetry_catalog.dart';

/// Generates a read-only HOI4 mod for the installed game's documented values.
/// Usage: dart run tool/generate_telemetry_mod.dart [game_root]
void main(List<String> args) {
  final root = args.isNotEmpty
      ? args.single
      : Platform.environment['HOI4_GAME_PATH'] ??
            '${Directory.current.path.split(':').first}:\\games\\Hearts of Iron IV';
  final documentation = File(
    '$root${Platform.pathSeparator}documentation${Platform.pathSeparator}dynamic_variables_documentation.md',
  ).readAsStringSync();
  final country = documentation
      .split('## Dynamic variables for scope country')
      .last
      .split('## Dynamic variables for scope state')
      .first;
  final supported = RegExp(
    r'^### ([a-z_]+)',
    multiLine: true,
  ).allMatches(country).map((match) => match.group(1)!).toSet();
  final resourceDefinitions = File(
    '$root${Platform.pathSeparator}common${Platform.pathSeparator}resources${Platform.pathSeparator}00_resources.txt',
  ).readAsStringSync();
  final equipmentFolder = Directory(
    '$root${Platform.pathSeparator}common${Platform.pathSeparator}units${Platform.pathSeparator}equipment',
  );
  final equipmentDefinitions = equipmentFolder
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.txt'))
      .map((file) => file.readAsStringSync())
      .join('\n');

  bool isDefined(TelemetryMetric metric) {
    final variable = metric.variable.split('@').first;
    if (!supported.contains(variable)) return false;
    if (metric.group == 'resources') {
      final resource = metric.variable.split('@').last;
      return RegExp('\\b$resource\\s*=\\s*\\{').hasMatch(resourceDefinitions);
    }
    if (metric.group == 'equipment') {
      final equipment = metric.variable.split('@').last;
      return RegExp('\\b$equipment\\s*=\\s*\\{').hasMatch(equipmentDefinitions);
    }
    return true;
  }

  final metrics = telemetryMetrics.values.where(isDefined).toList();
  final omitted = telemetryMetrics.length - metrics.length;
  final chunks = <List<TelemetryMetric>>[
    for (var offset = 0; offset < metrics.length; offset += 12)
      metrics.skip(offset).take(12).toList(),
  ];
  final output = StringBuffer()
    ..writeln('# Generated from documented values of the installed game.')
    ..writeln(
      '# Read-only temp variables; no country or save variables are changed.',
    )
    ..writeln('on_actions = {')
    ..writeln('  on_daily = {')
    ..writeln('    effect = {')
    ..writeln('      if = {')
    ..writeln('        limit = { is_ai = no }')
    ..writeln(
      '        log = "HOI4_HELPER_V2|phase=begin|tag=[ROOT.GetTag]|parts=${chunks.length}|manpower=[ROOT.GetManpower]"',
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
      '        log = "HOI4_HELPER_V2|phase=data|tag=[ROOT.GetTag]|part=$part|${fields.join('|')}"',
    );
  }
  output
    ..writeln(
      '        log = "HOI4_HELPER_V2|phase=end|tag=[ROOT.GetTag]|parts=${chunks.length}"',
    )
    ..writeln('      }')
    ..writeln('    }')
    ..writeln('  }')
    ..writeln('}');
  final target = File(
    'telemetry_mod${Platform.pathSeparator}hoi4_helper_telemetry${Platform.pathSeparator}common${Platform.pathSeparator}on_actions${Platform.pathSeparator}hoi4_helper_telemetry.txt',
  );
  target.writeAsStringSync(output.toString());
  stdout.writeln(
    'Generated ${metrics.length} values in ${chunks.length} parts; omitted $omitted unavailable fields.',
  );
}
