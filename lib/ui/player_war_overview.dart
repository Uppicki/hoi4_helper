import 'package:flutter/material.dart';

import '../core/game_localization.dart';
import '../core/player_world.dart';

/// Receives only the permitted projection, never raw world fields.
class PlayerWarOverview extends StatelessWidget {
  const PlayerWarOverview({
    super.key,
    required this.knowledge,
    required this.names,
    required this.language,
  });

  final PlayerWorldKnowledge knowledge;
  final GameLocalization names;
  final GameLanguage language;

  String _ui(String ru, String en) =>
      language == GameLanguage.russian ? ru : en;

  @override
  Widget build(BuildContext context) {
    final world = knowledge.observation;
    final message = switch (knowledge.availability) {
      PlayerWorldAvailability.unavailable => _ui(
        'Ожидаем полное наблюдение мода.',
        'Waiting for a complete mod observation.',
      ),
      PlayerWorldAvailability.unsupported => _ui(
        'Этот формат мода не передаёт список противников.',
        'This mod format does not provide the opponent list.',
      ),
      PlayerWorldAvailability.unknown => _ui(
        'Происхождение или правило видимости списка не подтверждено.',
        'The list source or visibility rule is unverified.',
      ),
      PlayerWorldAvailability.invalid => _ui(
        'Список противников не прошёл проверку.',
        'The opponent list did not pass validation.',
      ),
      PlayerWorldAvailability.ready =>
        world!.relations.isEmpty
            ? _ui(
                'В этом полном наблюдении стран-противников нет.',
                'There are no opponent countries in this complete observation.',
              )
            : _ui(
                'Страны, с которыми игрок воюет на дату этого наблюдения:',
                'Countries at war with the player at this observation date:',
              ),
    };
    return Card(
      key: const Key('player-war-overview'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ui('Войны игрока', 'Player wars'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(message, key: const Key('player-war-status')),
            if (world != null) ...[
              const SizedBox(height: 8),
              Text('${_ui('Игровая дата: ', 'Game date: ')}${world.gameDate}'),
              for (final relation in world.relations)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${names.country(relation.otherTag)} · ${relation.otherTag} — ${_ui('Война с игроком', 'At war with player')}',
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              _ui(
                'Это обзор собственных войн, а не полный перечень стран мира. Остальные отношения не определены.',
                'This covers the player’s own wars, not all countries in the world. Other relations are unknown.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
