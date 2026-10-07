import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/save_repository.dart';
import '../core/world_state.dart';
import '../core/world_state_source.dart';

enum WorkMode { assistant, viewOnly }

class SavesController extends ChangeNotifier {
  SavesController({
    SaveRepository? repository,
    WorldStateSourceFactory? sourceFactory,
  }) : _repository = repository ?? SaveRepository(),
       _sourceFactory =
           sourceFactory ?? WorldStateSourceFactory(repository: repository);

  final SaveRepository _repository;
  final WorldStateSourceFactory _sourceFactory;
  WorkMode mode = WorkMode.assistant;
  String? folder;
  List<SaveFile> saves = [];
  SaveFile? selected;
  LoadedSave? loaded;
  WorldStateSnapshot? worldState;
  String? error;
  bool busy = false;
  bool _disposed = false;

  void changeMode(WorkMode value) {
    mode = value;
    _notify();
  }

  void select(SaveFile value) {
    if (busy) return;
    selected = value;
    loaded = null;
    worldState = null;
    error = null;
    _notify();
  }

  Future<void> openFolder(String path) async {
    if (busy) return;
    final cleanPath = path.trim();
    if (cleanPath.isEmpty) {
      error = 'Выберите папку или введите путь к сохранениям.';
      _notify();
      return;
    }
    busy = true;
    error = null;
    folder = cleanPath;
    saves = [];
    selected = null;
    loaded = null;
    worldState = null;
    _notify();
    try {
      saves = await _repository.list(cleanPath);
    } catch (exception) {
      error = _message(exception);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> loadSelected() async {
    final save = selected;
    if (save == null || busy) return;
    await loadFromSource(SaveFileSourceSettings(save));
  }

  Future<void> loadFromSource(WorldStateSourceSettings settings) async {
    if (busy) return;
    busy = true;
    error = null;
    loaded = null;
    worldState = null;
    _notify();
    try {
      final snapshot = await _sourceFactory.create(settings).read();
      loaded = snapshot.loadedSave;
      worldState = snapshot;
    } catch (exception) {
      error = _message(exception);
    } finally {
      busy = false;
      _notify();
    }
  }

  String _message(Object exception) => switch (exception) {
    SaveReadException(:final message) => message,
    FileSystemException() =>
      'Не удалось прочитать папку или файл. Проверьте путь и права доступа.',
    UnsupportedError() =>
      'Выбранный источник состояния пока не поддерживается.',
    _ => 'Не удалось получить состояние. Попробуйте ещё раз.',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
