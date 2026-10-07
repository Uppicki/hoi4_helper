import 'dart:async';
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
  final Map<String, BinarySaveHeader> saveHeaders = {};
  final Set<String> unavailableHeaders = {};
  SaveFile? selected;
  LoadedSave? loaded;
  WorldStateSnapshot? worldState;
  String? error;

  /// Folder scan only. Save previews can be superseded by another selection.
  bool busy = false;
  bool previewLoading = false;
  int _previewRequest = 0;
  int _folderRequest = 0;
  bool _disposed = false;

  void changeMode(WorkMode value) {
    mode = value;
    _notify();
  }

  void select(SaveFile value) {
    if (busy) return;
    selected = value;
    unawaited(loadFromSource(SaveFileSourceSettings(value)));
  }

  void clearSelection() {
    _previewRequest++;
    selected = null;
    loaded = null;
    worldState = null;
    error = null;
    previewLoading = false;
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
    final folderRequest = ++_folderRequest;
    _previewRequest++;
    previewLoading = false;
    error = null;
    folder = cleanPath;
    saves = [];
    saveHeaders.clear();
    unavailableHeaders.clear();
    selected = null;
    loaded = null;
    worldState = null;
    _notify();
    try {
      saves = await _repository.list(cleanPath);
      unawaited(_readSaveHeaders(folderRequest, saves));
    } catch (exception) {
      error = _message(exception);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _readSaveHeaders(int request, List<SaveFile> files) async {
    for (final save in files) {
      try {
        final header = BinarySaveHeader.parse(
          await _repository.readHeader(save),
        );
        if (!_isCurrentFolder(request)) return;
        saveHeaders[save.path] = header;
      } catch (_) {
        if (!_isCurrentFolder(request)) return;
        unavailableHeaders.add(save.path);
      }
      _notify();
    }
  }

  bool _isCurrentFolder(int request) => !_disposed && request == _folderRequest;

  Future<void> loadSelected() async {
    final save = selected;
    if (save == null || busy || previewLoading) return;
    await loadFromSource(SaveFileSourceSettings(save));
  }

  Future<void> loadFromSource(WorldStateSourceSettings settings) async {
    if (busy) return;
    final request = ++_previewRequest;
    previewLoading = true;
    error = null;
    loaded = null;
    worldState = null;
    _notify();
    try {
      final snapshot = await _sourceFactory.create(settings).read();
      if (!_isCurrent(request)) return;
      loaded = snapshot.loadedSave;
      worldState = snapshot;
    } catch (exception) {
      if (!_isCurrent(request)) return;
      error = _message(exception);
    } finally {
      if (_isCurrent(request)) {
        previewLoading = false;
        _notify();
      }
    }
  }

  bool _isCurrent(int request) => !_disposed && request == _previewRequest;

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
    _folderRequest++;
    super.dispose();
  }
}
