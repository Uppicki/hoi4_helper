import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'saves_controller.dart';

class SavesScreen extends StatefulWidget {
  const SavesScreen({super.key, this.controller, this.pickDirectory});

  final SavesController? controller;
  final Future<String?> Function()? pickDirectory;

  @override
  State<SavesScreen> createState() => _SavesScreenState();
}

class _SavesScreenState extends State<SavesScreen> {
  late final SavesController controller;
  final pathInput = TextEditingController();
  bool choosingFolder = false;

  bool get busy => controller.busy || choosingFolder;
  Color get accent => Theme.of(context).colorScheme.primary;
  TextStyle get eyebrow => TextStyle(
    color: accent,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.6,
  );

  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? SavesController();
    pathInput.text = controller.folder ?? '';
  }

  @override
  void dispose() {
    pathInput.dispose();
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  Future<void> chooseFolder() async {
    setState(() => choosingFolder = true);
    try {
      final path =
          await (widget.pickDirectory?.call() ??
              getDirectoryPath(
                initialDirectory: controller.folder,
                confirmButtonText: 'Выбрать папку',
              ));
      if (!mounted || path == null) return;
      pathInput.text = path;
      await controller.openFolder(path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось открыть диалог. Введите путь вручную.'),
        ),
      );
    } finally {
      if (mounted) setState(() => choosingFolder = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide) SizedBox(width: 240, child: sidebar()),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(wide ? 36 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        header(),
                        if (!wide) ...[const SizedBox(height: 24), modes()],
                        const SizedBox(height: 28),
                        folderCard(),
                        if (busy) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(),
                        ],
                        if (controller.error case final error?) ...[
                          const SizedBox(height: 16),
                          notice(error, Icons.error_outline, error: true),
                        ],
                        const SizedBox(height: 28),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: savesCard()),
                              const SizedBox(width: 20),
                              SizedBox(width: 310, child: detailsCard()),
                            ],
                          )
                        else ...[
                          savesCard(),
                          const SizedBox(height: 20),
                          detailsCard(),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          'Оригинальные файлы остаются без изменений. '
                          'Список обновляется по кнопке.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget sidebar() => Container(
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
        Text('РЕЖИМ РАБОТЫ', style: eyebrow),
        const SizedBox(height: 16),
        modes(),
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

  Widget modes() => Column(
    children: [
      modeTile(
        WorkMode.assistant,
        Icons.assistant_outlined,
        'Помощник',
        'Анализ пока недоступен',
      ),
      const SizedBox(height: 8),
      modeTile(
        WorkMode.viewOnly,
        Icons.folder_outlined,
        'Только просмотр',
        'Выбор и загрузка файлов',
      ),
    ],
  );

  Widget modeTile(WorkMode mode, IconData icon, String title, String subtitle) {
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

  Widget header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('РАБОЧЕЕ ПРОСТРАНСТВО', style: eyebrow),
      const SizedBox(height: 10),
      const Text(
        'Сохранения',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'Выберите папку и загрузите сохранение вашей кампании.',
        style: TextStyle(color: Color(0xFFA6B1A9)),
      ),
    ],
  );

  Widget panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: const Color(0xFF1B2420),
      border: Border.all(color: const Color(0xFF303B33)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget folderCard() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '01  /  Папка сохранений',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Укажите папку с файлами .hoi4. Вложенные папки не сканируются.',
          style: TextStyle(color: Color(0xFFA6B1A9), fontSize: 13),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: pathInput,
          enabled: !busy,
          onSubmitted: (path) => controller.openFolder(path),
          decoration: const InputDecoration(
            labelText: 'Путь к папке',
            hintText: r'C:\…\Hearts of Iron IV\save games',
            prefixIcon: Icon(Icons.folder_open_outlined),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : chooseFolder,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Выбрать папку'),
            ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => controller.openFolder(pathInput.text),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Обновить список'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget savesCard() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '02  /  Выберите сохранение',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            Text('${controller.saves.length}', style: TextStyle(color: accent)),
          ],
        ),
        const SizedBox(height: 18),
        if (controller.saves.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 44),
            child: Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 42,
                    color: Colors.white38,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    controller.folder == null
                        ? 'Сначала выберите папку'
                        : controller.busy
                        ? 'Ищем сохранения…'
                        : controller.error != null
                        ? 'Список недоступен'
                        : 'Сохранения .hoi4 не найдены',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 340,
            child: ListView.separated(
              itemCount: controller.saves.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final save = controller.saves[index];
                final active = controller.selected?.path == save.path;
                return Material(
                  color: active ? const Color(0xFF30372A) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: ListTile(
                    enabled: !busy,
                    selected: active,
                    selectedColor: accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(Icons.description_outlined),
                    title: Text(save.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${size(save.size)} · ${date(save.modified)}',
                    ),
                    trailing: active
                        ? const Icon(Icons.check_circle_outline)
                        : null,
                    onTap: () => controller.select(save),
                  ),
                );
              },
            ),
          ),
      ],
    ),
  );

  Widget detailsCard() {
    final save = controller.selected;
    final loaded = controller.loaded;
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '03  /  Загрузка',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Icon(
            loaded == null ? Icons.upload_file_outlined : Icons.task_alt,
            size: 36,
            color: accent,
          ),
          const SizedBox(height: 16),
          Text(
            save?.name ?? 'Сохранение не выбрано',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          if (save != null) ...[
            Text('Размер: ${size(loaded?.bytesRead ?? save.size)}'),
            const SizedBox(height: 6),
            Text('Изменён: ${date(loaded?.file.modified ?? save.modified)}'),
            const SizedBox(height: 10),
            SelectableText(
              save.path,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ] else
            const Text('Выберите файл из списка слева или выше.'),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: save == null || busy ? null : controller.loadSelected,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(
                loaded == null ? 'Загрузить сохранение' : 'Загрузить повторно',
              ),
            ),
          ),
          if (loaded != null) ...[
            const SizedBox(height: 16),
            notice(
              'Файл прочитан · ${date(loaded.loadedAt)}',
              Icons.check_circle_outline,
            ),
          ],
          if (controller.worldState case final state?) ...[
            const SizedBox(height: 18),
            Text(
              loaded != null ? 'СОСТОЯНИЕ ПО СОХРАНЕНИЮ' : 'СОСТОЯНИЕ МИРА',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _stateLine(
              'Игровая дата',
              state.gameDate?.toString() ?? 'Неизвестно',
            ),
            _stateLine('Страна игрока', state.playerTag ?? 'Неизвестно'),
            _stateLine('Версия игры', state.gameVersion ?? 'Неизвестно'),
            _stateLine('Источник', state.sourceDescription),
            const SizedBox(height: 4),
            if (loaded != null)
              const Text(
                'Пока доступны только данные заголовка. '
                'Промышленность, армии и другие сведения мира ещё не разбираются.',
                style: TextStyle(fontSize: 11, color: Colors.white60),
              ),
          ],
          if (controller.mode == WorkMode.assistant) ...[
            const SizedBox(height: 22),
            const Divider(),
            const SizedBox(height: 12),
            Text('ПОМОЩНИК', style: eyebrow),
            const SizedBox(height: 10),
            const Text('Анализ появится на следующем этапе.'),
            const SizedBox(height: 6),
            const Text(
              'Сейчас можно выбрать и прочитать файл сохранения.',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ],
      ),
    );
  }

  Widget notice(String text, IconData icon, {bool error = false}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? const Color(0xFF3B2424) : const Color(0xFF26372B),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: error ? const Color(0xFFFFB4AB) : accent),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );

  Widget _stateLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white60),
        ),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    ),
  );

  String size(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  String date(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
