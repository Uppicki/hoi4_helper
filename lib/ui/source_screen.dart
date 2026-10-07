import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/game_localization.dart';

/// Keeps source selection separate from the save browser for future adapters.
class SourceScreen extends StatelessWidget {
  const SourceScreen({
    super.key,
    required this.onSelectFiles,
    required this.language,
  });

  final VoidCallback onSelectFiles;
  final ValueListenable<GameLanguage> language;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GameLanguage>(
    valueListenable: language,
    builder: (context, selected, _) {
      String label(String russian, String english) =>
          selected == GameLanguage.russian ? russian : english;
      return Scaffold(
        appBar: AppBar(
          title: Text(label('Источник состояния', 'World source')),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                Text(
                  label('Выберите источник', 'Choose a source'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  label(
                    'Сейчас состояние мира загружается из завершённого сохранения игры.',
                    'The world state is currently loaded from a completed game save.',
                  ),
                  style: const TextStyle(color: Color(0xFFAAB7AD)),
                ),
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    key: const Key('file-source'),
                    contentPadding: const EdgeInsets.all(20),
                    leading: const Icon(Icons.save_outlined, size: 32),
                    title: Text(label('Файл сохранения', 'Save file')),
                    subtitle: Text(
                      label(
                        'Выбрать папку и сохранение .hoi4',
                        'Choose a folder and a .hoi4 save',
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: onSelectFiles,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
