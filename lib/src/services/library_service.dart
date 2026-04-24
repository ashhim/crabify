import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../data/demo_catalog.dart';
import '../models/artist_profile.dart';
import '../models/music_collection.dart';
import '../models/music_track.dart';
import '../models/upload_draft.dart';
import 'audio_player_service.dart';
import 'audius_api_service.dart';
import 'download_service.dart';
import 'local_storage_service.dart';

class LibraryService extends ChangeNotifier {
  LibraryService({
    required AudiusApiService audiusApiService,
    required LocalStorageService localStorageService,
    required DownloadService downloadService,
    required AudioPlayerService audioPlayerService,
  }) : _audiusApiService = audiusApiService,
       _localStorageService = localStorageService,
       _downloadService = downloadService,
       _audioPlayerService = audioPlayerService {
    _audioPlayerService.onTrackChanged = (track) {
      if (track == null) {
        return;
      }
      unawaited(markRecentlyPlayed(track.id));
    };
  }

  final AudiusApiService _audiusApiService;
  final LocalStorageService _localStorageService;
  final DownloadService _downloadService;
  final AudioPlayerService _audioPlayerService;

  bool isLoading = true;
  bool usingFallbackCatalog = true;
  String? onlineError;

  List<MusicTrack> onlineTracks = <MusicTrack>[];
  List<MusicTrack> importedTracks = <MusicTrack>[];
  List<MusicTrack> downloadedTracks = <MusicTrack>[];
  List<MusicTrack> uploadedTracks = <MusicTrack>[];
  List<MusicCollection> playlists = <MusicCollection>[];
  final Set<String> _likedTrackIds = <String>{};
  final List<String> _recentTrackIds = <String>[];
  final Map<String, double> _downloadProgress = <String, double>{};

  List<MusicTrack> get allTracks {
    final result = <String, MusicTrack>{};
    for (final track in <MusicTrack>[
      ...downloadedTracks,
      ...uploadedTracks,
      ...importedTracks,
      ...onlineTracks,
    ]) {
      result.putIfAbsent(track.id, () => track);
    }
    return result.values.toList();
  }

  List<MusicTrack> get likedTracks => _resolveTracks(_likedTrackIds.toList());
  List<MusicTrack> get recentTracks => _resolveTracks(_recentTrackIds);
  Map<String, double> get downloadProgress =>
      Map<String, double>.unmodifiable(_downloadProgress);

  List<MusicCollection> get albums {
    final grouped = <String, List<MusicTrack>>{};
    for (final track in allTracks) {
      if (track.albumTitle.trim().isEmpty) {
        continue;
      }
      final albumId = track.albumId ?? _slug(track.albumTitle);
      grouped.putIfAbsent(albumId, () => <MusicTrack>[]).add(track);
    }

    return grouped.entries.map((entry) {
        final tracks = entry.value;
        final first = tracks.first;
        return MusicCollection(
          id: entry.key,
          title: first.albumTitle,
          subtitle: first.artistName,
          description:
              'A compact album view assembled from the current Crabify library.',
          type: CollectionType.album,
          trackIds: tracks.map((track) => track.id).toList(),
          artworkUrl: first.artworkUrl,
          artworkPath: first.artworkPath,
        );
      }).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  List<ArtistProfile> get artists => DemoCatalog.artistsFrom(
    allTracks,
    <MusicCollection>[...playlists, ...albums],
  );

  Future<void> initialize() async {
    _restoreState(_localStorageService.loadState());

    isLoading = true;
    notifyListeners();
    await refreshOnlineLibrary(silent: true);
    isLoading = false;
    notifyListeners();
  }

  Future<void> refreshOnlineLibrary({bool silent = false}) async {
    if (!silent) {
      isLoading = true;
      notifyListeners();
    }

    try {
      final freshTracks = await _audiusApiService.fetchTrendingTracks(
        limit: 12,
      );
      onlineTracks = freshTracks;
      usingFallbackCatalog = false;
      onlineError = null;
      _syncStarterPlaylistsWithOnlineTracks();
      debugPrint(
        '[Audius] Library refreshed with ${onlineTracks.length} live tracks.',
      );
    } catch (error) {
      debugPrint('[Audius] Online library refresh failed: $error');
      if (onlineTracks.isEmpty) {
        onlineTracks = DemoCatalog.onlineTracks();
        usingFallbackCatalog = true;
        onlineError =
            'Audius could not be reached, so Crabify loaded the built-in demo catalog instead.';
      } else if (_containsDemoTracks(onlineTracks)) {
        usingFallbackCatalog = true;
        onlineError =
            'Audius refresh failed, so Crabify kept the built-in demo catalog for now.';
      } else {
        usingFallbackCatalog = false;
        onlineError =
            'Audius refresh failed, so Crabify kept the last available online tracks.';
      }
      if (playlists.isEmpty) {
        playlists = DemoCatalog.starterPlaylists(onlineTracks);
      }
    }

    await _persistState();
    if (!silent) {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<List<MusicTrack>> searchTracks(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return <MusicTrack>[];
    }

    final localResults = DemoCatalog.searchTracks(allTracks, trimmed);
    List<MusicTrack> remoteResults = <MusicTrack>[];
    try {
      remoteResults = await _audiusApiService.searchTracks(trimmed, limit: 12);
    } catch (error) {
      debugPrint('[Audius] Search failed for "$trimmed": $error');
    }

    final deduped = <String, MusicTrack>{};
    for (final track in <MusicTrack>[...remoteResults, ...localResults]) {
      deduped.putIfAbsent(track.id, () => track);
    }
    return deduped.values.toList();
  }

  List<ArtistProfile> searchArtists(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return artists.take(6).toList();
    }
    return artists
        .where((artist) => artist.name.toLowerCase().contains(normalized))
        .toList();
  }

  List<MusicCollection> searchCollections(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return <MusicCollection>[...playlists, ...albums].take(6).toList();
    }

    return <MusicCollection>[...playlists, ...albums].where((collection) {
      final haystack =
          <String>[
            collection.title,
            collection.subtitle,
            collection.description,
          ].join(' ').toLowerCase();
      return haystack.contains(normalized);
    }).toList();
  }

  MusicTrack? trackById(String id) {
    for (final track in allTracks) {
      if (track.id == id) {
        return track;
      }
    }
    return null;
  }

  MusicCollection? collectionById(String id) {
    for (final collection in <MusicCollection>[...playlists, ...albums]) {
      if (collection.id == id) {
        return collection;
      }
    }
    return null;
  }

  ArtistProfile? artistById(String id) {
    for (final artist in artists) {
      if (artist.id == id) {
        return artist;
      }
    }
    return null;
  }

  bool isLiked(String trackId) => _likedTrackIds.contains(trackId);
  bool isDownloaded(String trackId) =>
      downloadedTracks.any((track) => track.id == trackId);
  bool isDownloading(String trackId) => _downloadProgress.containsKey(trackId);
  double? progressFor(String trackId) => _downloadProgress[trackId];

  Future<void> toggleLike(String trackId) async {
    if (_likedTrackIds.contains(trackId)) {
      _likedTrackIds.remove(trackId);
    } else {
      _likedTrackIds.add(trackId);
    }
    await _persistState();
    notifyListeners();
  }

  Future<void> markRecentlyPlayed(String trackId) async {
    _recentTrackIds.remove(trackId);
    _recentTrackIds.insert(0, trackId);
    if (_recentTrackIds.length > 20) {
      _recentTrackIds.removeRange(20, _recentTrackIds.length);
    }
    await _persistState();
    notifyListeners();
  }

  Future<void> playTracks(
    List<MusicTrack> tracks, {
    required String selectedTrackId,
    bool shuffle = false,
  }) async {
    final playableTracks =
        tracks
            .where(
              (track) =>
                  track.hasValidId &&
                  (track.hasValidLocalSource || track.hasValidRemoteSource),
            )
            .toList();
    if (playableTracks.isEmpty) {
      debugPrint('[Audio] No valid tracks were provided for playback.');
      return;
    }

    try {
      await _audioPlayerService.setQueue(
        playableTracks,
        initialTrackId: selectedTrackId,
      );
      if (_audioPlayerService.currentTrack?.id != selectedTrackId) {
        return;
      }
      if (shuffle && !_audioPlayerService.shuffleEnabled) {
        await _audioPlayerService.toggleShuffle();
      }
      await markRecentlyPlayed(selectedTrackId);
    } catch (error) {
      debugPrint('[Audio] Failed to play track queue: $error');
    }
  }

  Future<void> addToQueue(MusicTrack track) {
    return _audioPlayerService.addToQueue(track);
  }

  Future<void> removeQueueItem(int index) {
    return _audioPlayerService.removeAt(index);
  }

  Future<void> moveQueueItem(int oldIndex, int newIndex) {
    return _audioPlayerService.moveQueueItem(oldIndex, newIndex);
  }

  Future<void> playQueueItem(int index) {
    return _audioPlayerService.playFromQueue(index);
  }

  Future<void> importLocalTracks() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const <String>[
        'mp3',
        'm4a',
        'wav',
        'flac',
        'ogg',
        'opus',
      ],
    );

    if (result == null) {
      return;
    }

    for (final file in result.files) {
      if (file.path == null || file.path!.trim().isEmpty) {
        continue;
      }
      final importedTrack = await _importTrackFromFile(file.path!);
      importedTracks = _upsertTrack(importedTracks, importedTrack);
    }

    await _persistState();
    notifyListeners();
  }

  Future<void> downloadTrack(MusicTrack track) async {
    if (_downloadProgress.containsKey(track.id) || !track.isPlayable) {
      return;
    }

    if (!track.downloadable) {
      throw StateError(
        'Only tracks explicitly marked as downloadable can be saved offline.',
      );
    }

    if (!track.isLocal && !track.hasValidRemoteSource) {
      throw StateError('Crabify could not validate the remote stream for this track.');
    }

    final sourceUrl =
        track.isLocal
            ? track.localPath!
            : _audiusApiService.resolveStreamUrl(track);
    _downloadProgress[track.id] = 0;
    notifyListeners();

    try {
      final downloadedTrack = await _downloadService.downloadTrack(
        track: track,
        sourceUrl: sourceUrl,
        onProgress: (progress) {
          _downloadProgress[track.id] = progress;
          notifyListeners();
        },
      );

      downloadedTracks = _upsertTrack(downloadedTracks, downloadedTrack);
      _downloadProgress.remove(track.id);
      await _persistState();
      notifyListeners();
    } catch (error) {
      _downloadProgress.remove(track.id);
      notifyListeners();
      rethrow;
    }
  }

  Future<UploadSubmissionResult> submitUpload(UploadDraft draft) async {
    if (!draft.isComplete) {
      throw StateError(
        'Complete the upload form and confirm your rights before publishing.',
      );
    }

    final uploadId = _newId('upload');
    late final String localAudioPath;
    String? localCoverPath;

    try {
      localAudioPath = await _localStorageService.copyUploadedAudio(
        draft.audioFilePath,
        uploadId,
      );
      localCoverPath = await _localStorageService.copyUploadedCover(
        draft.coverImagePath,
        '$uploadId-cover',
      );
    } catch (error) {
      throw StateError(
        'Crabify could not save the selected files locally: $error',
      );
    }

    final submissionResult = await _audiusApiService.submitUpload(draft);

    final uploadedTrack = MusicTrack(
      id: uploadId,
      title: draft.title,
      artistName: draft.artistName,
      artistId: _slug(draft.artistName),
      albumTitle:
          submissionResult.submittedRemotely
              ? 'Published Uploads'
              : 'Local Upload Queue',
      albumId:
          submissionResult.submittedRemotely
              ? 'published-uploads'
              : 'local-upload-queue',
      artworkPath: localCoverPath,
      description: draft.description,
      genre: draft.genre,
      localPath: localAudioPath,
      downloadable: draft.allowDownload,
      origin: TrackOrigin.uploaded,
    );

    uploadedTracks = <MusicTrack>[uploadedTrack, ...uploadedTracks];
    await _persistState();
    if (submissionResult.submittedRemotely) {
      unawaited(refreshOnlineLibrary(silent: true));
    }
    notifyListeners();
    return submissionResult;
  }

  Future<void> createPlaylist(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw StateError('Playlist title cannot be empty.');
    }

    final newPlaylist = MusicCollection(
      id: _newId('playlist'),
      title: trimmed,
      subtitle: 'Custom playlist',
      description: 'Built inside Crabify from your online and offline library.',
      type: CollectionType.playlist,
      trackIds: const <String>[],
      editable: true,
    );
    playlists = <MusicCollection>[newPlaylist, ...playlists];
    await _persistState();
    notifyListeners();
  }

  Future<void> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    playlists =
        playlists.map((playlist) {
          if (playlist.id != playlistId) {
            return playlist;
          }
          if (playlist.trackIds.contains(trackId)) {
            return playlist;
          }
          return playlist.copyWith(
            trackIds: <String>[...playlist.trackIds, trackId],
          );
        }).toList();
    await _persistState();
    notifyListeners();
  }

  Future<void> removeTrackFromPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    playlists =
        playlists.map((playlist) {
          if (playlist.id != playlistId) {
            return playlist;
          }
          return playlist.copyWith(
            trackIds: playlist.trackIds.where((id) => id != trackId).toList(),
          );
        }).toList();
    await _persistState();
    notifyListeners();
  }

  List<MusicTrack> tracksForCollection(MusicCollection collection) {
    return _resolveTracks(collection.trackIds);
  }

  List<MusicTrack> tracksForArtist(ArtistProfile artist) {
    return allTracks.where((track) => track.artistId == artist.id).toList();
  }

  bool get uploadUsesStub => !_audiusApiService.hasUploadProxy;

  Future<MusicTrack> _importTrackFromFile(String sourcePath) async {
    final importedId = _newId('local');
    final copiedPath = await _localStorageService.copyImportedAudio(
      sourcePath,
      importedId,
    );

    AudioMetadata? metadata;
    try {
      metadata = readMetadata(File(copiedPath), getImage: true);
    } catch (_) {
      metadata = null;
    }

    final picture =
        metadata?.pictures.isNotEmpty == true ? metadata!.pictures.first : null;
    final coverPath = await _localStorageService.persistArtworkBytes(
      picture?.bytes,
      '$importedId-cover',
      mimeType: picture?.mimetype ?? 'image/jpeg',
    );

    final albumTitle =
        metadata?.album?.trim().isNotEmpty == true
            ? metadata!.album!.trim()
            : 'Imported Tracks';
    final artistName =
        metadata?.artist?.trim().isNotEmpty == true
            ? metadata!.artist!.trim()
            : 'Local audio';

    return MusicTrack(
      id: importedId,
      title:
          metadata?.title?.trim().isNotEmpty == true
              ? metadata!.title!.trim()
              : path.basenameWithoutExtension(sourcePath),
      artistName: artistName,
      artistId: _slug(artistName),
      albumTitle: albumTitle,
      albumId: _slug(albumTitle),
      artworkPath: coverPath,
      genre:
          metadata?.genres.isNotEmpty == true ? metadata!.genres.first : null,
      localPath: copiedPath,
      durationSeconds: metadata?.duration?.inSeconds,
      downloadable: false,
      origin: TrackOrigin.local,
      description: 'Imported from your device storage for offline playback.',
    );
  }

  List<MusicTrack> _resolveTracks(List<String> ids) {
    final lookup = <String, MusicTrack>{
      for (final track in allTracks) track.id: track,
    };
    return ids.map((id) => lookup[id]).whereType<MusicTrack>().toList();
  }

  List<MusicTrack> _upsertTrack(List<MusicTrack> tracks, MusicTrack candidate) {
    final existingIndex = tracks.indexWhere(
      (track) => track.id == candidate.id,
    );
    if (existingIndex < 0) {
      return <MusicTrack>[candidate, ...tracks];
    }

    final updated = List<MusicTrack>.from(tracks);
    updated[existingIndex] = candidate;
    return updated;
  }

  void _syncStarterPlaylistsWithOnlineTracks() {
    if (onlineTracks.isEmpty) {
      return;
    }

    final starterPlaylists = DemoCatalog.starterPlaylists(onlineTracks);
    final existingStarterPlaylists =
        playlists
            .where(
              (playlist) =>
                  DemoCatalog.starterPlaylistIds.contains(playlist.id),
            )
            .toList();

    final shouldRefreshStarterPlaylists =
        playlists.isEmpty ||
        existingStarterPlaylists.any(_playlistReferencesMissingTracks);

    if (!shouldRefreshStarterPlaylists) {
      return;
    }

    final customPlaylists =
        playlists
            .where(
              (playlist) =>
                  !DemoCatalog.starterPlaylistIds.contains(playlist.id),
            )
            .toList();

    playlists = <MusicCollection>[...starterPlaylists, ...customPlaylists];
  }

  bool _playlistReferencesMissingTracks(MusicCollection playlist) {
    return playlist.trackIds.any((trackId) => trackById(trackId) == null);
  }

  bool _containsDemoTracks(List<MusicTrack> tracks) {
    return tracks.any(
      (track) => track.id.startsWith(DemoCatalog.demoTrackIdPrefix),
    );
  }

  void _restoreState(Map<String, dynamic> state) {
    onlineTracks =
        (state['onlineTracks'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(MusicTrack.fromJson)
            .toList();

    importedTracks =
        (state['importedTracks'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(MusicTrack.fromJson)
            .toList();

    downloadedTracks =
        (state['downloadedTracks'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(MusicTrack.fromJson)
            .toList();

    uploadedTracks =
        (state['uploadedTracks'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(MusicTrack.fromJson)
            .toList();

    playlists =
        (state['playlists'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(MusicCollection.fromJson)
            .toList();

    _likedTrackIds
      ..clear()
      ..addAll(
        (state['likedTrackIds'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>(),
      );

    _recentTrackIds
      ..clear()
      ..addAll(
        (state['recentTrackIds'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>(),
      );
  }

  Future<void> _persistState() {
    return _localStorageService.saveState(<String, dynamic>{
      'onlineTracks': onlineTracks.map((track) => track.toJson()).toList(),
      'importedTracks': importedTracks.map((track) => track.toJson()).toList(),
      'downloadedTracks':
          downloadedTracks.map((track) => track.toJson()).toList(),
      'uploadedTracks': uploadedTracks.map((track) => track.toJson()).toList(),
      'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
      'likedTrackIds': _likedTrackIds.toList(),
      'recentTrackIds': _recentTrackIds,
    });
  }

  String _newId(String prefix) {
    final millis = DateTime.now().microsecondsSinceEpoch;
    final randomValue = Random().nextInt(9000) + 1000;
    return '$prefix-$millis-$randomValue';
  }

  String _slug(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }
}
