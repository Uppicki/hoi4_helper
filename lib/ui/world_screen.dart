import 'package:flutter/material.dart';

import '../core/world_state.dart';

/// The destination for a chosen snapshot. Sections can grow as parsing grows.
class WorldScreen extends StatelessWidget {
  const WorldScreen({super.key, required this.snapshot});

  final WorldStateSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final save = snapshot.loadedSave;
    var swipeDistance = 0.0;
    return Scaffold(
      appBar: AppBar(title: const Text('Состояние мира')),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => swipeDistance = 0,
        onHorizontalDragUpdate: (details) =>
            swipeDistance += details.primaryDelta ?? 0,
        onHorizontalDragEnd: (details) {
          if (swipeDistance > 80 || (details.primaryVelocity ?? 0) > 350) {
            Navigator.of(context).maybePop();
          }
        },
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'СНИМОК СОХРАНЕНИЯ',
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      snapshot.playerTag ?? 'Страна не определена',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snapshot.gameDate?.toString() ??
                          'Игровая дата неизвестна',
                      style: TextStyle(fontSize: 20, color: accent),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Показано состояние завершённого сохранения. '
                      'Оно не обновляется непрерывно вместе с игрой.',
                      style: TextStyle(color: Color(0xFFA6B1A9)),
                    ),
                    const SizedBox(height: 28),
                    _panel(
                      context,
                      title: 'Сведения о снимке',
                      child: Column(
                        children: [
                          _field('Страна игрока', snapshot.playerTag),
                          _field('Идеология', snapshot.ideology),
                          _field('Сложность', snapshot.difficulty),
                          _field('Версия игры', snapshot.gameVersion),
                          _field('Источник', snapshot.sourceDescription),
                          _field('Прочитан', _date(snapshot.readAt)),
                          if (save != null) ...[
                            _field('Сохранение', save.file.name),
                            _field('Размер', _size(save.bytesRead)),
                            _field('Файл изменён', _date(save.file.modified)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Разделы мира',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Следующие разделы появятся после разбора содержимого сейва. '
                      'Пока неизвестные значения не подменяются нулями.',
                      style: TextStyle(color: Color(0xFFA6B1A9)),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 640;
                        final width = wide
                            ? (constraints.maxWidth - 16) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            _pending(
                              context,
                              width,
                              Icons.science_outlined,
                              'Исследования',
                            ),
                            _pending(
                              context,
                              width,
                              Icons.precision_manufacturing_outlined,
                              'Производство',
                            ),
                            _pending(
                              context,
                              width,
                              Icons.construction_outlined,
                              'Строительство',
                            ),
                            _pending(
                              context,
                              width,
                              Icons.public_outlined,
                              'Карта и армии',
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(
    BuildContext context, {
    required String title,
    required Widget child,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: const Color(0xFF303B33)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );

  Widget _field(String label, String? value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 155,
          child: Text(label, style: const TextStyle(color: Color(0xFFA6B1A9))),
        ),
        Expanded(child: Text(value ?? 'Неизвестно')),
      ],
    ),
  );

  Widget _pending(
    BuildContext context,
    double width,
    IconData icon,
    String title,
  ) => SizedBox(
    width: width,
    child: _panel(
      context,
      title: title,
      child: Row(
        children: [
          Icon(icon, color: Colors.white38),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Данные пока недоступны',
              style: TextStyle(color: Color(0xFFA6B1A9)),
            ),
          ),
        ],
      ),
    ),
  );

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
