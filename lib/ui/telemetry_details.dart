import 'package:flutter/material.dart';

import '../core/game_localization.dart';
import '../core/telemetry_catalog.dart';
import '../core/telemetry_log.dart';

/// Detailed player-country values from the telemetry mod. Unknown stays blank.
class TelemetryDetails extends StatelessWidget {
  const TelemetryDetails({
    super.key,
    required this.observation,
    required this.names,
    required this.language,
  });

  final TelemetryObservation observation;
  final GameLocalization names;
  final GameLanguage language;

  bool get _ru => language == GameLanguage.russian;
  String _label(String ru, String en) => _ru ? ru : en;

  String _format(String key) {
    final value = observation.value(key);
    final metric = telemetryMetrics[key];
    if (value == null || metric == null) return '—';
    switch (metric.format) {
      case TelemetryFormat.count:
        return value.round().toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ' ',
        );
      case TelemetryFormat.decimal:
        return value.toStringAsFixed(2);
      case TelemetryFormat.percent:
        return '${(value * 100).toStringAsFixed(1)} %';
    }
  }

  Widget _card(BuildContext context, String title, Widget content) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: const Color(0xFF35433A)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      children: [content],
    ),
  );

  Widget _metrics(BuildContext context, String ru, String en, String group) {
    final entries = telemetryScalars
        .where(
          (metric) =>
              metric.group == group && observation.value(metric.key) != null,
        )
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return _card(
      context,
      _label(ru, en),
      Column(
        children: [
          for (final metric in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(child: Text(_ru ? metric.ru : metric.en)),
                  const SizedBox(width: 12),
                  Text(_format(metric.key)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _resourceName(String resource) {
    const translations = {
      'oil': ['Нефть', 'Oil'],
      'aluminium': ['Алюминий', 'Aluminium'],
      'rubber': ['Резина', 'Rubber'],
      'tungsten': ['Вольфрам', 'Tungsten'],
      'steel': ['Сталь', 'Steel'],
      'chromium': ['Хром', 'Chromium'],
      'coal': ['Уголь', 'Coal'],
    };
    final label = translations[resource];
    return label == null ? names.name(resource) : label[_ru ? 0 : 1];
  }

  Widget _table(
    BuildContext context, {
    required String titleRu,
    required String titleEn,
    required List<String> items,
    required String Function(String, String) key,
    required String Function(String) itemName,
    required List<(String, String, String)> columns,
  }) {
    final rows = items
        .where(
          (item) => columns.any(
            (column) => observation.value(key(item, column.$1)) != null,
          ),
        )
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return _card(
      context,
      _label(titleRu, titleEn),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          horizontalMargin: 8,
          columns: [
            DataColumn(label: Text(_label('Вид', 'Type'))),
            for (final column in columns)
              DataColumn(label: Text(_label(column.$2, column.$3))),
          ],
          rows: [
            for (final item in rows)
              DataRow(
                cells: [
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(
                        itemName(item),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  for (final column in columns)
                    DataCell(Text(_format(key(item, column.$1)))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (observation.schemaVersion < 2) {
      return Text(
        _label(
          'Установленный мод пока передаёт только дату, страну и армейский резерв.',
          'The installed mod currently reports only date, country and manpower.',
        ),
        style: const TextStyle(color: Color(0xFFAAB7AD)),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final twoColumns = width >= 900;
    final cardWidth = twoColumns ? (width.clamp(0, 1220) - 64) / 2 : width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _label(
            'Дополнительные данные страны (${observation.values.length} показателей)',
            'Additional country data (${observation.values.length} values)',
          ),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          _label(
            'Показатели получены на указанную выше игровую дату. Неизвестные значения показаны прочерком.',
            'Values were received on the game date above. Unknown values are shown as dashes.',
          ),
          style: const TextStyle(color: Color(0xFFAAB7AD), fontSize: 12),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final group in [
              ('Политика', 'Politics', 'politics'),
              ('Людские ресурсы', 'Manpower', 'manpower'),
              ('Вооружённые силы', 'Armed forces', 'army'),
              ('Промышленность', 'Industry', 'industry'),
              ('Топливо', 'Fuel', 'fuel'),
              ('Исследования', 'Research', 'research'),
              ('Территории', 'Territory', 'territory'),
              ('Разведка', 'Intelligence', 'intelligence'),
            ])
              SizedBox(
                width: cardWidth,
                child: _metrics(context, group.$1, group.$2, group.$3),
              ),
            SizedBox(
              width: cardWidth,
              child: _table(
                context,
                titleRu: 'Сырьевые ресурсы',
                titleEn: 'Raw resources',
                items: telemetryResources,
                key: (item, column) => 'res_${item}_$column',
                itemName: _resourceName,
                columns: const [
                  ('balance', 'Баланс', 'Balance'),
                  ('produced', 'Добыча', 'Produced'),
                  ('consumed', 'Расход', 'Consumed'),
                  ('imported', 'Импорт', 'Imported'),
                  ('exported', 'Экспорт', 'Exported'),
                ],
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _table(
                context,
                titleRu: 'Снаряжение',
                titleEn: 'Equipment',
                items: telemetryEquipment,
                key: (item, column) => 'eq_${item}_$column',
                itemName: (item) => names.name(item),
                columns: const [
                  ('stock', 'В резерве', 'Stockpile'),
                  ('field', 'В войсках', 'In armies'),
                  ('need', 'Потребность', 'Required'),
                ],
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _table(
                context,
                titleRu: 'Построено за кампанию',
                titleEn: 'Constructed in campaign',
                items: telemetryConstruction,
                key: (item, _) => 'built_$item',
                itemName: (item) => names.name(item),
                columns: const [('total', 'Всего', 'Total')],
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _table(
                context,
                titleRu: 'Произведено за кампанию',
                titleEn: 'Produced in campaign',
                items: telemetryProduction,
                key: (item, _) => 'produced_$item',
                itemName: (item) => names.name(item),
                columns: const [('total', 'Всего', 'Total')],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
