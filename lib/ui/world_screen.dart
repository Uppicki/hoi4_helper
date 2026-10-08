import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/game_localization.dart';
import '../core/telemetry_log.dart';
import '../core/telemetry_snapshot.dart';
import 'telemetry_details.dart';
import '../core/world_state.dart';

/// Main dashboard for a completed save or a limited telemetry observation.
class WorldScreen extends StatefulWidget {
  const WorldScreen({
    super.key,
    required this.snapshot,
    this.localizationRepository,
    this.language,
    this.onChangeSource,
    this.telemetryMode = false,
    this.telemetryManpower,
    this.telemetry,
    this.telemetryReceivedWhileOpen = false,
  });

  final WorldStateSnapshot snapshot;
  final GameLocalizationRepository? localizationRepository;
  final ValueNotifier<GameLanguage>? language;
  final VoidCallback? onChangeSource;
  final bool telemetryMode;
  final int? telemetryManpower;
  final TelemetryObservation? telemetry;
  final bool telemetryReceivedWhileOpen;

  @override
  State<WorldScreen> createState() => _WorldScreenState();
}

class _WorldScreenState extends State<WorldScreen> {
  GameLanguage _language = GameLanguage.russian;
  late Future<GameLocalization> _localization;
  bool _saveExpanded = false;
  double _swipeDistance = 0;

  GameLocalizationRepository get _repository =>
      widget.localizationRepository ?? GameLocalizationRepository.shared;

  @override
  void initState() {
    super.initState();
    _language = widget.language?.value ?? GameLanguage.russian;
    _localization = _repository.load(_language);
    widget.language?.addListener(_onLanguageChanged);
  }

  void _onLanguageChanged() {
    final next = widget.language?.value;
    if (next == null || next == _language) return;
    setState(() {
      _language = next;
      _localization = _repository.load(next);
    });
  }

  @override
  void dispose() {
    widget.language?.removeListener(_onLanguageChanged);
    super.dispose();
  }

  String _ui(String russian, String english) =>
      _language == GameLanguage.russian ? russian : english;

  @override
  Widget build(BuildContext context) => FutureBuilder<GameLocalization>(
    future: _localization,
    builder: (context, result) {
      final names = result.data?.language == _language
          ? result.data!
          : GameLocalization(_language, const {});
      return Scaffold(
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _swipeDistance = 0,
            onHorizontalDragUpdate: (details) =>
                _swipeDistance += details.primaryDelta ?? 0,
            onHorizontalDragEnd: (details) {
              if (_swipeDistance > 80 || (details.primaryVelocity ?? 0) > 350) {
                Navigator.of(context).maybePop();
              }
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1220),
                  child: LayoutBuilder(
                    builder: (context, bounds) => _dashboard(
                      context,
                      names,
                      bounds.maxWidth,
                      result.connectionState != ConnectionState.done,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _dashboard(
    BuildContext context,
    GameLocalization names,
    double width,
    bool loadingNames,
  ) {
    final world = widget.snapshot.world;
    final player = widget.telemetryMode
        ? telemetryDisplayCountry(widget.telemetry) ??
              (widget.snapshot.playerTag == null
                  ? null
                  : CountryWorldState(
                      tag: widget.snapshot.playerTag!,
                      availableManpower: widget.telemetryManpower,
                    ))
        : world?.playerCountry(widget.snapshot.playerTag);
    final twoColumns = width >= 760;
    final half = twoColumns ? (width - 16) / 2 : width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, names, width, player),
        if (loadingNames) ...[
          const SizedBox(height: 12),
          Text(
            _ui('Загружаем названия…', 'Loading names…'),
            style: const TextStyle(color: Color(0xFFAAB7AD), fontSize: 12),
          ),
        ],
        const SizedBox(height: 24),
        if (!widget.telemetryMode) ...[
          _worldSummary(world),
          const SizedBox(height: 24),
        ],
        Text(
          _ui('Состояние страны', 'Country dashboard'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(width: width, child: _armedForces(context, player)),
            SizedBox(width: half, child: _industry(context, player)),
            SizedBox(width: half, child: _resources(context, player)),
            SizedBox(width: half, child: _focuses(context, names, player)),
            SizedBox(width: half, child: _research(context, names, player)),
            SizedBox(width: half, child: _projects(context)),
            SizedBox(width: half, child: _map(context, names, world)),
          ],
        ),
        if (widget.telemetry case final observation?) ...[
          const SizedBox(height: 24),
          TelemetryDetails(
            observation: observation,
            names: names,
            language: _language,
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    GameLocalization names,
    double width,
    CountryWorldState? player,
  ) {
    final country = names.country(
      widget.snapshot.playerTag,
      ideology: widget.snapshot.ideology,
    );
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.telemetryMode
              ? _ui('НАБЛЮДЕНИЕ МОДА', 'MOD OBSERVATION')
              : _ui('СОСТОЯНИЕ МИРА', 'WORLD STATE'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(country, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 6),
        Text(
          '${widget.snapshot.playerTag ?? '—'}  ·  ${widget.snapshot.gameDate?.toString() ?? '—'}',
          style: const TextStyle(color: Color(0xFFAAB7AD), fontSize: 16),
        ),
        if (widget.telemetryMode) ...[
          const SizedBox(height: 8),
          Text(
            widget.telemetryReceivedWhileOpen
                ? _ui(
                    'Обновлено после открытия экрана. Данные поступают раз в игровой день.',
                    'Updated after this screen opened. Data arrives once per game day.',
                  )
                : _ui(
                    'Последняя запись журнала может относиться к прошлой загрузке.',
                    'The latest log line may belong to an earlier game load.',
                  ),
            style: const TextStyle(color: Color(0xFFAAB7AD), fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!widget.telemetryMode)
              _chip(Icons.flag_outlined, names.name(widget.snapshot.ideology)),
            if (!widget.telemetryMode)
              _chip(Icons.tune, names.name(widget.snapshot.difficulty)),
            if (widget.snapshot.gameVersion case final version?)
              _chip(Icons.extension_outlined, version),
            if (player?.major == true)
              _chip(Icons.star_border, _ui('Крупная держава', 'Major power')),
            if (player?.stability != null)
              _chip(
                Icons.balance_outlined,
                '${_ui('Стабильность', 'Stability')}: ${_percent(player!.stability)}',
              ),
            if (player?.warSupport != null)
              _chip(
                Icons.volunteer_activism_outlined,
                '${_ui('Поддержка войны', 'War support')}: ${_percent(player!.warSupport)}',
              ),
          ],
        ),
      ],
    );
    final tools = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, size: 18),
            const SizedBox(width: 8),
            DropdownButton<GameLanguage>(
              key: const Key('game-language'),
              value: _language,
              underline: const SizedBox.shrink(),
              items: [
                for (final language in GameLanguage.values)
                  DropdownMenuItem(
                    value: language,
                    child: Text(language.label),
                  ),
              ],
              onChanged: (language) {
                if (language == null || language == _language) return;
                if (widget.language case final shared?) {
                  shared.value = language;
                } else {
                  setState(() {
                    _language = language;
                    _localization = _repository.load(language);
                  });
                }
              },
            ),
          ],
        ),
        if (widget.telemetryMode) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('change-source-from-telemetry'),
            onPressed: widget.onChangeSource,
            icon: const Icon(Icons.swap_horiz),
            label: Text(_ui('Изменить источник', 'Change source')),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(width: math.min(width, 300), child: _saveMenu(context)),
      ],
    );
    if (width < 760) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          identity,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: tools),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: identity),
        const SizedBox(width: 16),
        tools,
      ],
    );
  }

  Widget _saveMenu(BuildContext context) {
    final save = widget.snapshot.loadedSave;
    final filename = widget.telemetryMode
        ? _ui('Телеметрия', 'Telemetry')
        : save?.file.name ?? widget.snapshot.sourceDescription;
    return Container(
      decoration: _decoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('save-summary'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _saveExpanded = !_saveExpanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    widget.telemetryMode
                        ? Icons.sensors_outlined
                        : Icons.save_outlined,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          widget.snapshot.gameDate?.toString() ?? '—',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFAAB7AD),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(_saveExpanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            child: _saveExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(),
                        _detail(
                          _ui('Источник', 'Source'),
                          widget.telemetryMode
                              ? _ui('Телеметрия', 'Telemetry')
                              : save == null
                              ? widget.snapshot.sourceDescription
                              : _ui('Файл сохранения', 'Save file'),
                        ),
                        if (!widget.telemetryMode)
                          _detail(
                            _ui('Размер', 'Size'),
                            save == null ? '—' : _size(save.bytesRead),
                          ),
                        if (!widget.telemetryMode)
                          _detail(
                            _ui('Изменён', 'Modified'),
                            save == null ? '—' : _date(save.file.modified),
                          ),
                        if (widget.telemetryMode)
                          _detail(
                            _ui('Путь журнала', 'Log path'),
                            widget.telemetry?.logSource ?? '—',
                          ),
                        _detail(
                          widget.telemetryMode
                              ? _ui('Получено приложением', 'Received by app')
                              : _ui('Прочитан', 'Read'),
                          widget.telemetryMode && widget.telemetry == null
                              ? '—'
                              : _date(widget.snapshot.readAt),
                        ),
                        if (widget.telemetryMode &&
                            widget.telemetry != null) ...[
                          _detail(
                            _ui('Дата и страна', 'Date and country'),
                            _ui(
                              'Игровая дата из префикса game.log; страна из [ROOT.GetTag].',
                              'Game date from the game.log prefix; country from [ROOT.GetTag].',
                            ),
                          ),
                          _detail(
                            _ui('Армейский резерв', 'Army manpower'),
                            _ui(
                              '[ROOT.GetManpower] в записи мода, человек.',
                              '[ROOT.GetManpower] in the mod record, people.',
                            ),
                          ),
                        ],
                        if (widget.telemetryMode) ...[
                          _detail(
                            _ui('Формат записи мода', 'Mod record format'),
                            widget.telemetry?.schemaVersion.toString() ?? '—',
                          ),
                          _detail(
                            _ui('Схема наблюдения', 'Observation schema'),
                            widget.telemetry?.observationSchemaVersion
                                    .toString() ??
                                '—',
                          ),
                        ],
                        if (widget.snapshot.world?.saveVersion
                            case final version?)
                          _detail(_ui('Формат', 'Format'), version.toString()),
                        if (!widget.telemetryMode)
                          _detail(
                            _ui('Схема снимка', 'Snapshot schema'),
                            SnapshotIdentity.schemaVersion.toString(),
                          ),
                        if (!widget.telemetryMode)
                          _detail(
                            _ui('ID сохранения', 'Save ID'),
                            widget.snapshot.identity?.saveId ??
                                _ui('Неизвестно', 'Unknown'),
                          ),
                        _detail(
                          _ui('Кампания', 'Campaign'),
                          widget.snapshot.identity?.campaignId ??
                              _ui('Не установлена', 'Unknown'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('change-source'),
                          onPressed:
                              widget.onChangeSource ??
                              () => Navigator.of(context).pushNamed('/source'),
                          icon: const Icon(Icons.swap_horiz),
                          label: Text(
                            _ui('Изменить источник', 'Change source'),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _worldSummary(SaveWorldDetails? world) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _chip(
        Icons.public,
        '${_ui('Стран', 'Countries')}: ${_number(world?.countries.length)}',
      ),
      _chip(
        Icons.map_outlined,
        '${_ui('Штатов', 'States')}: ${_number(world?.stateCount)}',
      ),
      _chip(
        Icons.layers_outlined,
        '${_ui('Провинций', 'Provinces')}: ${_number(world?.provinceCount)}',
      ),
      _chip(
        Icons.groups_outlined,
        '${_ui('Фракций', 'Factions')}: ${_number(world?.factionCount)}',
      ),
      if (world?.startDate != null)
        _chip(
          Icons.event_outlined,
          '${_ui('Начало кампании', 'Campaign start')}: ${world!.startDate}',
        ),
      if (world?.ironman != null)
        _chip(
          Icons.lock_outline,
          'Ironman: ${world!.ironman! ? _ui('да', 'yes') : _ui('нет', 'no')}',
        ),
    ],
  );

  Widget _armedForces(
    BuildContext context,
    CountryWorldState? country,
  ) => _panel(
    context,
    Icons.shield_outlined,
    _ui('Вооружённые силы', 'Armed forces'),
    LayoutBuilder(
      builder: (context, bounds) {
        final cell = bounds.maxWidth >= 650
            ? (bounds.maxWidth - 24) / 3
            : bounds.maxWidth >= 360
            ? (bounds.maxWidth - 12) / 2
            : bounds.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cell,
              child: _forceCard(
                Icons.military_tech_outlined,
                _ui('Армия', 'Army'),
                [
                  _pair(
                    _ui('Дивизии', 'Divisions'),
                    _number(country?.divisionCount),
                  ),
                  _pair(
                    _ui('Опыт армии', 'Army experience'),
                    _decimal(country?.armyExperience),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: cell,
              child: _forceCard(Icons.sailing_outlined, _ui('Флот', 'Navy'), [
                _pair(_ui('Флоты', 'Fleets'), _number(country?.fleetCount)),
                _pair(_ui('Корабли', 'Ships'), _number(country?.shipCount)),
                if (widget.telemetryMode)
                  _pair(
                    _ui('Опыт флота', 'Navy experience'),
                    _decimal(widget.telemetry?.value('navy_xp')),
                  ),
              ]),
            ),
            SizedBox(
              width: cell,
              child: _forceCard(
                Icons.flight_outlined,
                _ui('Авиация', 'Air force'),
                [
                  _pair(_ui('Авиакрылья', 'Air wings'), '—'),
                  if (widget.telemetryMode)
                    _pair(
                      _ui('Самолёты', 'Aircraft'),
                      _number(widget.telemetry?.count('planes')),
                    ),
                  _pair(
                    _ui('Опыт авиации', 'Air experience'),
                    _decimal(country?.airExperience),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _industry(BuildContext context, CountryWorldState? country) => _panel(
    context,
    Icons.factory_outlined,
    _ui('Промышленность', 'Industry'),
    Column(
      children: [
        _metricRow(
          _ui('Фабрики', 'Civilian factories'),
          _number(country?.civilianFactories),
        ),
        _metricRow(
          _ui('Военные заводы', 'Military factories'),
          _number(country?.militaryFactories),
        ),
        _metricRow(_ui('Верфи', 'Dockyards'), _number(country?.dockyards)),
        if (widget.telemetryMode) ...[
          const Divider(height: 20),
          _metricRow(
            _ui('Доступные фабрики', 'Available civilian factories'),
            _number(widget.telemetry?.count('available_civ')),
          ),
          _metricRow(
            _ui('Доступные военные заводы', 'Available military factories'),
            _number(widget.telemetry?.count('available_mil')),
          ),
          _metricRow(
            _ui('Доступные верфи', 'Available dockyards'),
            _number(widget.telemetry?.count('available_dock')),
          ),
        ],
        const Divider(height: 26),
        _metricRow(
          _ui('Военные линии', 'Military lines'),
          _number(country?.militaryProductionLines),
        ),
        _metricRow(
          _ui('Морские линии', 'Naval lines'),
          _number(country?.navalProductionLines),
        ),
      ],
    ),
  );

  Widget _resources(BuildContext context, CountryWorldState? country) => _panel(
    context,
    Icons.inventory_2_outlined,
    _ui('Ресурсы', 'Resources'),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.telemetryMode)
          _metricRow(
            _ui('Армейский резерв', 'Army manpower'),
            _number(country?.availableManpower),
          ),
        _metricRow(
          _ui('Людская сила в штатах', 'Manpower in states'),
          _number(country?.stateAvailableManpower),
        ),
        _metricRow(
          _ui('Политическая власть', 'Political power'),
          _decimal(country?.politicalPower),
        ),
        _metricRow(
          _ui('Командный ресурс', 'Command power'),
          _decimal(country?.commandPower),
        ),
        if (widget.telemetryMode)
          _metricRow(
            _ui('Топливо, тыс.', 'Fuel, thousands'),
            _decimal(widget.telemetry?.value('fuel')),
          ),
        const SizedBox(height: 10),
        Text(
          widget.telemetryMode
              ? _ui(
                  widget.telemetry?.schemaVersion == 2
                      ? 'Баланс сырья, запасы и потребности снаряжения показаны ниже.'
                      : 'Остальные ресурсы мод пока не передаёт.',
                  widget.telemetry?.schemaVersion == 2
                      ? 'Resource balance and equipment stockpiles are shown below.'
                      : 'The mod does not report the other resources yet.',
                )
              : _ui(
                  'Сырьевые ресурсы и армейский резерв пока не вычисляются из сейва и игровых данных.',
                  'Raw resources and army reserve are not calculated from the save and game data yet.',
                ),
          style: const TextStyle(color: Color(0xFFAAB7AD), fontSize: 12),
        ),
      ],
    ),
  );

  Widget _focuses(
    BuildContext context,
    GameLocalization names,
    CountryWorldState? country,
  ) => _panel(
    context,
    Icons.account_tree_outlined,
    _ui('Национальные фокусы', 'National focuses'),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detail(
          _ui('Текущий фокус', 'Current focus'),
          names.name(country?.currentFocus),
        ),
        _detail(_ui('Дерево', 'Tree'), names.name(country?.focusTree)),
        const SizedBox(height: 8),
        _codeList(
          _ui('Завершённые', 'Completed'),
          country?.completedFocuses ?? const [],
          names,
        ),
      ],
    ),
  );

  Widget _research(
    BuildContext context,
    GameLocalization names,
    CountryWorldState? country,
  ) => _panel(
    context,
    Icons.science_outlined,
    _ui('Исследования', 'Research'),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metricRow(
          _ui('Ячейки исследований', 'Research slots'),
          _number(country?.researchSlots),
        ),
        if (widget.telemetryMode)
          _metricRow(
            _ui('Изучено технологий', 'Researched technologies'),
            _number(widget.telemetry?.count('researched_count')),
          ),
        const SizedBox(height: 6),
        _codeList(
          _ui('Активные', 'Active'),
          country?.activeResearch ?? const [],
          names,
        ),
        const SizedBox(height: 10),
        _codeList(
          _ui('Изученные технологии', 'Researched technologies'),
          country?.researchedTechnologies ?? const [],
          names,
        ),
      ],
    ),
  );

  Widget _projects(BuildContext context) => _panel(
    context,
    Icons.bolt_outlined,
    _ui('Специальные проекты', 'Special projects'),
    Text(
      _ui(
        widget.telemetryMode
            ? 'Данные о специальных проектах мод пока не передаёт.'
            : 'Данные о специальных проектах пока не извлекаются из сохранения.',
        widget.telemetryMode
            ? 'The mod does not report special project data yet.'
            : 'Special project data is not extracted from the save yet.',
      ),
      style: const TextStyle(color: Color(0xFFAAB7AD)),
    ),
  );

  Widget _map(
    BuildContext context,
    GameLocalization names,
    SaveWorldDetails? world,
  ) {
    final playerTag = widget.snapshot.playerTag;
    final capital = world?.playerCountry(playerTag)?.capitalStateId;
    final states =
        world?.states.values.where((state) => state.owner == playerTag).toList()
          ?..sort((a, b) => a.id.compareTo(b.id));
    final countries = world?.countries.keys.toList()?..sort();
    return _panel(
      context,
      Icons.map_outlined,
      _ui('Карта и штаты', 'Map and states'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metricRow(
            _ui('Штаты страны', 'Owned states'),
            _number(
              widget.telemetryMode
                  ? widget.telemetry?.count('owned_states')
                  : world?.ownedStateCounts[playerTag],
            ),
          ),
          _metricRow(
            _ui('Столица', 'Capital'),
            capital == null ? '—' : names.state(capital),
          ),
          if (states != null && states.isNotEmpty)
            ExpansionTile(
              title: Text('${_ui('Штаты', 'States')} (${states.length})'),
              tilePadding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height: 260,
                  child: ListView.builder(
                    itemCount: states.length,
                    itemBuilder: (context, index) {
                      final state = states[index];
                      final buildings = state.buildings.entries
                          .map(
                            (item) => '${names.name(item.key)} ${item.value}',
                          )
                          .join(' · ');
                      return ListTile(
                        dense: true,
                        title: Text(names.state(state.id)),
                        subtitle: Text(
                          '${_ui('Людская сила', 'Manpower')}: ${_number(state.availableManpower)}'
                          '${buildings.isEmpty ? '' : ' · $buildings'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          if (countries != null && countries.isNotEmpty)
            ExpansionTile(
              title: Text(
                '${_ui('Страны', 'Countries')} (${countries.length})',
              ),
              tilePadding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height: 260,
                  child: ListView.builder(
                    itemCount: countries.length,
                    itemBuilder: (context, index) {
                      final tag = countries[index];
                      return ListTile(
                        dense: true,
                        title: Text('${names.name(tag)} · $tag'),
                        trailing: Text(_number(world?.ownedStateCounts[tag])),
                      );
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _panel(
    BuildContext context,
    IconData icon,
    String title,
    Widget child,
  ) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: _decoration(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );

  BoxDecoration _decoration(BuildContext context) => BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    border: Border.all(color: const Color(0xFF35433A)),
    borderRadius: BorderRadius.circular(16),
  );

  Widget _forceCard(IconData icon, String title, List<Widget> facts) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF222D27),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...facts,
          ],
        ),
      );

  Widget _pair(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFFAAB7AD)),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _metricRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFFAAB7AD))),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFFAAB7AD)),
        ),
        const SizedBox(height: 2),
        Tooltip(
          message: value,
          child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );

  Widget _codeList(String title, List<String> codes, GameLocalization names) {
    if (codes.isEmpty) return _detail(title, '—');
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('$title (${codes.length})'),
      children: [
        SizedBox(
          height: math.min(250, codes.length * 44).toDouble(),
          child: ListView.builder(
            itemCount: codes.length,
            itemBuilder: (context, index) => ListTile(
              dense: true,
              title: Text(
                names.name(codes[index]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: names.name(codes[index]) == codes[index]
                  ? null
                  : Text(codes[index], maxLines: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF27332B),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFFD7B979)),
        const SizedBox(width: 7),
        Text(label),
      ],
    ),
  );

  String _number(int? value) => value == null
      ? '—'
      : value.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ' ',
        );
  String _decimal(double? value) => value?.toStringAsFixed(1) ?? '—';
  String _percent(double? value) =>
      value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';

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
