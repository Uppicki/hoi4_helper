import 'dart:io';

import 'package:hoi4_helper/core/telemetry_catalog.dart';

import 'telemetry_mod_builder.dart';

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

  validateWarOverviewSupport(
    effects: File(
      '$root/documentation/effects_documentation.md',
    ).readAsStringSync(),
    triggers: File(
      '$root/documentation/triggers_documentation.md',
    ).readAsStringSync(),
    warInterface: File('$root/interface/waroverview.gui').readAsStringSync(),
  );
  final metrics = telemetryMetrics.values.where(isDefined).toList();
  final omitted = telemetryMetrics.length - metrics.length;
  final output = buildTelemetryMod(metrics);
  final target = File(
    'telemetry_mod${Platform.pathSeparator}hoi4_helper_telemetry${Platform.pathSeparator}common${Platform.pathSeparator}on_actions${Platform.pathSeparator}hoi4_helper_telemetry.txt',
  );
  target.writeAsStringSync(output);
  stdout.writeln(
    'Generated ${metrics.length} values in ${(metrics.length + 11) ~/ 12} metric parts, V3 world scope; omitted $omitted unavailable fields.',
  );
}
