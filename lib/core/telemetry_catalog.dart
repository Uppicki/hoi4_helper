/// Read-only country values. The exporter checks against installed game docs.
enum TelemetryFormat { count, decimal, percent }

/// Accepted values after parsing the mod's localized numeric output.
/// Bounds are only used where the field's meaning or game docs establish them.
enum TelemetryDomain {
  finite(
    'Конечное число; границы не подтверждены',
    'Finite number; bounds unverified',
  ),
  nonNegativeFinite('Конечное число от 0', 'Finite number from 0'),
  signedInteger(
    'Целое число, возможно отрицательное',
    'Integer, possibly negative',
  ),
  nonNegativeInteger('Целое число от 0', 'Integer from 0'),
  fraction('Доля от 0 до 1', 'Fraction from 0 to 1');

  const TelemetryDomain(this.descriptionRu, this.descriptionEn);

  final String descriptionRu;
  final String descriptionEn;

  bool accepts(double value) {
    if (!value.isFinite) return false;
    return switch (this) {
      TelemetryDomain.finite => true,
      TelemetryDomain.nonNegativeFinite => value >= 0,
      TelemetryDomain.signedInteger => value == value.truncateToDouble(),
      TelemetryDomain.nonNegativeInteger =>
        value >= 0 && value == value.truncateToDouble(),
      TelemetryDomain.fraction => value >= 0 && value <= 1,
    };
  }
}

enum TelemetryUnit {
  points('очков', 'points'),
  pointsPerDay('очков/день', 'points/day'),
  percent('%', '%'),
  people('человек', 'people'),
  thousandPeople('тыс. человек', 'thousand people'),
  divisions('дивизий', 'divisions'),
  battalions('батальонов', 'battalions'),
  ships('кораблей', 'ships'),
  aircraft('самолётов', 'aircraft'),
  factories('заводов', 'factories'),
  thousandFuel('тыс. ед. топлива', 'thousand fuel units'),
  researchSlots('ячеек', 'slots'),
  technologies('технологий', 'technologies'),
  levels('уровней', 'levels'),
  states('штатов', 'states'),
  supplyNodes('узлов', 'supply nodes'),
  countries('стран', 'countries'),
  upgrades('улучшений', 'upgrades'),
  operatives('оперативников', 'operatives'),
  strength('ед. силы', 'strength units'),
  resources('ед. ресурса', 'resource units'),
  equipment('ед. снаряжения', 'equipment units'),
  buildings('построек', 'buildings');

  const TelemetryUnit(this.ru, this.en);

  final String ru;
  final String en;
}

class TelemetryMetric {
  const TelemetryMetric(
    this.key,
    this.variable,
    this.ru,
    this.en,
    this.group, {
    this.format = TelemetryFormat.count,
    this.scale = 1,
  });
  final String key, variable, ru, en, group;
  final TelemetryFormat format;
  final double scale;

  String get unitRu => unit.ru;
  String get unitEn => unit.en;

  /// The game variable used by set_temp_variable in the generated player mod.
  String get sourceRu => 'Динамическая переменная страны: $variable';
  String get sourceEn => 'Country dynamic variable: $variable';

  TelemetryUnit get unit => switch (group) {
    'politics' => switch (key) {
      'political_power' || 'command_power' => TelemetryUnit.points,
      'political_power_daily' ||
      'command_power_daily' => TelemetryUnit.pointsPerDay,
      'stability' ||
      'war_support' ||
      'surrender_progress' ||
      'party_democratic' ||
      'party_fascism' ||
      'party_communism' ||
      'party_neutrality' => TelemetryUnit.percent,
      _ => throw StateError('No telemetry unit for $key'),
    },
    'manpower' => switch (key) {
      'manpower' ||
      'training_manpower' ||
      'garrison_need' => TelemetryUnit.people,
      'deployed_army' ||
      'deployed_navy' ||
      'deployed_air' ||
      'deployed_total' ||
      'casualties' ||
      'max_manpower' => TelemetryUnit.thousandPeople,
      _ => throw StateError('No telemetry unit for $key'),
    },
    'army' => switch (key) {
      'divisions' => TelemetryUnit.divisions,
      'battalions' => TelemetryUnit.battalions,
      'ships' => TelemetryUnit.ships,
      'planes' => TelemetryUnit.aircraft,
      'army_xp' || 'navy_xp' || 'air_xp' => TelemetryUnit.points,
      _ => throw StateError('No telemetry unit for $key'),
    },
    'industry' => switch (key) {
      'energy_ratio' => TelemetryUnit.percent,
      'civilian_factories' ||
      'military_factories' ||
      'dockyards' ||
      'available_civ' ||
      'available_mil' ||
      'available_dock' ||
      'project_civ' ||
      'controlled_factories' ||
      'owned_factories' => TelemetryUnit.factories,
      _ => throw StateError('No telemetry unit for $key'),
    },
    'fuel' => switch (key) {
      'fuel_ratio' => TelemetryUnit.percent,
      'fuel' || 'max_fuel' => TelemetryUnit.thousandFuel,
      _ => throw StateError('No telemetry unit for $key'),
    },
    'research' => switch (key) {
      'research_slots' => TelemetryUnit.researchSlots,
      'researched_count' => TelemetryUnit.technologies,
      'land_doctrine' => TelemetryUnit.levels,
      _ => throw StateError('No telemetry unit for $key'),
    },
    'territory' => switch (key) {
      'owned_states' ||
      'controlled_states' ||
      'core_states' ||
      'occupied_states' => TelemetryUnit.states,
      'supply_nodes' => TelemetryUnit.supplyNodes,
      'subjects' || 'faction_members' => TelemetryUnit.countries,
      _ => throw StateError('No telemetry unit for $key'),
    },
    'intelligence' => switch (key) {
      'agency_upgrades' => TelemetryUnit.upgrades,
      'operatives' ||
      'operative_slots' ||
      'free_operative_slots' => TelemetryUnit.operatives,
      'encryption' => TelemetryUnit.strength,
      _ => throw StateError('No telemetry unit for $key'),
    },
    'resources' => TelemetryUnit.resources,
    'equipment' || 'production' => TelemetryUnit.equipment,
    'construction' => TelemetryUnit.buildings,
    _ => throw StateError('No telemetry unit for $key'),
  };

  TelemetryDomain get domain => switch (group) {
    'politics' => switch (key) {
      'war_support' ||
      'party_democratic' ||
      'party_fascism' ||
      'party_communism' ||
      'party_neutrality' => TelemetryDomain.fraction,
      'political_power' ||
      'political_power_daily' ||
      'command_power' ||
      'command_power_daily' ||
      'stability' ||
      'surrender_progress' => TelemetryDomain.finite,
      _ => throw StateError('No telemetry domain for $key'),
    },
    'manpower' => switch (key) {
      'deployed_army' ||
      'deployed_navy' ||
      'deployed_air' ||
      'deployed_total' ||
      'casualties' ||
      'max_manpower' => TelemetryDomain.nonNegativeFinite,
      'manpower' ||
      'training_manpower' ||
      'garrison_need' => TelemetryDomain.nonNegativeInteger,
      _ => throw StateError('No telemetry domain for $key'),
    },
    'army' => switch (key) {
      'army_xp' || 'navy_xp' || 'air_xp' => TelemetryDomain.nonNegativeFinite,
      'divisions' ||
      'battalions' ||
      'ships' ||
      'planes' => TelemetryDomain.nonNegativeInteger,
      _ => throw StateError('No telemetry domain for $key'),
    },
    'industry' => switch (key) {
      'energy_ratio' => TelemetryDomain.fraction,
      'civilian_factories' ||
      'military_factories' ||
      'dockyards' ||
      'available_civ' ||
      'available_mil' ||
      'available_dock' ||
      'project_civ' ||
      'controlled_factories' ||
      'owned_factories' => TelemetryDomain.nonNegativeInteger,
      _ => throw StateError('No telemetry domain for $key'),
    },
    'fuel' => switch (key) {
      'fuel_ratio' => TelemetryDomain.finite,
      'fuel' || 'max_fuel' => TelemetryDomain.nonNegativeFinite,
      _ => throw StateError('No telemetry domain for $key'),
    },
    'research' => switch (key) {
      'research_slots' ||
      'researched_count' ||
      'land_doctrine' => TelemetryDomain.nonNegativeInteger,
      _ => throw StateError('No telemetry domain for $key'),
    },
    'territory' => switch (key) {
      'owned_states' ||
      'controlled_states' ||
      'core_states' ||
      'occupied_states' ||
      'supply_nodes' ||
      'subjects' ||
      'faction_members' => TelemetryDomain.nonNegativeInteger,
      _ => throw StateError('No telemetry domain for $key'),
    },
    'intelligence' => switch (key) {
      'encryption' => TelemetryDomain.finite,
      'agency_upgrades' ||
      'operatives' ||
      'operative_slots' ||
      'free_operative_slots' => TelemetryDomain.nonNegativeInteger,
      _ => throw StateError('No telemetry domain for $key'),
    },
    'resources' =>
      key.endsWith('_balance')
          ? TelemetryDomain.signedInteger
          : TelemetryDomain.nonNegativeInteger,
    'equipment' ||
    'construction' ||
    'production' => TelemetryDomain.nonNegativeInteger,
    _ => throw StateError('No telemetry domain for $key'),
  };
}

final telemetryScalars = <TelemetryMetric>[
  TelemetryMetric(
    'political_power',
    'political_power',
    'Политическая власть',
    'Political power',
    'politics',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'political_power_daily',
    'political_power_daily',
    'Политическая власть / день',
    'Political power / day',
    'politics',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'command_power',
    'command_power',
    'Командный ресурс',
    'Command power',
    'politics',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'command_power_daily',
    'command_power_daily',
    'Командный ресурс / день',
    'Command power / day',
    'politics',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'stability',
    'stability',
    'Стабильность',
    'Stability',
    'politics',
    format: TelemetryFormat.percent,
  ),
  TelemetryMetric(
    'war_support',
    'has_war_support',
    'Поддержка войны',
    'War support',
    'politics',
    format: TelemetryFormat.percent,
  ),
  TelemetryMetric(
    'surrender_progress',
    'surrender_progress',
    'Прогресс капитуляции',
    'Surrender progress',
    'politics',
    format: TelemetryFormat.percent,
  ),
  TelemetryMetric(
    'party_democratic',
    'party_popularity@democratic',
    'Демократия',
    'Democracy',
    'politics',
    format: TelemetryFormat.percent,
  ),
  TelemetryMetric(
    'party_fascism',
    'party_popularity@fascism',
    'Фашизм',
    'Fascism',
    'politics',
    format: TelemetryFormat.percent,
  ),
  TelemetryMetric(
    'party_communism',
    'party_popularity@communism',
    'Коммунизм',
    'Communism',
    'politics',
    format: TelemetryFormat.percent,
  ),
  TelemetryMetric(
    'party_neutrality',
    'party_popularity@neutrality',
    'Нейтралитет',
    'Non-aligned',
    'politics',
    format: TelemetryFormat.percent,
  ),
  TelemetryMetric(
    'manpower',
    'manpower',
    'Армейский резерв',
    'Army manpower',
    'manpower',
  ),
  TelemetryMetric(
    'deployed_army',
    'deployed_army_manpower_k',
    'Личный состав армии, тыс.',
    'Army personnel, thousands',
    'manpower',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'deployed_navy',
    'deployed_navy_manpower_k',
    'Личный состав флота, тыс.',
    'Navy personnel, thousands',
    'manpower',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'deployed_air',
    'deployed_airforce_manpower_k',
    'Личный состав авиации, тыс.',
    'Air force personnel, thousands',
    'manpower',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'deployed_total',
    'deployed_total_manpower_k',
    'Всего развёрнуто, тыс.',
    'Total deployed, thousands',
    'manpower',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'training_manpower',
    'amount_manpower_in_deployment_queue',
    'Людей в очереди развёртывания',
    'Deployment queue manpower',
    'manpower',
  ),
  TelemetryMetric(
    'garrison_need',
    'garrison_manpower_need',
    'Потребность гарнизонов',
    'Garrison manpower need',
    'manpower',
  ),
  TelemetryMetric(
    'casualties',
    'casualties_k',
    'Потери во всех войнах, тыс.',
    'Casualties, thousands',
    'manpower',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'max_manpower',
    'max_manpower_k',
    'Общий людской потенциал, тыс.',
    'Total manpower potential, thousands',
    'manpower',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'divisions',
    'num_divisions',
    'Дивизии под контролем',
    'Controlled divisions',
    'army',
  ),
  TelemetryMetric(
    'battalions',
    'num_battalions',
    'Батальоны',
    'Battalions',
    'army',
  ),
  TelemetryMetric('ships', 'num_ships', 'Корабли', 'Ships', 'army'),
  TelemetryMetric(
    'planes',
    'num_deployed_planes',
    'Развёрнутые самолёты',
    'Deployed aircraft',
    'army',
  ),
  TelemetryMetric(
    'army_xp',
    'army_experience',
    'Опыт армии',
    'Army experience',
    'army',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'navy_xp',
    'navy_experience',
    'Опыт флота',
    'Navy experience',
    'army',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'air_xp',
    'air_experience',
    'Опыт авиации',
    'Air experience',
    'army',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'civilian_factories',
    'num_of_civilian_factories',
    'Фабрики',
    'Civilian factories',
    'industry',
  ),
  TelemetryMetric(
    'military_factories',
    'num_of_military_factories',
    'Военные заводы',
    'Military factories',
    'industry',
  ),
  TelemetryMetric(
    'dockyards',
    'num_of_naval_factories',
    'Верфи',
    'Dockyards',
    'industry',
  ),
  TelemetryMetric(
    'available_civ',
    'num_of_available_civilian_factories',
    'Доступные фабрики',
    'Available civilian factories',
    'industry',
  ),
  TelemetryMetric(
    'available_mil',
    'num_of_available_military_factories',
    'Доступные военные заводы',
    'Available military factories',
    'industry',
  ),
  TelemetryMetric(
    'available_dock',
    'num_of_available_naval_factories',
    'Доступные верфи',
    'Available dockyards',
    'industry',
  ),
  TelemetryMetric(
    'project_civ',
    'num_of_civilian_factories_available_for_projects',
    'Фабрики для нового проекта',
    'Factories available for a new project',
    'industry',
  ),
  TelemetryMetric(
    'controlled_factories',
    'num_of_controlled_factories',
    'Заводы в контролируемых штатах',
    'Factories in controlled states',
    'industry',
  ),
  TelemetryMetric(
    'owned_factories',
    'num_of_owned_factories',
    'Заводы в собственных штатах',
    'Factories in owned states',
    'industry',
  ),
  TelemetryMetric(
    'energy_ratio',
    'energy_ratio',
    'Обеспечение энергией',
    'Energy fulfilment',
    'industry',
    format: TelemetryFormat.percent,
  ),
  TelemetryMetric(
    'fuel',
    'fuel_k',
    'Топливо, тыс.',
    'Fuel, thousands',
    'fuel',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'max_fuel',
    'max_fuel_k',
    'Ёмкость хранилищ, тыс.',
    'Fuel capacity, thousands',
    'fuel',
    format: TelemetryFormat.decimal,
  ),
  TelemetryMetric(
    'fuel_ratio',
    'fuel_ratio',
    'Заполнение хранилищ',
    'Fuel storage fill',
    'fuel',
    format: TelemetryFormat.percent,
  ),
  TelemetryMetric(
    'research_slots',
    'amount_research_slots',
    'Ячейки исследований',
    'Research slots',
    'research',
  ),
  TelemetryMetric(
    'researched_count',
    'num_researched_technologies',
    'Изучено технологий',
    'Researched technology count',
    'research',
  ),
  TelemetryMetric(
    'land_doctrine',
    'land_doctrine_level',
    'Уровень сухопутной доктрины',
    'Land doctrine level',
    'research',
  ),
  TelemetryMetric(
    'owned_states',
    'num_owned_states',
    'Собственные штаты',
    'Owned states',
    'territory',
  ),
  TelemetryMetric(
    'controlled_states',
    'num_controlled_states',
    'Контролируемые штаты',
    'Controlled states',
    'territory',
  ),
  TelemetryMetric(
    'core_states',
    'num_core_states',
    'Национальные штаты',
    'Core states',
    'territory',
  ),
  TelemetryMetric(
    'occupied_states',
    'num_occupied_states',
    'Оккупированные штаты',
    'Occupied states',
    'territory',
  ),
  TelemetryMetric(
    'supply_nodes',
    'num_of_supply_nodes',
    'Узлы снабжения',
    'Supply hubs',
    'territory',
  ),
  TelemetryMetric(
    'subjects',
    'num_subjects',
    'Подчинённые страны',
    'Subjects',
    'territory',
  ),
  TelemetryMetric(
    'faction_members',
    'num_faction_members',
    'Участники альянса',
    'Faction members',
    'territory',
  ),
  TelemetryMetric(
    'agency_upgrades',
    'agency_upgrade_number',
    'Улучшения агентства',
    'Agency upgrades',
    'intelligence',
  ),
  TelemetryMetric(
    'operatives',
    'num_of_operatives',
    'Оперативники',
    'Operatives',
    'intelligence',
  ),
  TelemetryMetric(
    'operative_slots',
    'num_operative_slots',
    'Ячейки оперативников',
    'Operative slots',
    'intelligence',
  ),
  TelemetryMetric(
    'free_operative_slots',
    'num_free_operative_slots',
    'Свободные ячейки оперативников',
    'Free operative slots',
    'intelligence',
  ),
  TelemetryMetric(
    'encryption',
    'encryption_strength',
    'Сила шифрования',
    'Encryption strength',
    'intelligence',
    format: TelemetryFormat.decimal,
  ),
];

const telemetryResources = [
  'oil',
  'aluminium',
  'rubber',
  'tungsten',
  'steel',
  'chromium',
  'coal',
];
const telemetryResourceColumns = {
  'balance': 'resource',
  'produced': 'resource_produced',
  'consumed': 'resource_consumed',
  'imported': 'resource_imported',
  'exported': 'resource_exported',
};
const telemetryEquipment = [
  'infantry_equipment',
  'support_equipment',
  'artillery_equipment',
  'rocket_artillery_equipment',
  'anti_tank_equipment',
  'anti_air_equipment',
  'motorized_equipment',
  'motorized_rocket_equipment',
  'mechanized_equipment',
  'amphibious_mechanized_equipment',
  'armored_car_equipment',
  'light_tank_chassis',
  'medium_tank_chassis',
  'heavy_tank_chassis',
  'super_heavy_tank_chassis',
  'modern_tank_chassis',
  'amphibious_tank_chassis',
  'small_plane_airframe',
  'medium_plane_airframe',
  'large_plane_airframe',
  'cv_small_plane_airframe',
  'small_plane_cas_airframe',
  'small_plane_naval_bomber_airframe',
  'cv_small_plane_cas_airframe',
  'cv_small_plane_naval_bomber_airframe',
  'transport_plane_equipment',
  'train_equipment',
  'railway_gun_equipment',
  'convoy',
  'floating_harbor_equipment',
];
const telemetryEquipmentColumns = {
  'stock': 'num_equipment',
  'field': 'num_equipment_in_armies',
  'need': 'num_target_equipment_in_armies',
};
const telemetryConstruction = [
  'civilian_factory',
  'military_factory',
  'dockyard',
  'infrastructure',
  'refinery',
  'fuel_silo',
  'air_base',
  'anti_air',
  'land_fort',
  'naval_fort',
  'port',
  'radar',
  'supply_node',
  'nuclear_reactor',
  'rocket_site',
];
const telemetryProduction = [
  'infantry',
  'support',
  'artillery',
  'anti_air',
  'anti_tank',
  'armor',
  'motorized',
  'mechanized',
  'amphibious',
  'fighter',
  'cas',
  'naval_bomber',
  'tactical_bomber',
  'strategic_bomber',
  'heavy_fighter',
  'air_transport',
  'scout_plane',
  'carrier',
  'capital_ship',
  'screen_ship',
  'submarine',
  'convoy',
  'train',
  'railway_gun',
  'floating_harbor',
  'missile',
];

final telemetryMetrics = <String, TelemetryMetric>{
  for (final metric in telemetryScalars) metric.key: metric,
  for (final resource in telemetryResources)
    for (final column in telemetryResourceColumns.entries)
      'res_${resource}_${column.key}': TelemetryMetric(
        'res_${resource}_${column.key}',
        '${column.value}@$resource',
        resource,
        resource,
        'resources',
      ),
  for (final equipment in telemetryEquipment)
    for (final column in telemetryEquipmentColumns.entries)
      'eq_${equipment}_${column.key}': TelemetryMetric(
        'eq_${equipment}_${column.key}',
        '${column.value}@$equipment',
        equipment,
        equipment,
        'equipment',
      ),
  for (final type in telemetryConstruction)
    'built_$type': TelemetryMetric(
      'built_$type',
      'total_constructed_$type',
      type,
      type,
      'construction',
    ),
  for (final type in telemetryProduction)
    'produced_$type': TelemetryMetric(
      'produced_$type',
      'total_equipment_produced_$type',
      type,
      type,
      'production',
    ),
};
