import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  LocalStorageService._({
    required SharedPreferences preferences,
    required Directory appDirectory,
    required Directory importDirectory,
    required Directory uploadDirectory,
    required Directory downloadDirectory,
    required Directory coverDirectory,
  }) : _preferences = preferences,
       _appDirectory = appDirectory,
       _importDirectory = importDirectory,
       _uploadDirectory = uploadDirectory,
       _downloadDirectory = downloadDirectory,
       _coverDirectory = coverDirectory;

  final SharedPreferences _preferences;
  final Directory _appDirectory;
  final Directory _importDirectory;
  final Directory _uploadDirectory;
  final Directory _downloadDirectory;
  final Directory _coverDirectory;

  static const String _stateKey = 'crabify.library_state.v1';

  static Future<LocalStorageService> create() async {
    final preferences = await SharedPreferences.getInstance();
    final docsDirectory = await getApplicationDocumentsDirectory();
    final appDirectory = Directory(path.join(docsDirectory.path, 'crabify'));
    final importDirectory = Directory(path.join(appDirectory.path, 'imports'));
    final uploadDirectory = Directory(path.join(appDirectory.path, 'uploads'));
    final downloadDirectory = Directory(
      path.join(appDirectory.path, 'downloads'),
    );
    final coverDirectory = Directory(path.join(appDirectory.path, 'covers'));

    for (final directory in <Directory>[
      appDirectory,
      importDirectory,
      uploadDirectory,
      downloadDirectory,
      coverDirectory,
    ]) {
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
    }

    return LocalStorageService._(
      preferences: preferences,
      appDirectory: appDirectory,
      importDirectory: importDirectory,
      uploadDirectory: uploadDirectory,
      downloadDirectory: downloadDirectory,
      coverDirectory: coverDirectory,
    );
  }

  Directory get appDirectory => _appDirectory;
  Directory get importDirectory => _importDirectory;
  Directory get uploadDirectory => _uploadDirectory;
  Directory get downloadDirectory => _downloadDirectory;
  Directory get coverDirectory => _coverDirectory;

  Map<String, dynamic> loadState() {
    final raw = _preferences.getString(_stateKey);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> saveState(Map<String, dynamic> state) {
    return _preferences.setString(_stateKey, jsonEncode(state));
  }

  Future<String> copyImportedAudio(String sourcePath, String id) async {
    return _copyFileInto(
      sourcePath: sourcePath,
      targetDirectory: _importDirectory,
      fileName: '$id${_safeExtension(sourcePath, fallback: '.mp3')}',
    );
  }

  Future<String> createImportedAudioPath(
    String id, {
    String extension = '.mp3',
  }) {
    final file = File(path.join(_importDirectory.path, '$id$extension'));
    return Future<String>.value(file.path);
  }

  Future<String?> copyImportedCover(String? sourcePath, String id) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return null;
    }

    return _copyFileInto(
      sourcePath: sourcePath,
      targetDirectory: _coverDirectory,
      fileName: '$id${_safeExtension(sourcePath, fallback: '.png')}',
    );
  }

  Future<String> copyUploadedAudio(String sourcePath, String id) async {
    return _copyFileInto(
      sourcePath: sourcePath,
      targetDirectory: _uploadDirectory,
      fileName: '$id${_safeExtension(sourcePath, fallback: '.mp3')}',
    );
  }

  Future<String?> copyUploadedCover(String? sourcePath, String id) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return null;
    }

    return _copyFileInto(
      sourcePath: sourcePath,
      targetDirectory: _coverDirectory,
      fileName: '$id${_safeExtension(sourcePath, fallback: '.png')}',
    );
  }

  Future<String?> copyPlaylistCover(String? sourcePath, String id) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return null;
    }

    return _copyFileInto(
      sourcePath: sourcePath,
      targetDirectory: _coverDirectory,
      fileName: '$id${_safeExtension(sourcePath, fallback: '.png')}',
    );
  }

  Future<String?> persistArtworkBytes(
    List<int>? bytes,
    String id, {
    String mimeType = 'image/jpeg',
  }) async {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final extension = switch (mimeType) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      _ => '.jpg',
    };
    final file = File(path.join(_coverDirectory.path, '$id$extension'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> createDownloadPath(
    String trackId, {
    String extension = '.mp3',
  }) {
    final file = File(path.join(_downloadDirectory.path, '$trackId$extension'));
    return Future<String>.value(file.path);
  }

  Future<void> deleteIfExists(String? filePath) async {
    if (filePath == null || filePath.trim().isEmpty) {
      return;
    }
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<bool> fileExists(String? filePath) async {
    if (filePath == null || filePath.trim().isEmpty) {
      return false;
    }
    return File(filePath).exists();
  }

  bool isManagedPath(String? filePath) {
    if (filePath == null || filePath.trim().isEmpty) {
      return false;
    }

    final normalizedPath = path.normalize(filePath);
    final managedRoots = <String>[
      _appDirectory.path,
      _importDirectory.path,
      _uploadDirectory.path,
      _downloadDirectory.path,
      _coverDirectory.path,
    ].map(path.normalize);

    return managedRoots.any(
      (managedRoot) =>
          normalizedPath == managedRoot ||
          normalizedPath.startsWith('$managedRoot${path.separator}'),
    );
  }

  Future<void> deleteManagedFile(String? filePath) async {
    if (!isManagedPath(filePath)) {
      return;
    }
    await deleteIfExists(filePath);
  }

  Future<String> _copyFileInto({
    required String sourcePath,
    required Directory targetDirectory,
    required String fileName,
  }) async {
    final sourceFile = File(sourcePath);
    final targetFile = File(path.join(targetDirectory.path, fileName));

    if (!await sourceFile.exists()) {
      throw FileSystemException('Source file could not be found.', sourcePath);
    }

    if (targetFile.existsSync()) {
      await targetFile.delete();
    }

    return sourceFile.copy(targetFile.path).then((copied) => copied.path);
  }

  String _safeExtension(String sourcePath, {required String fallback}) {
    final extension = path.extension(sourcePath).toLowerCase();
    if (extension.isEmpty || extension.length > 6) {
      return fallback;
    }
    return extension;
  }
}
