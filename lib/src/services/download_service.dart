import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

import '../models/music_track.dart';
import 'local_storage_service.dart';

class DownloadService {
  DownloadService({required LocalStorageService storageService})
    : _storageService = storageService,
      _dio = Dio();

  final LocalStorageService _storageService;
  final Dio _dio;

  Future<MusicTrack> downloadTrack({
    required MusicTrack track,
    required String sourceUrl,
    void Function(double progress)? onProgress,
  }) async {
    final extension = _extensionFromUrl(sourceUrl, fallback: '.mp3');
    final targetPath = await _storageService.createDownloadPath(
      track.id,
      extension: extension,
    );

    await _dio.download(
      sourceUrl,
      targetPath,
      onReceiveProgress: (received, total) {
        if (total <= 0) {
          onProgress?.call(0);
          return;
        }
        onProgress?.call(received / total);
      },
    );

    String? localArtworkPath = track.artworkPath;
    if (localArtworkPath == null &&
        track.artworkUrl != null &&
        track.artworkUrl!.isNotEmpty) {
      try {
        final artworkExtension = _extensionFromUrl(
          track.artworkUrl!,
          fallback: '.jpg',
        );
        final coverResponse = await _dio.get<List<int>>(
          track.artworkUrl!,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = coverResponse.data;
        if (bytes != null && bytes.isNotEmpty) {
          localArtworkPath = await _storageService.persistArtworkBytes(
            bytes,
            '${track.id}-download',
            mimeType: _mimeTypeFromExtension(artworkExtension),
          );
        }
      } catch (_) {
        // Cover art is optional for offline playback.
      }
    }

    return track.copyWith(
      localPath: targetPath,
      artworkPath: localArtworkPath,
      origin: TrackOrigin.downloaded,
    );
  }

  String _extensionFromUrl(String url, {required String fallback}) {
    final uri = Uri.tryParse(url);
    final extension = uri == null ? '' : path.extension(uri.path).toLowerCase();
    if (extension.isEmpty || extension.length > 6) {
      return fallback;
    }
    return extension;
  }

  String _mimeTypeFromExtension(String extension) {
    return switch (extension.toLowerCase()) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }
}
