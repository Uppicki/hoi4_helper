import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/game_localization.dart';
import '../core/telemetry_log.dart';

/// Live observations from the optional mod, separate from save snapshots.
class TelemetryScreen extends StatefulWidget {
  const TelemetryScreen({
    super.key,
    required this.language,
    required this.onChangeSource,
    this.reader,
  });

  final ValueListenable<GameLanguage> language;
  final VoidCallback onChangeSource;
  final TelemetryLogReader? reader;

  @override
  State<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends State<TelemetryScreen> {
  TelemetryLogReader? _reader;
  TelemetryObservation? _observation;
  Timer? _timer;
  bool _receivedWhileOpen = false;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _reader = widget.reader;
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_reading) return;
    if (_reader == null) {
      final file = TelemetryLogReader.findDefaultLog();
      if (file != null) _reader = TelemetryLogReader(file);
    }
    final reader = _reader;
    if (reader == null) return;
    _reading = true;
    try {
      final result = await reader.poll();
      if (!mounted) return;
      if (!identical(result.latest, _observation) ||
          (result.receivedNewLine && !_receivedWhileOpen)) {
        setState(() {
          _observation = result.latest;
          _receivedWhileOpen =
              result.latest != null &&
              (result.receivedNewLine || _receivedWhileOpen);
        });
      }
    } on FileSystemException {
      // HOI4 can briefly lock game.log while writing.
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GameLanguage>(
    valueListenable: widget.language,
    builder: (context, language, _) {
      String label(String russian, String english) =>
          language == GameLanguage.russian ? russian : english;
      final observation = _observation;
      return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label('ИСТОЧНИК 01', 'SOURCE 01'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      label('Телеметрия', 'Telemetry'),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label(
                        'Данные из запущенной игры обновляются после каждого игрового дня.',
                        'Data from the running game updates after each game day.',
                      ),
                      style: const TextStyle(color: Color(0xFFA6B1A9)),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label(
                                'Последнее наблюдение',
                                'Latest observation',
                              ),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              observation == null
                                  ? label(
                                      'Ожидание game.log. Запустите игру с модом и пропустите день.',
                                      'Waiting for game.log. Start the game with the mod and advance one day.',
                                    )
                                  : label(
                                      'Страна: ${observation.playerTag} · дата: ${observation.gameDate} · людские резервы: ${observation.manpower}',
                                      'Country: ${observation.playerTag} · date: ${observation.gameDate} · manpower: ${observation.manpower}',
                                    ),
                              key: const Key('telemetry-status'),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _receivedWhileOpen
                                  ? label(
                                      'Новая запись получена после открытия экрана.',
                                      'A new line arrived after this screen opened.',
                                    )
                                  : label(
                                      'Последняя запись может относиться к прошлой загрузке.',
                                      'The latest line may belong to an earlier game load.',
                                    ),
                              style: const TextStyle(
                                color: Color(0xFFA6B1A9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      label(
                        'Телеметрия пока содержит только дату, страну и людские резервы. Она не привязана к сохранению и не используется для советов.',
                        'Telemetry currently contains only the date, country and manpower. It is not tied to a save or used for advice.',
                      ),
                      style: const TextStyle(color: Color(0xFFA6B1A9)),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      key: const Key('change-source-from-telemetry'),
                      onPressed: widget.onChangeSource,
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(label('Изменить источник', 'Change source')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
