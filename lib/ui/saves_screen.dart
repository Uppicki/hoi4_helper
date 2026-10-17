import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/game_localization.dart';
import 'app_router.dart';
import 'app_sidebar.dart';
import 'saves_controller.dart';

class SavesScreen extends StatefulWidget {
  const SavesScreen({
    super.key,
    this.controller,
    this.pickDirectory,
    this.language,
    this.localizationRepository,
    this.onChangeSource,
  });

  final SavesController? controller;
  final Future<String?> Function()? pickDirectory;
  final ValueNotifier<GameLanguage>? language;
  final GameLocalizationRepository? localizationRepository;
  final VoidCallback? onChangeSource;

  @override
  State<SavesScreen> createState() => _SavesScreenState();
}

class _SavesScreenState extends State<SavesScreen> {
  late final SavesController controller;
  final pathInput = TextEditingController();
  bool choosingFolder = false;
  double _swipeDistance = 0;
  GameLanguage _language = GameLanguage.russian;
  GameLocalization _names = const GameLocalization(GameLanguage.russian, {});
  GameLocalizationRepository get _localizationRepository =>
      widget.localizationRepository ?? GameLocalizationRepository.shared;

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
    _language = widget.language?.value ?? GameLanguage.russian;
    _names = GameLocalization(_language, const {});
    widget.language?.addListener(_onLanguageChanged);
    _loadLocalization();
  }

  void _onLanguageChanged() {
    final next = widget.language?.value;
    if (next == null || next == _language) return;
    setState(() {
      _language = next;
      _names = GameLocalization(next, const {});
    });
    _loadLocalization();
  }

  Future<void> _loadLocalization() async {
    final requested = _language;
    final names = await _localizationRepository.load(requested);
    if (mounted && requested == _language) setState(() => _names = names);
  }

  @override
  void dispose() {
    widget.language?.removeListener(_onLanguageChanged);
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

  void openSelectedWorld() {
    final snapshot = controller.worldState;
    if (snapshot == null || controller.previewLoading) return;
    AppRouter.openWorld(context, snapshot);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final windowSize = MediaQuery.sizeOf(context);
            final wide =
                windowSize.width >= 1000 &&
                constraints.maxWidth >= 760 &&
                constraints.maxHeight >= 650;
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => _swipeDistance = 0,
              onHorizontalDragUpdate: (details) =>
                  _swipeDistance += details.primaryDelta ?? 0,
              onHorizontalDragEnd: (details) {
                if (_swipeDistance < -80 ||
                    (details.primaryVelocity ?? 0) < -350) {
                  openSelectedWorld();
                }
              },
              child: wide
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header(),
                          const SizedBox(height: 18),
                          folderCard(wide: true),
                          if (busy) ...[
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(),
                          ],
                          if (controller.selected == null &&
                              controller.error != null) ...[
                            const SizedBox(height: 8),
                            notice(
                              controller.error!,
                              Icons.error_outline,
                              error: true,
                            ),
                          ],
                          const SizedBox(height: 18),
                          Expanded(child: savesWorkspace(true)),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header(),
                          const SizedBox(height: 24),
                          WorkModeSelector(controller: controller),
                          const SizedBox(height: 28),
                          folderCard(),
                          if (busy) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                          ],
                          if (controller.selected == null &&
                              controller.error != null) ...[
                            const SizedBox(height: 16),
                            notice(
                              controller.error!,
                              Icons.error_outline,
                              error: true,
                            ),
                          ],
                          const SizedBox(height: 28),
                          savesWorkspace(false),
                        ],
                      ),
                    ),
            );
          },
        ),
      ),
    ),
  );

  Widget header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('ИСТОЧНИК 02', style: eyebrow),
      const SizedBox(height: 10),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Сохранения',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
          ),
          if (widget.onChangeSource != null)
            OutlinedButton.icon(
              key: const Key('change-source-from-saves'),
              onPressed: widget.onChangeSource,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Изменить источник'),
            ),
        ],
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

  Widget folderCard({bool wide = false}) => panel(
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
        SizedBox(height: wide ? 12 : 18),
        if (wide)
          Row(
            children: [
              Expanded(child: pathField()),
              const SizedBox(width: 12),
              folderButtons().first,
              const SizedBox(width: 12),
              folderButtons().last,
            ],
          )
        else ...[
          pathField(),
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 10, children: folderButtons()),
        ],
      ],
    ),
  );

  Widget pathField() => TextField(
    controller: pathInput,
    enabled: !busy,
    onSubmitted: (path) => controller.openFolder(path),
    decoration: const InputDecoration(
      labelText: 'Путь к папке',
      hintText: r'C:\…\Hearts of Iron IV\save games',
      prefixIcon: Icon(Icons.folder_open_outlined),
    ),
  );

  List<Widget> folderButtons() => [
    FilledButton.icon(
      onPressed: busy ? null : chooseFolder,
      icon: const Icon(Icons.folder_open, size: 18),
      label: const Text('Выбрать папку'),
    ),
    OutlinedButton.icon(
      onPressed: busy ? null : () => controller.openFolder(pathInput.text),
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Обновить список'),
    ),
  ];

  Widget savesWorkspace(bool wide) => panel(
    wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: savesCard(fillHeight: true)),
              const SizedBox(width: 20),
              Container(width: 1, color: const Color(0xFF303B33)),
              const SizedBox(width: 20),
              SizedBox(
                width: 300,
                child: SingleChildScrollView(child: detailsCard()),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              savesCard(fillHeight: false),
              const Divider(height: 36),
              detailsCard(),
            ],
          ),
  );

  Widget savesCard({required bool fillHeight}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              '02  /  Сохранения',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          Text('${controller.saves.length}', style: TextStyle(color: accent)),
        ],
      ),
      const SizedBox(height: 18),
      if (controller.saves.isEmpty)
        (fillHeight ? Expanded(child: emptySaves()) : emptySaves())
      else if (fillHeight)
        Expanded(child: saveList(fillHeight: true))
      else
        saveList(fillHeight: false),
    ],
  );

  Widget emptySaves() => Padding(
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
  );

  Widget saveList({required bool fillHeight}) => ListView.separated(
    shrinkWrap: !fillHeight,
    physics: fillHeight ? null : const NeverScrollableScrollPhysics(),
    itemCount: controller.saves.length,
    separatorBuilder: (_, _) => const SizedBox(height: 6),
    itemBuilder: (context, index) {
      final save = controller.saves[index];
      final header = controller.saveHeaders[save.path];
      final headerText = header == null
          ? controller.unavailableHeaders.contains(save.path)
                ? 'Сведения недоступны'
                : 'Читаем сведения…'
          : '${header.date.year} · '
                '${_names.country(header.playerTag, ideology: header.ideology)} '
                '(${header.playerTag}) · ${_names.name(header.difficulty)} · '
                '${shortVersion(header.version)}';
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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(headerText, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('${size(save.size)} · ${date(save.modified)}'),
            ],
          ),
          isThreeLine: true,
          trailing: active ? const Icon(Icons.check_circle_outline) : null,
          onTap: () => controller.select(save),
        ),
      );
    },
  );

  String shortVersion(String version) =>
      RegExp(r'v\d+(?:\.\d+)+').firstMatch(version)?.group(0) ?? version;

  Widget detailsCard() {
    final save = controller.selected;
    final loaded = controller.loaded;
    final state = controller.worldState;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Предпросмотр',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Данные загружаются при выборе файла.',
          style: TextStyle(fontSize: 12, color: Color(0xFFA6B1A9)),
        ),
        const SizedBox(height: 22),
        if (save == null)
          const Text('Выберите сохранение в списке слева или выше.')
        else ...[
          Text(
            save.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: state == null || controller.previewLoading
                  ? null
                  : openSelectedWorld,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Использовать'),
            ),
          ),
          const SizedBox(height: 22),
          _stateLine('Размер', size(loaded?.bytesRead ?? save.size)),
          _stateLine(
            'Файл изменён',
            date(loaded?.file.modified ?? save.modified),
          ),
          if (controller.previewLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            const Text('Читаем сохранение…'),
          ],
          if (controller.error case final error?) ...[
            const SizedBox(height: 8),
            notice(error, Icons.error_outline, error: true),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.previewLoading
                  ? null
                  : controller.loadSelected,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
          if (state != null) ...[
            const Divider(height: 28),
            _stateLine(
              'Игровая дата',
              state.gameDate?.toString() ?? 'Неизвестно',
            ),
            _stateLine(
              'Страна игрока',
              '${_names.country(state.playerTag, ideology: state.ideology)} '
                  '(${state.playerTag ?? '—'})',
            ),
            _stateLine('Идеология', _names.name(state.ideology)),
            _stateLine('Сложность', _names.name(state.difficulty)),
            _stateLine('Версия игры', state.gameVersion ?? 'Неизвестно'),
          ],
        ],
      ],
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
