import 'package:flutter/material.dart';

import 'saves_controller.dart';

/// The navigation rail shared by the save picker and world pages.
class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key, required this.controller});

  final SavesController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final accent = Theme.of(context).colorScheme.primary;
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF18201C),
          border: Border(right: BorderSide(color: Color(0xFF303B33))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.explore_outlined, size: 36, color: accent),
            const SizedBox(height: 16),
            const Text(
              'HOI IV',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const Text('Локальный помощник'),
            const SizedBox(height: 48),
            Text(
              'РЕЖИМ РАБОТЫ',
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            _WorkModeTiles(controller: controller),
            const Spacer(),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Первый этап',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Выбор и загрузка сохранений',
              style: TextStyle(color: Color(0xFFA6B1A9), fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
}

/// The same mode picker outside the sidebar on compact layouts.
class WorkModeSelector extends StatelessWidget {
  const WorkModeSelector({super.key, required this.controller});

  final SavesController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _WorkModeTiles(controller: controller),
  );
}

class _WorkModeTiles extends StatelessWidget {
  const _WorkModeTiles({required this.controller});

  final SavesController controller;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _modeTile(
        context,
        WorkMode.assistant,
        Icons.assistant_outlined,
        'Помощник',
        'Анализ пока недоступен',
      ),
      const SizedBox(height: 8),
      _modeTile(
        context,
        WorkMode.viewOnly,
        Icons.folder_outlined,
        'Только просмотр',
        'Выбор и загрузка файлов',
      ),
    ],
  );

  Widget _modeTile(
    BuildContext context,
    WorkMode mode,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final accent = Theme.of(context).colorScheme.primary;
    final active = controller.mode == mode;
    return Semantics(
      selected: active,
      child: Material(
        color: active ? const Color(0xFF30372A) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => controller.changeMode(mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: active ? accent : Colors.white54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(color: active ? accent : null),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
                if (active) Icon(Icons.check, size: 16, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
