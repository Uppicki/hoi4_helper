import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/game_localization.dart';
import '../core/telemetry_log.dart';
import '../core/telemetry_snapshot.dart';
import 'world_screen.dart';

/// Live observations from the optional mod, separate from save snapshots.
class TelemetryScreen extends StatefulWidget {
  const TelemetryScreen({
    super.key,
    required this.language,
    required this.onChangeSource,
    this.reader,
    this.localizationRepository,
  });

  final ValueNotifier<GameLanguage> language;
  final VoidCallback onChangeSource;
  final TelemetryLogReader? reader;
  final GameLocalizationRepository? localizationRepository;

  @override
  State<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends State<TelemetryScreen> {
  TelemetryLogReader? _reader;
  TelemetryObservation? _observation;
  Timer? _timer;
  bool _receivedWhileOpen = false;
  bool _reading = false;
  DateTime _readAt = DateTime.now();

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
          _readAt = DateTime.now();
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
  Widget build(BuildContext context) => WorldScreen(
    snapshot: telemetryDisplaySnapshot(_observation, readAt: _readAt),
    telemetryMode: true,
    telemetryManpower: _observation?.manpower,
    telemetry: _observation,
    telemetryReceivedWhileOpen: _receivedWhileOpen,
    language: widget.language,
    localizationRepository: widget.localizationRepository,
    onChangeSource: widget.onChangeSource,
  );
}
