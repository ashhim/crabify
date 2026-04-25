import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../data/demo_catalog.dart';
import '../models/artist_profile.dart';
import '../models/import_draft.dart';
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
      unawaited(markRecentlyPlayed(track.id, trackSnapshot: track));
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
  final Map<String, MusicTrack> _retainedTracks = <String, MusicTrack>{};
  final Set<String> _likedTrackIds = <String>{};
  final List<String> _recentTrackIds = <String>[];
  final Map<String, double> _downloadProgress = <String, double>{};
  String? _activePlaylistPlaybackId;
  String selectedSearchTag = 'crabify';
  String selectedLibraryFilter = 'playlists';

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
  List<MusicTrack> get localTracks {
    final result = <String, MusicTrack>{};
    for (final track in <MusicTrack>[
      ...downloadedTracks,
      ...importedTracks,
      ...uploadedTracks,
    ]) {
      result.putIfAbsent(track.cacheKey, () => track);
    }
    return result.values.toList();
  }

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
    _refreshPlaylistCoverArtwork();
    final removedMissingTracks = await _pruneMissingManagedLocalTracks();
    if (removedMissingTracks) {
      await _persistState();
    }

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
      _rememberTracks(freshTracks);
      usingFallbackCatalog = false;
      onlineError = null;
      _syncStarterPlaylistsWithOnlineTracks();
      _refreshPlaylistCoverArtwork();
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
        _refreshPlaylistCoverArtwork();
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
      _rememberTracks(remoteResults);
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
    final lookup = <String, MusicTrack>{
      ..._retainedTracks,
      for (final track in allTracks) track.id: track,
    };
    return lookup[id];
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
  bool canDownloadTrack(MusicTrack track) =>
      downloadDisabledReason(track) == null;
  String? downloadDisabledReason(MusicTrack track) {
    if (_downloadProgress.containsKey(track.id)) {
      return 'Download already in progress.';
    }
    if (track.hasValidLocalSource) {
      return 'This track is already stored locally.';
    }
    if (isDownloaded(track.id)) {
      return 'This track is already downloaded.';
    }
    if (!track.downloadable) {
      return 'The artist has not enabled downloading for this track.';
    }
    if (!track.hasValidRemoteSource) {
      return 'This track is not available for offline download right now.';
    }
    return null;
  }

  Future<void> toggleLike(String trackId, {MusicTrack? trackSnapshot}) async {
    if (trackSnapshot != null) {
      _rememberTrack(trackSnapshot);
    } else {
      final track = trackById(trackId);
      if (track != null) {
        _rememberTrack(track);
      }
    }
    if (_likedTrackIds.contains(trackId)) {
      _likedTrackIds.remove(trackId);
    } else {
      _likedTrackIds.add(trackId);
    }
    _cleanupDanglingTrackReferences();
    await _persistState();
    notifyListeners();
  }

  Future<void> markRecentlyPlayed(
    String trackId, {
    MusicTrack? trackSnapshot,
  }) async {
    if (trackSnapshot != null) {
      _rememberTrack(trackSnapshot);
    }
    _recentTrackIds.remove(trackId);
    _recentTrackIds.insert(0, trackId);
    if (_recentTrackIds.length > 20) {
      _recentTrackIds.removeRange(20, _recentTrackIds.length);
    }
    final track = trackSnapshot ?? trackById(trackId);
    if (track != null) {
      _updateLastPlayedPlaylistCovers(track);
    }
    _cleanupDanglingTrackReferences();
    await _persistState();
    notifyListeners();
  }

  Future<void> playTracks(
    List<MusicTrack> tracks, {
    required String selectedTrackId,
    bool shuffle = false,
    String? playlistContextId,
  }) async {
    _activePlaylistPlaybackId = playlistContextId;
    final playableTracks = await _resolvePlayableTracks(tracks);
    if (playableTracks.isEmpty) {
      final message = 'No playable tracks are available right now.';
      debugPrint('[Audio] $message');
      _audioPlayerService.reportError(message);
      return;
    }

    MusicTrack? selectedTrack;
    for (final track in playableTracks) {
      if (track.id == selectedTrackId) {
        selectedTrack = track;
        break;
      }
    }

    if (selectedTrack == null) {
      final message =
          'The selected track is no longer available locally or cannot be streamed right now.';
      debugPrint('[Audio] $message | trackId=$selectedTrackId');
      _audioPlayerService.reportError(message);
      return;
    }

    try {
      _rememberTracks(playableTracks);
      await _audioPlayerService.setQueue(
        playableTracks,
        initialTrackId: selectedTrack.id,
        shuffle: shuffle,
      );
      if (_audioPlayerService.currentTrack?.cacheKey !=
          selectedTrack.cacheKey) {
        return;
      }
      await markRecentlyPlayed(selectedTrack.id, trackSnapshot: selectedTrack);
    } catch (error) {
      debugPrint('[Audio] Failed to play track queue: $error');
    }
  }

  Future<void> playPlaylist(
    MusicCollection playlist, {
    String? selectedTrackId,
    bool shuffle = false,
  }) async {
    final tracks = tracksForCollection(playlist);
    if (tracks.isEmpty) {
      _audioPlayerService.reportError('${playlist.title} has no tracks yet.');
      return;
    }

    final startTrackId =
        selectedTrackId ??
        (shuffle
            ? tracks[Random().nextInt(tracks.length)].id
            : tracks.first.id);
    await playTracks(
      tracks,
      selectedTrackId: startTrackId,
      shuffle: shuffle,
      playlistContextId: playlist.id,
    );
  }

  Future<void> shuffleAllPlaylists() async {
    final orderedTracks = <MusicTrack>[];
    final seenKeys = <String>{};
    for (final playlist in playlists) {
      for (final track in tracksForCollection(playlist)) {
        if (seenKeys.add(track.cacheKey)) {
          orderedTracks.add(track);
        }
      }
    }

    if (orderedTracks.isEmpty) {
      _audioPlayerService.reportError(
        'There are no playlist tracks to shuffle.',
      );
      return;
    }

    orderedTracks.shuffle(Random());
    await playTracks(
      orderedTracks,
      selectedTrackId: orderedTracks.first.id,
      shuffle: true,
    );
  }

  Future<void> setSelectedSearchTag(String tag) async {
    if (selectedSearchTag == tag) {
      return;
    }
    selectedSearchTag = tag;
    await _persistState();
    notifyListeners();
  }

  Future<void> setSelectedLibraryFilter(String filter) async {
    if (selectedLibraryFilter == filter) {
      return;
    }
    selectedLibraryFilter = filter;
    await _persistState();
    notifyListeners();
  }

  Future<void> addToQueue(MusicTrack track) async {
    if (!await _canUseTrack(track)) {
      _audioPlayerService.reportError(
        'This track is not available for playback right now.',
      );
      return;
    }

    _rememberTrack(track);
    await _audioPlayerService.addToQueue(track);
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

  Future<void> importLocalTracks() {
    return quickImportTracks();
  }

  Future<void> quickImportTracks() async {
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
      final draft = await _buildImportDraftFromFile(file.path!);
      final importedTrack = await _saveImportedDraft(draft);
      importedTracks = _upsertTrack(importedTracks, importedTrack);
    }

    await _persistState();
    notifyListeners();
  }

  Future<ImportDraft?> createCustomImportDraft() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
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

    final sourcePath = result?.files.single.path;
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return null;
    }

    return _buildImportDraftFromFile(sourcePath);
  }

  Future<MusicTrack> saveCustomImport(ImportDraft draft) async {
    final importedTrack = await _saveImportedDraft(draft);
    importedTracks = _upsertTrack(importedTracks, importedTrack);
    await _persistState();
    notifyListeners();
    return importedTrack;
  }

  Future<void> downloadTrack(MusicTrack track) async {
    final disabledReason = downloadDisabledReason(track);
    if (disabledReason != null) {
      throw StateError(disabledReason);
    }

    if (!track.isPlayable) {
      return;
    }

    final sourceUrl =
        track.isLocal
            ? track.localPath!
            : await _audiusApiService.resolveFreshPlaybackUrl(track);
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
      _rememberTrack(downloadedTrack);
      _downloadProgress.remove(track.id);
      await _persistState();
      notifyListeners();
    } catch (error) {
      _downloadProgress.remove(track.id);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteLocalTrack(MusicTrack track) async {
    if (!track.hasValidLocalSource) {
      throw StateError(
        'Only locally stored tracks can be removed from the device.',
      );
    }

    if (_downloadProgress.containsKey(track.id)) {
      throw StateError(
        'Wait for the current download to finish before deleting it.',
      );
    }

    final fallbackRemoteTrack =
        track.origin == TrackOrigin.downloaded && track.hasValidRemoteSource
            ? track.copyWith(
              origin: TrackOrigin.online,
              clearLocalPath: true,
              clearArtworkPath:
                  track.artworkUrl != null && track.artworkUrl!.isNotEmpty,
            )
            : null;

    await _removeTrackFromQueue(track);

    await _localStorageService.deleteManagedFile(track.localPath);
    await _localStorageService.deleteManagedFile(track.artworkPath);

    downloadedTracks =
        downloadedTracks
            .where((candidate) => candidate.cacheKey != track.cacheKey)
            .toList();
    importedTracks =
        importedTracks
            .where((candidate) => candidate.cacheKey != track.cacheKey)
            .toList();
    uploadedTracks =
        uploadedTracks
            .where((candidate) => candidate.cacheKey != track.cacheKey)
            .toList();
    if (fallbackRemoteTrack != null) {
      _rememberTrack(fallbackRemoteTrack);
    } else {
      _retainedTracks.remove(track.id);
    }

    _cleanupDanglingTrackReferences();
    await _persistState();
    notifyListeners();
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
    _rememberTrack(uploadedTrack);
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
      coverMode: PlaylistCoverMode.lastPlayed,
    );
    playlists = <MusicCollection>[newPlaylist, ...playlists];
    await _persistState();
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    MusicCollection? playlist;
    for (final item in playlists) {
      if (item.id == playlistId) {
        playlist = item;
        break;
      }
    }
    if (playlist == null) {
      return;
    }

    await _localStorageService.deleteManagedFile(playlist.coverImagePath);
    playlists =
        playlists.where((candidate) => candidate.id != playlistId).toList();
    if (_activePlaylistPlaybackId == playlistId) {
      _activePlaylistPlaybackId = null;
    }
    _cleanupDanglingTrackReferences();
    await _persistState();
    notifyListeners();
  }

  Future<void> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
    MusicTrack? trackSnapshot,
  }) async {
    if (trackSnapshot != null) {
      _rememberTrack(trackSnapshot);
    }
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
          final nextTrackIds =
              playlist.trackIds.where((id) => id != trackId).toList();
          final coverTrackRemoved = playlist.coverTrackId == trackId;
          final nextPlaylist = playlist.copyWith(
            trackIds: nextTrackIds,
            coverTrackId:
                coverTrackRemoved
                    ? (nextTrackIds.isEmpty ? null : nextTrackIds.first)
                    : playlist.coverTrackId,
            clearCoverTrackId: coverTrackRemoved && nextTrackIds.isEmpty,
          );
          return _withResolvedPlaylistCover(nextPlaylist);
        }).toList();
    _cleanupDanglingTrackReferences();
    await _persistState();
    notifyListeners();
  }

  Future<void> movePlaylistTrack({
    required String playlistId,
    required int oldIndex,
    required int newIndex,
  }) async {
    playlists =
        playlists.map((playlist) {
          if (playlist.id != playlistId) {
            return playlist;
          }
          if (oldIndex < 0 ||
              oldIndex >= playlist.trackIds.length ||
              newIndex < 0 ||
              newIndex > playlist.trackIds.length) {
            return playlist;
          }
          final adjustedIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;
          if (adjustedIndex == oldIndex) {
            return playlist;
          }
          final nextIds = List<String>.from(playlist.trackIds);
          final trackId = nextIds.removeAt(oldIndex);
          nextIds.insert(adjustedIndex, trackId);
          return playlist.copyWith(trackIds: nextIds);
        }).toList();
    await _persistState();
    notifyListeners();
  }

  Future<void> useLastPlayedPlaylistCover(String playlistId) async {
    final current = playlists.where((playlist) => playlist.id == playlistId);
    if (current.isNotEmpty) {
      await _localStorageService.deleteManagedFile(
        current.first.coverImagePath,
      );
    }
    playlists =
        playlists.map((playlist) {
          if (playlist.id != playlistId) {
            return playlist;
          }
          final coverTrackId =
              playlist.coverTrackId != null &&
                      playlist.trackIds.contains(playlist.coverTrackId)
                  ? playlist.coverTrackId
                  : (playlist.trackIds.isEmpty
                      ? null
                      : playlist.trackIds.first);
          return _withResolvedPlaylistCover(
            playlist.copyWith(
              coverMode: PlaylistCoverMode.lastPlayed,
              coverTrackId: coverTrackId,
              clearCoverTrackId: coverTrackId == null,
              clearCoverImagePath: true,
            ),
          );
        }).toList();
    await _persistState();
    notifyListeners();
  }

  Future<void> useFixedPlaylistCover({
    required String playlistId,
    required String trackId,
  }) async {
    final current = playlists.where((playlist) => playlist.id == playlistId);
    if (current.isNotEmpty) {
      await _localStorageService.deleteManagedFile(
        current.first.coverImagePath,
      );
    }
    playlists =
        playlists.map((playlist) {
          if (playlist.id != playlistId ||
              !playlist.trackIds.contains(trackId)) {
            return playlist;
          }
          return _withResolvedPlaylistCover(
            playlist.copyWith(
              coverMode: PlaylistCoverMode.fixedTrack,
              coverTrackId: trackId,
              clearCoverImagePath: true,
            ),
          );
        }).toList();
    await _persistState();
    notifyListeners();
  }

  Future<void> pickLocalPlaylistCover(String playlistId) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.image,
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return;
    }

    final copiedPath = await _localStorageService.copyPlaylistCover(
      sourcePath,
      '$playlistId-cover',
    );
    if (copiedPath == null) {
      return;
    }

    playlists =
        playlists.map((playlist) {
          if (playlist.id != playlistId) {
            return playlist;
          }
          return playlist.copyWith(
            coverMode: PlaylistCoverMode.localImage,
            coverImagePath: copiedPath,
            artworkPath: copiedPath,
            clearArtworkUrl: true,
          );
        }).toList();
    await _persistState();
    notifyListeners();
  }

  List<MusicTrack> tracksForCollection(MusicCollection collection) {
    return _resolveTracks(collection.trackIds);
  }

  MusicCollection playlistWithResolvedCover(MusicCollection playlist) {
    return _withResolvedPlaylistCover(playlist);
  }

  List<MusicTrack> tracksForArtist(ArtistProfile artist) {
    return allTracks.where((track) => track.artistId == artist.id).toList();
  }

  bool get uploadUsesStub => !_audiusApiService.hasUploadProxy;

  void _updateLastPlayedPlaylistCovers(MusicTrack track) {
    final activePlaylistId = _activePlaylistPlaybackId;
    if (activePlaylistId == null) {
      return;
    }

    var changed = false;
    playlists =
        playlists.map((playlist) {
          if (playlist.id != activePlaylistId ||
              playlist.coverMode != PlaylistCoverMode.lastPlayed ||
              !playlist.trackIds.contains(track.id)) {
            return playlist;
          }
          changed = true;
          return _withResolvedPlaylistCover(
            playlist.copyWith(coverTrackId: track.id),
          );
        }).toList();

    if (changed) {
      debugPrint('[Library] Playlist cover updated from last played track.');
    }
  }

  MusicCollection _withResolvedPlaylistCover(MusicCollection playlist) {
    if (playlist.coverMode == PlaylistCoverMode.localImage) {
      final coverPath = playlist.coverImagePath;
      if (coverPath != null &&
          coverPath.trim().isNotEmpty &&
          File(coverPath).existsSync()) {
        return playlist.copyWith(artworkPath: coverPath, clearArtworkUrl: true);
      }
    }

    final coverTrackId =
        playlist.coverTrackId != null &&
                playlist.trackIds.contains(playlist.coverTrackId)
            ? playlist.coverTrackId
            : (playlist.trackIds.isEmpty ? null : playlist.trackIds.first);
    final coverTrack = coverTrackId == null ? null : trackById(coverTrackId);

    if (coverTrack == null) {
      return playlist.copyWith(
        clearArtworkPath: true,
        clearArtworkUrl: true,
        clearCoverTrackId: playlist.coverMode != PlaylistCoverMode.localImage,
      );
    }

    return playlist.copyWith(
      coverTrackId: coverTrack.id,
      artworkPath: coverTrack.artworkPath,
      artworkUrl: coverTrack.artworkUrl,
      clearArtworkPath: coverTrack.artworkPath == null,
      clearArtworkUrl: coverTrack.artworkUrl == null,
    );
  }

  void _refreshPlaylistCoverArtwork() {
    playlists = playlists.map(_withResolvedPlaylistCover).toList();
  }

  Future<ImportDraft> _buildImportDraftFromFile(String sourcePath) async {
    AudioMetadata? metadata;
    try {
      metadata = readMetadata(File(sourcePath), getImage: true);
    } catch (_) {
      metadata = null;
    }

    final picture =
        metadata?.pictures.isNotEmpty == true ? metadata!.pictures.first : null;
    final albumTitle =
        metadata?.album?.trim().isNotEmpty == true
            ? metadata!.album!.trim()
            : 'Imported Tracks';
    final artistName =
        metadata?.artist?.trim().isNotEmpty == true
            ? metadata!.artist!.trim()
            : 'Local audio';

    return ImportDraft(
      sourceAudioPath: sourcePath,
      title:
          metadata?.title?.trim().isNotEmpty == true
              ? metadata!.title!.trim()
              : path.basenameWithoutExtension(sourcePath),
      artistName: artistName,
      albumTitle: albumTitle,
      genre:
          metadata?.genres.isNotEmpty == true ? metadata!.genres.first : null,
      durationSeconds: metadata?.duration?.inSeconds,
      embeddedArtworkBytes: picture?.bytes,
      embeddedArtworkMimeType: picture?.mimetype,
    );
  }

  Future<MusicTrack> _saveImportedDraft(ImportDraft draft) async {
    final importedId = _newId('local');
    final copiedPath = await _localStorageService.copyImportedAudio(
      draft.sourceAudioPath,
      importedId,
    );

    final coverPath =
        draft.hasManualCover
            ? await _localStorageService.copyImportedCover(
              draft.coverImagePath,
              '$importedId-cover',
            )
            : await _localStorageService.persistArtworkBytes(
              draft.embeddedArtworkBytes,
              '$importedId-cover',
              mimeType: draft.embeddedArtworkMimeType ?? 'image/jpeg',
            );

    final importedTrack = MusicTrack(
      id: importedId,
      title: draft.title.trim().isEmpty ? 'Imported track' : draft.title.trim(),
      artistName:
          draft.artistName.trim().isEmpty
              ? 'Local audio'
              : draft.artistName.trim(),
      artistId: _slug(
        draft.artistName.trim().isEmpty ? 'Local audio' : draft.artistName,
      ),
      albumTitle:
          draft.albumTitle.trim().isEmpty
              ? 'Imported Tracks'
              : draft.albumTitle.trim(),
      albumId: _slug(
        draft.albumTitle.trim().isEmpty ? 'Imported Tracks' : draft.albumTitle,
      ),
      artworkPath: coverPath,
      genre: draft.genre?.trim().isEmpty == true ? null : draft.genre?.trim(),
      localPath: copiedPath,
      durationSeconds: draft.durationSeconds,
      downloadable: false,
      origin: TrackOrigin.local,
      description: 'Imported from your device storage for offline playback.',
    );
    _rememberTrack(importedTrack);
    return importedTrack;
  }

  Future<List<MusicTrack>> _resolvePlayableTracks(
    List<MusicTrack> tracks,
  ) async {
    final playableTracks = <MusicTrack>[];
    var removedMissingLocalTrack = false;

    for (final track in tracks) {
      if (!track.hasValidId) {
        continue;
      }

      if (track.hasValidLocalSource) {
        if (await _localStorageService.fileExists(track.localPath)) {
          playableTracks.add(track);
          continue;
        }

        removedMissingLocalTrack = true;
        debugPrint(
          '[Library] Local file missing for ${track.title} | path=${track.localPath}',
        );
        continue;
      }

      if (track.hasValidRemoteSource) {
        playableTracks.add(track);
      }
    }

    if (removedMissingLocalTrack) {
      final changed = await _pruneMissingManagedLocalTracks();
      if (changed) {
        await _persistState();
        notifyListeners();
      }
    }

    final deduped = <String, MusicTrack>{};
    for (final track in playableTracks) {
      deduped.putIfAbsent(track.cacheKey, () => track);
    }
    return deduped.values.toList();
  }

  Future<bool> _canUseTrack(MusicTrack track) async {
    if (!track.hasValidId) {
      return false;
    }

    if (track.hasValidLocalSource) {
      return _localStorageService.fileExists(track.localPath);
    }

    return track.hasValidRemoteSource;
  }

  Future<bool> _pruneMissingManagedLocalTracks() async {
    var changed = false;

    Future<List<MusicTrack>> keepExisting(List<MusicTrack> tracks) async {
      final result = <MusicTrack>[];
      for (final track in tracks) {
        if (!track.hasValidLocalSource) {
          result.add(track);
          continue;
        }

        if (await _localStorageService.fileExists(track.localPath)) {
          result.add(track);
          continue;
        }

        changed = true;
        debugPrint(
          '[Library] Pruning missing local track ${track.title} | path=${track.localPath}',
        );
        await _localStorageService.deleteManagedFile(track.artworkPath);
      }
      return result;
    }

    downloadedTracks = await keepExisting(downloadedTracks);
    importedTracks = await keepExisting(importedTracks);
    uploadedTracks = await keepExisting(uploadedTracks);

    if (changed) {
      _cleanupDanglingTrackReferences();
    }

    return changed;
  }

  void _cleanupDanglingTrackReferences() {
    final availableTrackIds = <String>{
      ...allTracks.map((track) => track.id),
      ..._retainedTracks.keys,
    };

    _likedTrackIds.removeWhere(
      (trackId) => !availableTrackIds.contains(trackId),
    );
    _recentTrackIds.removeWhere(
      (trackId) => !availableTrackIds.contains(trackId),
    );
    playlists =
        playlists.map((playlist) {
          final trackIds =
              playlist.trackIds
                  .where((trackId) => availableTrackIds.contains(trackId))
                  .toList();
          final coverTrackId =
              playlist.coverTrackId != null &&
                      trackIds.contains(playlist.coverTrackId)
                  ? playlist.coverTrackId
                  : (trackIds.isEmpty ? null : trackIds.first);
          return _withResolvedPlaylistCover(
            playlist.copyWith(
              trackIds: trackIds,
              coverTrackId: coverTrackId,
              clearCoverTrackId: coverTrackId == null,
            ),
          );
        }).toList();

    final liveTrackIds = allTracks.map((track) => track.id).toSet();
    _retainedTracks.removeWhere((trackId, track) {
      if (liveTrackIds.contains(trackId)) {
        return false;
      }
      if (track.hasValidLocalSource) {
        return true;
      }
      return !_likedTrackIds.contains(trackId) &&
          !_recentTrackIds.contains(trackId) &&
          !playlists.any((playlist) => playlist.trackIds.contains(trackId));
    });
  }

  Future<void> _removeTrackFromQueue(MusicTrack track) async {
    final queuedMatches = <int>[];
    for (var index = 0; index < _audioPlayerService.queue.length; index += 1) {
      final queuedTrack = _audioPlayerService.queue[index];
      if (queuedTrack.cacheKey == track.cacheKey) {
        queuedMatches.add(index);
      }
    }

    for (final index in queuedMatches.reversed) {
      await _audioPlayerService.removeAt(index);
    }
  }

  List<MusicTrack> _resolveTracks(List<String> ids) {
    final lookup = <String, MusicTrack>{
      ..._retainedTracks,
      for (final track in allTracks) track.id: track,
    };
    return ids.map((id) => lookup[id]).whereType<MusicTrack>().toList();
  }

  void _rememberTracks(Iterable<MusicTrack> tracks) {
    for (final track in tracks) {
      _rememberTrack(track);
    }
  }

  void _rememberTrack(MusicTrack track) {
    if (!track.hasValidId) {
      return;
    }
    _retainedTracks[track.id] = track;
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

    _retainedTracks
      ..clear()
      ..addAll(
        ((state['retainedTracks'] as Map<String, dynamic>?) ??
                const <String, dynamic>{})
            .map(
              (key, value) => MapEntry(
                key,
                MusicTrack.fromJson(value as Map<String, dynamic>),
              ),
            ),
      );

    selectedSearchTag =
        state['selectedSearchTag'] as String? ?? selectedSearchTag;
    selectedLibraryFilter =
        state['selectedLibraryFilter'] as String? ?? selectedLibraryFilter;
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
      'retainedTracks': _retainedTracks.map(
        (key, track) => MapEntry(key, track.toJson()),
      ),
      'selectedSearchTag': selectedSearchTag,
      'selectedLibraryFilter': selectedLibraryFilter,
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
