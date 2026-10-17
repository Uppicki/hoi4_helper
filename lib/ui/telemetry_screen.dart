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
  TelemetryLogPoll? _pollResult;
  Timer? _timer;
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
      setState(() => _pollResult = result);
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
  Widget build(BuildContext context) {
    final observation = _pollResult?.latest;
    return WorldScreen(
      snapshot: telemetryDisplaySnapshot(
        observation,
        readAt: observation?.receivedAt ?? DateTime.now(),
      ),
      telemetryMode: true,
      telemetryManpower: observation?.manpower,
      telemetry: observation,
      telemetryStatus: _pollResult?.status ?? TelemetryStreamStatus.noLog,
      telemetryHistorical: _pollResult?.historical ?? false,
      language: widget.language,
      localizationRepository: widget.localizationRepository,
      onChangeSource: widget.onChangeSource,
    );
  }
}
