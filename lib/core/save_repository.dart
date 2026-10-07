import 'dart:io';

class SaveFile {
  const SaveFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modified;
}

class LoadedSave {
  const LoadedSave({
    required this.file,
    required this.bytesRead,
    required this.loadedAt,
    this.prefixBytes = const [],
  });

  final SaveFile file;
  final int bytesRead;
  final DateTime loadedAt;

  /// A small prefix captured during the same verified read as [bytesRead].
  final List<int> prefixBytes;
}

class SaveReadException implements Exception {
  const SaveReadException(this.message);
  final String message;
}

/// Reads source files without modifying them. Game parsing is a later stage.
class SaveRepository {
  Future<List<SaveFile>> list(String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      throw const SaveReadException('Папка не найдена. Проверьте путь.');
    }
    final saves = <SaveFile>[];
    await for (final entry in folder.list(followLinks: false)) {
      if (entry is! File || !entry.path.toLowerCase().endsWith('.hoi4')) {
        continue;
      }
      final stat = await entry.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      saves.add(_describe(entry, stat));
    }
    saves.sort((a, b) {
      final byDate = b.modified.compareTo(a.modified);
      return byDate != 0 ? byDate : a.name.compareTo(b.name);
    });
    return saves;
  }

  Future<LoadedSave> load(SaveFile save) async {
    final file = File(save.path);
    final before = await file.stat();
    if (before.type != FileSystemEntityType.file) {
      throw const SaveReadException(
        'Файл больше недоступен. Обновите список сохранений.',
      );
    }
    if (before.size == 0) {
      throw const SaveReadException(
        'Файл пуст. Дождитесь окончания сохранения и попробуйте снова.',
      );
    }
    // Stream instead of retaining potentially large saves in UI memory.
    var bytesRead = 0;
    final prefix = <int>[];
    await for (final chunk in file.openRead()) {
      bytesRead += chunk.length;
      if (prefix.length < 4096) {
        prefix.addAll(chunk.take(4096 - prefix.length));
      }
    }
    final after = await file.stat();
    if (after.type != FileSystemEntityType.file ||
        before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed ||
        bytesRead != after.size) {
      throw const SaveReadException(
        'Файл изменился во время чтения. Дождитесь окончания записи '
        'и загрузите его снова.',
      );
    }
    return LoadedSave(
      file: _describe(file, after),
      bytesRead: bytesRead,
      loadedAt: DateTime.now(),
      prefixBytes: List<int>.unmodifiable(prefix),
    );
  }

  SaveFile _describe(File file, FileStat stat) => SaveFile(
    path: file.absolute.path,
    name: file.uri.pathSegments.last,
    size: stat.size,
    modified: stat.modified,
  );
}
