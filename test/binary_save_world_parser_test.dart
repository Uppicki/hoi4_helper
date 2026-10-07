import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/binary_save_world_parser.dart';
import 'package:hoi4_helper/core/save_repository.dart';

import 'support/binary_save_fixture.dart';

void main() {
  test('Extracts distinct world and country facts from nested save tokens', () {
    final fixture = BinarySaveFixture();
    fixture.fieldInt32(0x349D, 31); // save_version
    fixture.fieldInt32(0x28E0, 60759374); // start_date
    fixture.fieldBool(0x2D13, true); // ironman
    fixture.object(0x2A7D, (_) {}); // faction
    fixture.object(0x2A7D, (_) {});
    fixture.object(0x2830, (world) {
      world.intKeyObject(1, (_) {});
      world.intKeyObject(2, (_) {});
      world.intKeyObject(1, (_) {}); // Duplicate ID is one province.
    });
    fixture.object(0x2E3B, (world) {
      world.intKeyObject(1, (state) {
        state.fieldString(0x283E, 'GER');
        state.object(0x3635, (pool) {
          pool.fieldInt32(0x2FE8, 100);
          pool.fieldInt32(0x2DE4, 20);
          pool.fieldInt32(0x2A12, 120);
        });
        state.object(0x2F59, (buildings) {
          buildings.unquotedKeyObject('industrial_complex', (factory) {
            factory.fieldInt32(0x286C, 2);
          });
          buildings.unquotedKeyObject('arms_factory', (factory) {
            factory.fieldInt32(0x286C, 1);
          });
          buildings.object(0x4BF6, (dockyard) {
            dockyard.fieldInt32(0x286C, 1);
          });
        });
      });
      world.intKeyObject(2, (state) {
        state.fieldString(0x283E, 'FRA');
        state.object(0x3635, (pool) => pool.fieldInt32(0x2FE8, 200));
        state.object(0x2F59, (buildings) {
          buildings.unquotedKeyObject('industrial_complex', (factory) {
            factory.fieldInt32(0x286C, 3);
          });
        });
      });
      world.intKeyObject(3, (state) {
        state.fieldString(0x283E, 'GER');
        state.object(0x3635, (pool) => pool.fieldInt32(0x2FE8, 300));
        state.object(0x2F59, (buildings) {
          buildings.unquotedKeyObject('industrial_complex', (factory) {
            factory.fieldInt32(0x286C, 1);
          });
          buildings.unquotedKeyObject('arms_factory', (factory) {
            factory.fieldInt32(0x286C, 2);
          });
        });
      });
      world.intKeyObject(3, (state) {
        state.fieldString(0x283E, 'FRA');
        state.object(0x3635, (pool) => pool.fieldInt32(0x2FE8, 400));
        state.object(0x2F59, (buildings) {
          buildings.unquotedKeyObject('industrial_complex', (factory) {
            factory.fieldInt32(0x286C, 1);
          });
          buildings.unquotedKeyObject('arms_factory', (factory) {
            factory.fieldInt32(0x286C, 2);
          });
        });
      });
    });
    fixture.object(0x2D49, (world) {
      world.stringKeyObject('GER', (country) {
        country.fieldInt32(0x284B, 64); // capital
        country.fieldBool(0x2BE9, true); // major
        country.fieldFixed(0x2883, 0.70); // stability
        country.fieldFixed(0x37FD, 0.30); // war_support
        country.fieldInt32(0x2F71, 3); // research_slot
        country.fieldInt32(0x2F71, 4); // Last scalar wins.
        country.fieldInt32(0x35BF, 12); // num_ships
        country.fieldString(0x33B8, 'GER_focus'); // focus_tree
        country.object(0x2FFA, (politics) {
          politics.fieldFixed(0x301E, 120.25); // political_power
        });
        country.object(0x2FAA, (units) {
          units.object(0x01D7, (_) {}); // division
          units.object(0x01D7, (_) {});
          units.object(0x3B34, (_) {}); // fleet
        });
        country.object(0x2FB4, (production) {
          production.object(0x2FB0, (_) {}); // military_lines
          production.object(0x2FB0, (_) {});
          production.object(0x2FB1, (_) {}); // naval_lines
        });
        country.object(0x33B7, (focus) {
          focus.fieldString(0x2B75, 'GER_four_year_plan');
          focus.fieldString(0x3127, 'GER_rhineland');
          focus.fieldString(0x3127, 'GER_autarky');
        });
        country.object(0x285F, (technology) {
          technology.object(0x2E5D, (researched) {
            researched.stringKeyObject('infantry_weapons', (_) {});
            researched.stringKeyObject(
              'electronic_mechanical_engineering',
              (_) {},
            );
          });
          technology.object(0x2E67, (active) {
            active.stringKeyObject('basic_machine_tools', (_) {});
          });
        });
        country.object(0x7FFE, (unknown) {
          unknown.fieldFixed(0x2883, 0.01);
          unknown.fieldInt32(0x2F71, 99);
        });
      });
      world.stringKeyObject('FRA', (country) {
        country.fieldInt32(0x284B, 16);
        country.fieldFixed(0x37FD, 0.0);
      });
      world.stringKeyObject('GER', (country) {
        country.fieldInt32(0x284B, 65); // Reopened tag updates one field.
      });
    });

    final details = BinarySaveWorldParser.parse(
      Uint8List.fromList(fixture.build()),
    );

    expect(details.saveVersion, 31);
    expect(details.startDate.toString(), '1936.01.01 15:00');
    expect(details.ironman, isTrue);
    expect(details.factionCount, 2);
    expect(details.provinceCount, 2);
    expect(details.stateCount, 3);
    expect(details.ownedStateCounts, {'GER': 1, 'FRA': 2});
    expect(details.countries, hasLength(2));
    expect(details.countries.keys, containsAll(['GER', 'FRA']));
    final ger = details.countries['GER']!;
    expect(ger.capitalStateId, 65);
    expect(ger.major, isTrue);
    expect(ger.stability, closeTo(0.70, 0.00001));
    expect(ger.warSupport, closeTo(0.30, 0.00001));
    expect(ger.researchSlots, 4);
    expect(ger.civilianFactories, 2);
    expect(ger.militaryFactories, 1);
    expect(ger.dockyards, 1);
    expect(ger.stateAvailableManpower, 100);
    expect(details.states[1]?.lockedManpower, 20);
    expect(details.states[1]?.totalManpower, 120);
    expect(details.states[3]?.owner, 'FRA');
    expect(ger.shipCount, 12);
    expect(ger.focusTree, 'GER_focus');
    expect(ger.politicalPower, closeTo(120.25, 0.00001));
    expect(ger.divisionCount, 2);
    expect(ger.fleetCount, 1);
    expect(ger.militaryProductionLines, 2);
    expect(ger.navalProductionLines, 1);
    expect(ger.currentFocus, 'GER_four_year_plan');
    expect(ger.completedFocuses, ['GER_rhineland', 'GER_autarky']);
    expect(ger.researchedTechnologies, [
      'infantry_weapons',
      'electronic_mechanical_engineering',
    ]);
    expect(ger.activeResearch, ['basic_machine_tools']);
    final fra = details.countries['FRA']!;
    expect(fra.capitalStateId, 16);
    expect(fra.stability, isNull);
    expect(fra.warSupport, 0.0);
    expect(fra.civilianFactories, 4);
    expect(fra.militaryFactories, 2);
    expect(fra.dockyards, 0);
    expect(fra.stateAvailableManpower, 600);
    expect(fra.divisionCount, isNull);
    expect(fra.militaryProductionLines, isNull);
    expect(fra.navalProductionLines, isNull);
  });

  test('Rejects unclosed object and incomplete typed payload', () {
    final unclosed = BinarySaveFixture();
    unclosed.object(0x2D49, (world) {
      world.stringKeyObject('GER', (country) {
        country.fieldInt32(0x284B, 64);
      });
    });
    final bytes = unclosed.build();
    expect(
      () => BinarySaveWorldParser.parse(
        Uint8List.fromList(bytes.sublist(0, bytes.length - 2)),
      ),
      throwsA(isA<SaveReadException>()),
    );

    final partial = BinarySaveFixture();
    partial.fieldInt32(0x349D, 31);
    final truncated = partial.build();
    expect(
      () => BinarySaveWorldParser.parse(
        Uint8List.fromList(truncated.sublist(0, truncated.length - 1)),
      ),
      throwsA(isA<SaveReadException>()),
    );
  });

  test('Rejects unverified binary save versions explicitly', () {
    final fixture = BinarySaveFixture()..fieldInt32(0x349D, 32);
    expect(
      () => BinarySaveWorldParser.parse(Uint8List.fromList(fixture.build())),
      throwsA(isA<SaveReadException>()),
    );
  });
}
