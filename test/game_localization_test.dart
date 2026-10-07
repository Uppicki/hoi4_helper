import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoi4_helper/core/game_localization.dart';

void main() {
  test(
    'Loads game labels in the selected language and keeps unknown codes',
    () async {
      final root = await Directory.systemTemp.createTemp('hoi4_localization_');
      addTearDown(() => root.delete(recursive: true));
      final separator = Platform.pathSeparator;
      for (final language in ['russian', 'english']) {
        final folder = Directory(
          '${root.path}${separator}localisation$separator$language',
        );
        await folder.create(recursive: true);
        final isRussian = language == 'russian';
        await File('${folder.path}${separator}names.yml').writeAsString(
          '\ufeffl_$language:\n'
          ' GER:0 "${isRussian ? 'Германия' : 'Germany'}"\n'
          ' GER_fascism: "${isRussian ? 'Третий рейх' : 'German Reich'}"\n'
          ' STATE_64: "${isRussian ? 'Бранденбург' : 'Brandenburg'}"\n'
          ' basic_machine_tools: "${isRussian ? 'Базовые станки' : 'Basic machine tools'}"\n',
        );
      }
      final repository = GameLocalizationRepository(gameRoot: root.path);
      final russian = await repository.load(GameLanguage.russian);
      final english = await repository.load(GameLanguage.english);

      expect(russian.country('GER', ideology: 'fascism'), 'Третий рейх');
      expect(russian.state(64), 'Бранденбург · #64');
      expect(russian.state(999), 'STATE_999');
      expect(russian.name('basic_machine_tools'), 'Базовые станки');
      expect(russian.name('unmapped_focus'), 'unmapped_focus');
      expect(english.country('GER', ideology: 'fascism'), 'German Reich');
      expect(english.name('basic_machine_tools'), 'Basic machine tools');
      expect(english.name('normal'), 'Normal');
    },
  );
}
