import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../data/demo_catalog.dart';
import '../models/artist_profile.dart';
import '../models/device_audio_candidate.dart';
import '../models/import_draft.dart';
import '../models/music_collection.dart';
import '../models/music_track.dart';
import '../models/upload_draft.dart';
import 'audio_player_service.dart';
import 'audius_api_service.dart';
import 'device_media_scanner_service.dart';
import 'download_service.dart';
import 'local_storage_service.dart';

class LibraryService extends ChangeNotifier {
  LibraryService({
    required AudiusApiService audiusApiService,
    required LocalStorageService localStorageService,
    required DownloadService downloadService,
    required AudioPlayerService audioPlayerService,
    required DeviceMediaScannerService deviceMediaScannerService,
  }) : _audiusApiService = audiusApiService,
       _localStorageService = localStorageService,
       _downloadService = downloadService,
       _audioPlayerService = audioPlayerService,
       _deviceMediaScannerService = deviceMediaScannerService {
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
  final DeviceMediaScannerService _deviceMediaScannerService;

  bool isLoading = true;
  bool usingFallbackCatalog = true;
  String? onlineError;
  bool importOperationInProgress = false;
  String? importStatusMessage;
  double? importProgressValue;
  final List<String> _importErrorMessages = <String>[];

  List<MusicTrack> onlineTracks = <MusicTrack>[];
  List<MusicTrack> importedTracks = <MusicTrack>[];
  List<MusicTrack> downloadedTracks = <MusicTrack>[];
  List<MusicTrack> uploadedTracks = <MusicTrack>[];
  List<MusicCollection> playlists = <MusicCollection>[];
  List<ArtistProfile> _savedArtists = <ArtistProfile>[];
  final Map<String, MusicTrack> _retainedTracks = <String, MusicTrack>{};
  final Map<String, MusicTrack> _trackOverrides = <String, MusicTrack>{};
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
  List<String> get importErrorMessages =>
      List<String>.unmodifiable(_importErrorMessages);
  List<ArtistProfile> get savedArtists =>
      _savedArtists.where((artist) => !artist.hidden).toList();

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

  List<ArtistProfile> get artists => _mergeArtists(
    _buildArtistsFromTracks(
      allTracks,
      collections: <MusicCollection>[...playlists, ...albums],
    ),
  );

  List<ArtistProfile> get localArtists => _mergeArtists(
    _buildArtistsFromTracks(localTracks, collections: playlists),
    localOnly: true,
  );

  Future<void> initialize() async {
    _restoreState(_localStorageService.loadState());
    _applyTrackOverrides();
    _syncArtistPlaylists();
    _refreshPlaylistCoverArtwork();
    _refreshArtistCoverArtwork();
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
        limit: 32,
      );
      onlineTracks = freshTracks;
      _applyTrackOverrides();
      _rememberTracks(freshTracks);
      usingFallbackCatalog = false;
      onlineError = null;
      _syncStarterPlaylistsWithOnlineTracks();
      _syncArtistPlaylists();
      _refreshPlaylistCoverArtwork();
      _refreshArtistCoverArtwork();
      debugPrint(
        '[Audius] Library refreshed with ${onlineTracks.length} live tracks.',
      );
    } catch (error) {
      debugPrint('[Audius] Online library refresh failed: $error');
      if (onlineTracks.isEmpty) {
        onlineTracks = DemoCatalog.onlineTracks();
        _applyTrackOverrides();
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
      _syncArtistPlaylists();
      _refreshArtistCoverArtwork();
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
      remoteResults = remoteResults.map(_applyTrackOverride).toList();
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

  Future<List<ArtistProfile>> searchRemoteArtists(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return savedArtists.take(6).toList();
    }

    final tracks = await _audiusApiService.searchTracks(trimmed, limit: 24);
    _rememberTracks(tracks);
    final artists =
        _buildArtistsFromTracks(tracks).where((artist) {
            final haystack =
                <String>[
                  artist.name,
                  artist.description,
                ].join(' ').toLowerCase();
            return haystack.contains(trimmed.toLowerCase());
          }).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return artists.map(_decorateArtist).toList();
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
    final normalizedId = canonicalArtistIdentity(id);
    for (final artist in artists) {
      if (canonicalArtistIdentity(artist.id) == normalizedId) {
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
      _updateArtistLastPlayedCover(track);
    }
    _cleanupDanglingTrackReferences();
    await _persistState();
    notifyListeners();
  }

  Future<void> removeRecentTrack(String trackId) async {
    _recentTrackIds.removeWhere((id) => id == trackId);
    _cleanupDanglingTrackReferences();
    await _persistState();
    notifyListeners();
  }

  Future<void> clearRecentTracks() async {
    _recentTrackIds.clear();
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

  Future<List<DeviceAudioCandidate>> scanDeviceSongs() async {
    final candidates = await _deviceMediaScannerService.scanDeviceSongs();
    final seenPaths = <String>{};
    return candidates.where((candidate) {
      final normalized = _normalizeSourcePath(candidate.path);
      if (normalized.isEmpty ||
          !normalized.endsWith('.mp3') ||
          seenPaths.contains(normalized)) {
        return false;
      }
      seenPaths.add(normalized);
      return true;
    }).toList();
  }

  bool isImportedSourcePath(String sourcePath) {
    final normalized = _normalizeSourcePath(sourcePath);
    if (normalized.isEmpty) {
      return false;
    }
    return localTracks.any(
      (track) => _normalizeSourcePath(track.sourcePath) == normalized,
    );
  }

  Future<int> importDetectedSongs(List<DeviceAudioCandidate> candidates) async {
    if (candidates.isEmpty) {
      return 0;
    }

    _importErrorMessages.clear();
    var importedCount = 0;
    await _runImportOperation<void>('Scanning selected songs...', () async {
      final uniqueCandidates = <DeviceAudioCandidate>[];
      final seenPaths = <String>{};
      for (final candidate in candidates) {
        final normalized = _normalizeSourcePath(candidate.path);
        if (normalized.isEmpty ||
            seenPaths.contains(normalized) ||
            isImportedSourcePath(candidate.path)) {
          continue;
        }
        seenPaths.add(normalized);
        uniqueCandidates.add(candidate);
      }

      for (var index = 0; index < uniqueCandidates.length; index += 1) {
        final candidate = uniqueCandidates[index];
        importStatusMessage = 'Importing ${candidate.title}...';
        importProgressValue = index / uniqueCandidates.length;
        notifyListeners();

        try {
          final draft = await _buildImportDraftFromFile(
            candidate.path,
            detectedCandidate: candidate,
          );
          final importedTrack = await _saveImportedDraft(draft);
          importedTracks = _upsertTrack(importedTracks, importedTrack);
          importedCount += 1;
        } catch (error, stackTrace) {
          debugPrint(
            '[Import] Failed to import detected song ${candidate.path}: $error',
          );
          debugPrintStack(stackTrace: stackTrace);
          _importErrorMessages.add('${candidate.title}: $error');
        }
        importProgressValue = (index + 1) / uniqueCandidates.length;
        notifyListeners();
      }

      _syncArtistPlaylists();
      _refreshArtistCoverArtwork();
      await _persistState();
    });
    if (importedCount == 0 && _importErrorMessages.isNotEmpty) {
      throw StateError(_importErrorMessages.first);
    }
    notifyListeners();
    return importedCount;
  }

  Future<void> quickImportTracks() async {
    _importErrorMessages.clear();
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const <String>[
        'mp3',
        'aac',
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

    final paths =
        result.files
            .map((file) => file.path)
            .whereType<String>()
            .where((path) => path.trim().isNotEmpty)
            .toList();
    if (paths.isEmpty) {
      return;
    }

    await _runImportOperation<void>('Importing local files...', () async {
      for (var index = 0; index < paths.length; index += 1) {
        final sourcePath = paths[index];
        if (isImportedSourcePath(sourcePath)) {
          continue;
        }
        importStatusMessage = 'Importing ${path.basename(sourcePath)}...';
        importProgressValue = index / paths.length;
        notifyListeners();

        final draft = await _buildImportDraftFromFile(sourcePath);
        final importedTrack = await _saveImportedDraft(draft);
        importedTracks = _upsertTrack(importedTracks, importedTrack);
        importProgressValue = (index + 1) / paths.length;
        notifyListeners();
      }

      _syncArtistPlaylists();
      _refreshArtistCoverArtwork();
      await _persistState();
    });
    notifyListeners();
  }

  Future<ImportDraft?> createCustomImportDraft() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const <String>[
        'mp3',
        'aac',
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

    if (isImportedSourcePath(sourcePath)) {
      throw StateError('This file is already in your offline library.');
    }

    return _buildImportDraftFromFile(sourcePath);
  }

  Future<MusicTrack> saveCustomImport(ImportDraft draft) async {
    _importErrorMessages.clear();
    late final MusicTrack importedTrack;
    await _runImportOperation<void>(
      'Saving ${draft.title}...',
      () async {
        importedTrack = await _saveImportedDraft(draft);
        importedTracks = _upsertTrack(importedTracks, importedTrack);
        _syncArtistPlaylists();
        _refreshArtistCoverArtwork();
        await _persistState();
      },
    );
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
      _syncArtistPlaylists();
      _refreshPlaylistCoverArtwork();
      _refreshArtistCoverArtwork();
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
      final removedOverride = _trackOverrides.remove(track.id);
      if (removedOverride != null &&
          removedOverride.artworkPath != track.artworkPath) {
        await _localStorageService.deleteManagedFile(
          removedOverride.artworkPath,
        );
      }
    }

    _cleanupDanglingTrackReferences();
    _syncArtistPlaylists();
    _refreshArtistCoverArtwork();
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
      artistName: buildArtistDisplayName(parseArtistNames(draft.artistName)),
      artistId: _primaryArtistIdForNames(parseArtistNames(draft.artistName)),
      artistNames: _resolvedArtistNames(parseArtistNames(draft.artistName)),
      artistIds: _artistIdsForNames(parseArtistNames(draft.artistName)),
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
      sourcePath: draft.audioFilePath,
      downloadable: draft.allowDownload,
      origin: TrackOrigin.uploaded,
    );

    uploadedTracks = <MusicTrack>[uploadedTrack, ...uploadedTracks];
    _rememberTrack(uploadedTrack);
    _syncArtistPlaylists();
    _refreshArtistCoverArtwork();
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
      artistIds: const <String>[],
      excludedTrackIds: const <String>[],
      editable: true,
      coverMode: PlaylistCoverMode.lastPlayed,
    );
    playlists = <MusicCollection>[newPlaylist, ...playlists];
    await _persistState();
    notifyListeners();
  }

  Future<MusicCollection> createPlaylistFromArtists({
    required String title,
    required List<String> artistIds,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw StateError('Playlist title cannot be empty.');
    }

    final nextPlaylist = _applyArtistSelectionToPlaylist(
      MusicCollection(
        id: _newId('playlist'),
        title: trimmed,
        subtitle:
            artistIds.isEmpty
                ? 'Custom playlist'
                : 'Built from selected artists',
        description:
            'Built inside Crabify from selected artists across your online and offline library.',
        type: CollectionType.playlist,
      trackIds: const <String>[],
      artistIds: _sanitizeArtistIds(artistIds).toList(),
      excludedTrackIds: const <String>[],
      editable: true,
      coverMode: PlaylistCoverMode.lastPlayed,
      ),
      previousArtistIds: const <String>[],
    );

    playlists = <MusicCollection>[nextPlaylist, ...playlists];
    await _persistState();
    notifyListeners();
    return nextPlaylist;
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
            return playlist.copyWith(
              excludedTrackIds:
                  playlist.excludedTrackIds
                      .where((excludedTrackId) => excludedTrackId != trackId)
                      .toList(),
            );
          }
          return playlist.copyWith(
            trackIds: <String>[...playlist.trackIds, trackId],
            excludedTrackIds:
                playlist.excludedTrackIds
                    .where((excludedTrackId) => excludedTrackId != trackId)
                    .toList(),
          );
        }).toList();
    await _persistState();
    notifyListeners();
  }

  Future<void> updatePlaylistArtistSelection({
    required String playlistId,
    required String title,
    required List<String> artistIds,
  }) async {
    playlists =
        playlists.map((playlist) {
          if (playlist.id != playlistId) {
            return playlist;
          }
          final updatedPlaylist = playlist.copyWith(
            title: title.trim().isEmpty ? playlist.title : title.trim(),
            subtitle:
                artistIds.isEmpty
                    ? 'Custom playlist'
                    : 'Built from selected artists',
            artistIds: _sanitizeArtistIds(artistIds).toList(),
          );
          return _applyArtistSelectionToPlaylist(
            updatedPlaylist,
            previousArtistIds: playlist.artistIds,
          );
        }).toList();
    _refreshPlaylistCoverArtwork();
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
          final removedTrack = trackById(trackId);
          final selectedArtistTrack =
              removedTrack != null &&
              _trackMatchesArtistIds(removedTrack, playlist.artistIds);
          final nextExcludedTrackIds = <String>[
            ...playlist.excludedTrackIds.where((id) => id != trackId),
            if (selectedArtistTrack) trackId,
          ];
          final coverTrackRemoved = playlist.coverTrackId == trackId;
          final nextPlaylist = playlist.copyWith(
            trackIds: nextTrackIds,
            excludedTrackIds: nextExcludedTrackIds,
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

  MusicCollection _applyArtistSelectionToPlaylist(
    MusicCollection playlist, {
    required List<String> previousArtistIds,
  }) {
    final previousArtistSet = _sanitizeArtistIds(previousArtistIds);
    final nextArtistSet = _sanitizeArtistIds(playlist.artistIds);
    final nextExcludedTrackIds =
        playlist.excludedTrackIds.where((trackId) {
          final track = trackById(trackId);
          return track != null && _trackMatchesArtistIds(track, nextArtistSet);
        }).toList();
    final nextTrackIds =
        playlist.trackIds.where((trackId) {
          final track = trackById(trackId);
          if (track == null) {
            return false;
          }
          if (!_trackMatchesArtistIds(track, previousArtistSet)) {
            return true;
          }
          return _trackMatchesArtistIds(track, nextArtistSet);
        }).toList();

    for (final artistId in nextArtistSet) {
      for (final track in allTracks.where(
        (track) => track.hasArtistIdentity(artistId),
      )) {
        if (!nextTrackIds.contains(track.id) &&
            !nextExcludedTrackIds.contains(track.id)) {
          nextTrackIds.add(track.id);
        }
      }
    }

    return _withResolvedPlaylistCover(
      playlist.copyWith(
        trackIds: nextTrackIds,
        excludedTrackIds: nextExcludedTrackIds,
      ),
    );
  }

  void _syncArtistPlaylists() {
    playlists =
        playlists.map((playlist) {
          if (playlist.artistIds.isEmpty) {
            return _withResolvedPlaylistCover(playlist);
          }
          return _applyArtistSelectionToPlaylist(
            playlist,
            previousArtistIds: playlist.artistIds,
          );
        }).toList();
  }

  Future<MusicTrack> saveTrackEdits({
    required MusicTrack track,
    required String title,
    required List<String> artistNames,
    String? albumTitle,
    String? genre,
    String? description,
    String? coverImagePath,
    bool clearCover = false,
  }) async {
    return _writeTrackOverride(
      track: track,
      title: title,
      artistNames: artistNames,
      albumTitle: albumTitle,
      genre: genre,
      description: description,
      coverImagePath: coverImagePath,
      clearCover: clearCover,
    );
  }

  Future<void> saveArtist(ArtistProfile artist) async {
    final normalizedId = canonicalArtistIdentity(
      artist.id.isNotEmpty ? artist.id : artist.name,
    );
    final existing = _savedArtistById(normalizedId);
    final nextArtist = _decorateArtist(
      (existing ?? artist).copyWith(
        id: normalizedId,
        name: artist.name,
        description:
            artist.description.isNotEmpty
                ? artist.description
                : (existing?.description ?? ''),
        topTrackIds:
            artist.topTrackIds.isNotEmpty
                ? artist.topTrackIds
                : (existing?.topTrackIds ?? const <String>[]),
        collectionIds:
            artist.collectionIds.isNotEmpty
                ? artist.collectionIds
                : (existing?.collectionIds ?? const <String>[]),
        artworkUrl: artist.artworkUrl ?? existing?.artworkUrl,
        artworkPath: artist.artworkPath ?? existing?.artworkPath,
        coverMode: existing?.coverMode ?? artist.coverMode,
        coverTrackId: existing?.coverTrackId ?? artist.coverTrackId,
        coverImagePath: existing?.coverImagePath ?? artist.coverImagePath,
        hidden: false,
        pinned: true,
        manuallyAdded: true,
      ),
    );
    _saveArtistProfile(nextArtist);
    await _persistState();
    notifyListeners();
  }

  Future<void> addTracksToArtist({
    required ArtistProfile artist,
    required List<MusicTrack> tracks,
  }) async {
    if (tracks.isEmpty) {
      return;
    }
    final canonicalArtistId = canonicalArtistIdentity(artist.id);
    final artistName = artist.name.trim().isEmpty ? 'Unknown artist' : artist.name.trim();
    for (final track in tracks) {
      final nextArtistNames = sanitizeArtistNames(<String>[
        ...track.creditedArtistNames,
        artistName,
      ]);
      await _writeTrackOverride(
        track: track,
        title: track.title,
        artistNames: nextArtistNames,
        albumTitle: track.albumTitle,
        genre: track.genre,
        description: track.description,
        persist: false,
        refreshPlayer: true,
        notifyAfter: false,
      );
    }

    final existing = _savedArtistById(canonicalArtistId) ?? artist;
    _saveArtistProfile(
      _decorateArtist(
        existing.copyWith(
          id: canonicalArtistId,
          name: artistName,
          hidden: false,
          pinned: true,
          manuallyAdded: true,
        ),
      ),
    );
    await _persistState();
    notifyListeners();
  }

  Future<void> removeTracksFromArtist({
    required ArtistProfile artist,
    required List<MusicTrack> tracks,
  }) async {
    if (tracks.isEmpty) {
      return;
    }
    final canonicalArtistId = canonicalArtistIdentity(artist.id);
    for (final track in tracks) {
      final remainingArtists =
          track.artistCredits
              .where((credit) => credit.id != canonicalArtistId)
              .map((credit) => credit.name)
              .toList();
      await _writeTrackOverride(
        track: track,
        title: track.title,
        artistNames: remainingArtists,
        allowEmptyArtists: true,
        albumTitle: track.albumTitle,
        genre: track.genre,
        description: track.description,
        persist: false,
        refreshPlayer: true,
        notifyAfter: false,
      );
    }
    await _persistState();
    notifyListeners();
  }

  Future<ArtistProfile> createManualArtist({
    required String name,
    String description = '',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('Artist name cannot be empty.');
    }
    final artist = ArtistProfile(
      id: canonicalArtistIdentity(trimmed),
      name: trimmed,
      description: description.trim(),
      topTrackIds: const <String>[],
      collectionIds: const <String>[],
      pinned: true,
      manuallyAdded: true,
    );
    await saveArtist(artist);
    return savedArtistById(artist.id) ?? artist;
  }

  Future<void> updateArtistDetails({
    required ArtistProfile artist,
    required String name,
    String description = '',
  }) async {
    final existing = _savedArtistById(artist.id) ?? artist;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('Artist name cannot be empty.');
    }

    _saveArtistProfile(
      _decorateArtist(
        existing.copyWith(
          name: trimmed,
          description: description.trim(),
          hidden: false,
          pinned: true,
          manuallyAdded: true,
        ),
      ),
    );
    await _persistState();
    notifyListeners();
  }

  Future<void> removeArtistFromLibrary(ArtistProfile artist) async {
    final existing = _savedArtistById(artist.id);
    final nextArtist = (existing ?? artist).copyWith(
      id: canonicalArtistIdentity(
        existing?.id.isNotEmpty == true ? existing!.id : artist.name,
      ),
      hidden: true,
      pinned: false,
      manuallyAdded: existing?.manuallyAdded ?? true,
    );
    _saveArtistProfile(nextArtist);
    await _persistState();
    notifyListeners();
  }

  Future<void> useLastPlayedArtistCover(String artistId) async {
    final current = _savedArtistById(artistId) ?? artistById(artistId);
    if (current == null) {
      return;
    }
    await _localStorageService.deleteManagedFile(current.coverImagePath);
    _saveArtistProfile(
      _decorateArtist(
        current.copyWith(
          coverMode: PlaylistCoverMode.lastPlayed,
          clearCoverImagePath: true,
        ),
      ),
    );
    await _persistState();
    notifyListeners();
  }

  Future<void> useFixedArtistCover({
    required String artistId,
    required String trackId,
  }) async {
    final current = _savedArtistById(artistId) ?? artistById(artistId);
    if (current == null) {
      return;
    }
    await _localStorageService.deleteManagedFile(current.coverImagePath);
    _saveArtistProfile(
      _decorateArtist(
        current.copyWith(
          coverMode: PlaylistCoverMode.fixedTrack,
          coverTrackId: trackId,
          clearCoverImagePath: true,
        ),
      ),
    );
    await _persistState();
    notifyListeners();
  }

  Future<void> pickLocalArtistCover(String artistId) async {
    final current = _savedArtistById(artistId) ?? artistById(artistId);
    if (current == null) {
      return;
    }

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
      '$artistId-artist-cover',
    );
    if (copiedPath == null) {
      return;
    }

    _saveArtistProfile(
      _decorateArtist(
        current.copyWith(
          coverMode: PlaylistCoverMode.localImage,
          coverImagePath: copiedPath,
          artworkPath: copiedPath,
          clearArtworkUrl: true,
          hidden: false,
          pinned: true,
          manuallyAdded: true,
        ),
      ),
    );
    await _persistState();
    notifyListeners();
  }

  ArtistProfile? savedArtistById(String id) => _savedArtistById(id);

  List<MusicTrack> tracksForArtist(ArtistProfile artist) {
    final result = <String, MusicTrack>{};
    for (final track in allTracks) {
      if (track.hasArtistIdentity(artist.id)) {
        result[track.cacheKey] = track;
      }
    }
    for (final trackId in artist.topTrackIds) {
      final track = trackById(trackId);
      if (track != null) {
        result[track.cacheKey] = track;
      }
    }
    return result.values.toList();
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

  void _updateArtistLastPlayedCover(MusicTrack track) {
    var changed = false;
    _savedArtists =
        _savedArtists.map((artist) {
          if (!track.hasArtistIdentity(artist.id) ||
              artist.coverMode != PlaylistCoverMode.lastPlayed) {
            return artist;
          }
          changed = true;
          return _decorateArtist(artist.copyWith(coverTrackId: track.id));
        }).toList();

    if (changed) {
      debugPrint('[Library] Artist cover updated from last played track.');
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

  void _refreshArtistCoverArtwork() {
    _savedArtists = _savedArtists.map(_decorateArtist).toList();
  }

  List<ArtistProfile> _buildArtistsFromTracks(
    List<MusicTrack> tracks, {
    List<MusicCollection>? collections,
  }) {
    final grouped = <String, List<MusicTrack>>{};
    final artistNamesById = <String, String>{};
    for (final track in tracks) {
      for (final credit in track.artistCredits) {
        grouped.putIfAbsent(credit.id, () => <MusicTrack>[]).add(track);
        artistNamesById.putIfAbsent(credit.id, () => credit.name);
      }
    }

    return grouped.entries.map((entry) {
        final artistTracks = entry.value;
        final artistName =
            artistNamesById[entry.key] ??
            artistTracks.first.artistCredits
                .firstWhere(
                  (credit) => credit.id == entry.key,
                  orElse:
                      () => ArtistCredit(
                        id: entry.key,
                        name: artistTracks.first.artistName,
                      ),
                )
                .name;
        final collectionIds =
            (collections ?? const <MusicCollection>[])
                .where(
                  (collection) => collection.trackIds.any(
                    (trackId) =>
                        artistTracks.any((track) => track.id == trackId),
                  ),
                )
                .map((collection) => collection.id)
                .toSet()
                .toList();
        return ArtistProfile(
          id: entry.key,
          name: artistName,
          description:
              DemoCatalog.artistBlurbs[entry.key] ??
              '$artistName keeps Crabify grounded in your current library.',
          topTrackIds: artistTracks.map((track) => track.id).toList(),
          collectionIds: collectionIds,
          artworkUrl: artistTracks.first.artworkUrl,
          artworkPath: artistTracks.first.artworkPath,
        );
      }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<ArtistProfile> _mergeArtists(
    List<ArtistProfile> generated, {
    bool localOnly = false,
  }) {
    final merged = <String, ArtistProfile>{};
    for (final artist in generated) {
      final key = canonicalArtistIdentity(
        artist.id.isNotEmpty ? artist.id : artist.name,
      );
      merged[key] = _decorateArtist(artist.copyWith(id: key));
    }
    for (final saved in _savedArtists) {
      final key = canonicalArtistIdentity(
        saved.id.isNotEmpty ? saved.id : saved.name,
      );
      if (saved.hidden) {
        merged.remove(key);
        continue;
      }
      final base = merged[key] ?? saved.copyWith(id: key);
      merged[key] = _decorateArtist(
        base.copyWith(
          id: key,
          name: saved.name.isNotEmpty ? saved.name : base.name,
          description:
              saved.description.isNotEmpty
                  ? saved.description
                  : base.description,
          topTrackIds:
              base.topTrackIds.isNotEmpty
                  ? base.topTrackIds
                  : saved.topTrackIds,
          collectionIds:
              base.collectionIds.isNotEmpty
                  ? base.collectionIds
                  : saved.collectionIds,
          artworkUrl: saved.artworkUrl ?? base.artworkUrl,
          artworkPath: saved.artworkPath ?? base.artworkPath,
          coverMode: saved.coverMode,
          coverTrackId: saved.coverTrackId ?? base.coverTrackId,
          coverImagePath: saved.coverImagePath ?? base.coverImagePath,
          pinned: saved.pinned,
          manuallyAdded: saved.manuallyAdded,
        ),
      );
    }

    final artists = merged.values.where((artist) => !artist.hidden).toList();
    if (!localOnly) {
      artists.sort((a, b) {
        if (a.pinned != b.pinned) {
          return a.pinned ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });
      return artists;
    }

    final localArtistIds =
        generated
            .map(
              (artist) => canonicalArtistIdentity(
                artist.id.isNotEmpty ? artist.id : artist.name,
              ),
            )
            .toSet();
    final filtered =
        artists
            .where(
              (artist) => localArtistIds.contains(artist.id) || artist.pinned,
            )
            .toList()
          ..sort((a, b) {
            if (a.pinned != b.pinned) {
              return a.pinned ? -1 : 1;
            }
            return a.name.compareTo(b.name);
          });
    return filtered;
  }

  ArtistProfile _decorateArtist(ArtistProfile artist) {
    if (artist.coverMode == PlaylistCoverMode.localImage) {
      final localImagePath = artist.coverImagePath;
      if (localImagePath != null &&
          localImagePath.trim().isNotEmpty &&
          File(localImagePath).existsSync()) {
        return artist.copyWith(
          artworkPath: localImagePath,
          clearArtworkUrl: true,
        );
      }
    }

    final artistTracks = tracksForArtist(artist);
    final fixedTrackId =
        artist.coverTrackId != null &&
                artistTracks.any((track) => track.id == artist.coverTrackId)
            ? artist.coverTrackId
            : null;
    final fixedTrack = fixedTrackId == null ? null : trackById(fixedTrackId);
    if (fixedTrack != null &&
        ((fixedTrack.artworkPath?.isNotEmpty ?? false) ||
            (fixedTrack.artworkUrl?.isNotEmpty ?? false))) {
      return artist.copyWith(
        coverTrackId: fixedTrack.id,
        artworkPath: fixedTrack.artworkPath,
        artworkUrl: fixedTrack.artworkUrl,
        clearArtworkPath: fixedTrack.artworkPath == null,
        clearArtworkUrl: fixedTrack.artworkUrl == null,
      );
    }

    final firstTrackWithArtwork = artistTracks.firstWhere(
      (track) =>
          (track.artworkPath?.isNotEmpty ?? false) ||
          (track.artworkUrl?.isNotEmpty ?? false),
      orElse:
          () =>
              _latestPlayedTrackForArtist(artist.id) ??
              const MusicTrack(
                id: '',
                title: '',
                artistName: '',
                artistId: '',
                albumTitle: '',
                origin: TrackOrigin.online,
              ),
    );
    if (firstTrackWithArtwork.hasValidId) {
      return artist.copyWith(
        coverTrackId: firstTrackWithArtwork.id,
        artworkPath: firstTrackWithArtwork.artworkPath,
        artworkUrl: firstTrackWithArtwork.artworkUrl,
        clearArtworkPath: firstTrackWithArtwork.artworkPath == null,
        clearArtworkUrl: firstTrackWithArtwork.artworkUrl == null,
      );
    }

    final recentTrack = _latestPlayedTrackForArtist(artist.id);
    if (recentTrack != null) {
      return artist.copyWith(
        coverTrackId: recentTrack.id,
        artworkPath: recentTrack.artworkPath,
        artworkUrl: recentTrack.artworkUrl,
        clearArtworkPath: recentTrack.artworkPath == null,
        clearArtworkUrl: recentTrack.artworkUrl == null,
      );
    }

    if ((artist.artworkPath?.isNotEmpty ?? false) ||
        (artist.artworkUrl?.isNotEmpty ?? false)) {
      return artist;
    }

    return artist.copyWith(clearArtworkPath: true, clearArtworkUrl: true);
  }

  MusicTrack? _latestPlayedTrackForArtist(String artistId) {
    for (final trackId in _recentTrackIds) {
      final track = trackById(trackId);
      if (track != null &&
          track.hasArtistIdentity(artistId) &&
          ((track.artworkPath?.isNotEmpty ?? false) ||
              (track.artworkUrl?.isNotEmpty ?? false))) {
        return track;
      }
    }
    return null;
  }

  ArtistProfile? _savedArtistById(String artistId) {
    final normalizedId = canonicalArtistIdentity(artistId);
    for (final artist in _savedArtists) {
      if (canonicalArtistIdentity(artist.id) == normalizedId) {
        return artist;
      }
    }
    return null;
  }

  void _saveArtistProfile(ArtistProfile artist) {
    final normalizedId = canonicalArtistIdentity(
      artist.id.isNotEmpty ? artist.id : artist.name,
    );
    final normalizedArtist = artist.copyWith(id: normalizedId);
    final index = _savedArtists.indexWhere(
      (saved) => canonicalArtistIdentity(saved.id) == normalizedId,
    );
    if (index < 0) {
      _savedArtists = <ArtistProfile>[normalizedArtist, ..._savedArtists];
      return;
    }
    final updated = List<ArtistProfile>.from(_savedArtists);
    updated[index] = normalizedArtist;
    _savedArtists = updated;
  }

  Future<ImportDraft> _buildImportDraftFromFile(
    String sourcePath, {
    DeviceAudioCandidate? detectedCandidate,
  }) async {
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
      sourceAudioUri: detectedCandidate?.sourceUri,
      title:
          metadata?.title?.trim().isNotEmpty == true
              ? metadata!.title!.trim()
              : (detectedCandidate?.title.trim().isNotEmpty == true
                  ? detectedCandidate!.title
                  : path.basenameWithoutExtension(sourcePath)),
      artistName:
          artistName.trim().isNotEmpty
              ? artistName
              : (detectedCandidate?.artistName ?? 'Local audio'),
      albumTitle:
          albumTitle.trim().isNotEmpty
              ? albumTitle
              : (detectedCandidate?.albumTitle ?? 'Imported Tracks'),
      genre:
          metadata?.genres.isNotEmpty == true ? metadata!.genres.first : null,
      durationSeconds:
          metadata?.duration?.inSeconds ?? detectedCandidate?.durationSeconds,
      embeddedArtworkBytes: picture?.bytes,
      embeddedArtworkMimeType: picture?.mimetype,
    );
  }

  Future<MusicTrack> _saveImportedDraft(ImportDraft draft) async {
    final importedId = _newId('local');
    final copiedPath = await _prepareImportedAudioPath(
      draft.sourceAudioPath,
      importedId,
      draft.sourceAudioUri,
    );
    final artistNames = _resolvedArtistNames(
      parseArtistNames(draft.artistName),
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
      artistName: buildArtistDisplayName(artistNames),
      artistId: _primaryArtistIdForNames(artistNames),
      artistNames: artistNames,
      artistIds: _artistIdsForNames(artistNames),
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
      sourcePath: draft.sourceAudioPath,
      durationSeconds: draft.durationSeconds,
      downloadable: false,
      origin: TrackOrigin.local,
      description: 'Imported from your device storage for offline playback.',
    );
    _rememberTrack(importedTrack);
    return importedTrack;
  }

  Future<String> _prepareImportedAudioPath(
    String sourcePath,
    String importedId,
    String? sourceUri,
  ) async {
    if (sourceUri != null && sourceUri.trim().isNotEmpty && Platform.isAndroid) {
      final targetPath = await _localStorageService.createImportedAudioPath(
        importedId,
        extension: '.mp3',
      );
      return _deviceMediaScannerService.copyScannedSongToAppStorage(
        sourceUri: sourceUri,
        targetPath: targetPath,
      );
    }
    return _localStorageService.copyImportedAudio(sourcePath, importedId);
  }

  Future<T> _runImportOperation<T>(
    String statusMessage,
    Future<T> Function() action,
  ) async {
    importOperationInProgress = true;
    importStatusMessage = statusMessage;
    importProgressValue = 0;
    notifyListeners();
    try {
      return await action();
    } finally {
      importOperationInProgress = false;
      importStatusMessage = null;
      importProgressValue = null;
      notifyListeners();
    }
  }

  String _normalizeSourcePath(String? sourcePath) {
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return '';
    }
    return path.normalize(sourcePath).toLowerCase();
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
          final excludedTrackIds =
              playlist.excludedTrackIds
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
              excludedTrackIds: excludedTrackIds,
              coverTrackId: coverTrackId,
              clearCoverTrackId: coverTrackId == null,
            ),
          );
        }).toList();
    _savedArtists =
        _savedArtists.map((artist) {
          final nextTopTrackIds =
              artist.topTrackIds
                  .where((trackId) => availableTrackIds.contains(trackId))
                  .toList();
          final coverTrackId =
              artist.coverTrackId != null &&
                      availableTrackIds.contains(artist.coverTrackId)
                  ? artist.coverTrackId
                  : null;
          return _decorateArtist(
            artist.copyWith(
              topTrackIds: nextTopTrackIds,
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
          !playlists.any((playlist) => playlist.trackIds.contains(trackId)) &&
          !_savedArtists.any((artist) => artist.topTrackIds.contains(trackId));
    });
    _trackOverrides.removeWhere(
      (trackId, _) =>
          !availableTrackIds.contains(trackId) &&
          !_likedTrackIds.contains(trackId) &&
          !_recentTrackIds.contains(trackId),
    );
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
    _retainedTracks[track.id] = _applyTrackOverride(track);
  }

  List<MusicTrack> _upsertTrack(List<MusicTrack> tracks, MusicTrack candidate) {
    final nextCandidate = _applyTrackOverride(candidate);
    final existingIndex = tracks.indexWhere(
      (track) => track.id == nextCandidate.id,
    );
    if (existingIndex < 0) {
      return <MusicTrack>[nextCandidate, ...tracks];
    }

    final updated = List<MusicTrack>.from(tracks);
    updated[existingIndex] = nextCandidate;
    return updated;
  }

  MusicTrack _applyTrackOverride(MusicTrack track) {
    final override = _trackOverrides[track.id];
    if (override == null) {
      return track;
    }

    return track.copyWith(
      title: override.title,
      artistName: override.artistName,
      artistId: override.artistId,
      artistNames: override.artistNames,
      artistIds: override.artistIds,
      albumTitle: override.albumTitle,
      albumId: override.albumId,
      clearAlbumId: override.albumId == null,
      genre: override.genre,
      clearGenre: override.genre == null,
      description: override.description,
      clearDescription: override.description == null,
      artworkPath: override.artworkPath,
      artworkUrl: override.artworkUrl,
      durationSeconds: override.durationSeconds,
      clearArtworkPath: override.artworkPath == null,
      clearArtworkUrl: override.artworkUrl == null,
    );
  }

  void _applyTrackOverrides() {
    onlineTracks = onlineTracks.map(_applyTrackOverride).toList();
    importedTracks = importedTracks.map(_applyTrackOverride).toList();
    downloadedTracks = downloadedTracks.map(_applyTrackOverride).toList();
    uploadedTracks = uploadedTracks.map(_applyTrackOverride).toList();

    final retainedKeys = _retainedTracks.keys.toList();
    for (final key in retainedKeys) {
      final track = _retainedTracks[key];
      if (track != null) {
        _retainedTracks[key] = _applyTrackOverride(track);
      }
    }
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
    _savedArtists =
        (state['savedArtists'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ArtistProfile.fromJson)
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
    _trackOverrides
      ..clear()
      ..addAll(
        ((state['trackOverrides'] as Map<String, dynamic>?) ??
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
      'savedArtists': _savedArtists.map((artist) => artist.toJson()).toList(),
      'likedTrackIds': _likedTrackIds.toList(),
      'recentTrackIds': _recentTrackIds,
      'retainedTracks': _retainedTracks.map(
        (key, track) => MapEntry(key, track.toJson()),
      ),
      'trackOverrides': _trackOverrides.map(
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

  Set<String> _sanitizeArtistIds(Iterable<String> artistIds) {
    return artistIds
        .map(canonicalArtistIdentity)
        .where((artistId) => artistId.isNotEmpty)
        .toSet();
  }

  List<String> _resolvedArtistNames(Iterable<String> artistNames) {
    final cleaned = sanitizeArtistNames(artistNames);
    return cleaned.isEmpty ? <String>['Unknown artist'] : cleaned;
  }

  List<String> _artistIdsForNames(Iterable<String> artistNames) {
    return _resolvedArtistNames(artistNames)
        .map(canonicalArtistIdentity)
        .where((artistId) => artistId.isNotEmpty)
        .toList();
  }

  String _primaryArtistIdForNames(Iterable<String> artistNames) {
    final ids = _artistIdsForNames(artistNames);
    return ids.isEmpty ? canonicalArtistIdentity('Unknown artist') : ids.first;
  }

  bool _trackMatchesArtistIds(MusicTrack track, Iterable<String> artistIds) {
    for (final artistId in artistIds) {
      if (track.hasArtistIdentity(artistId)) {
        return true;
      }
    }
    return false;
  }

  Future<MusicTrack> _writeTrackOverride({
    required MusicTrack track,
    required String title,
    List<String>? artistNames,
    bool allowEmptyArtists = false,
    String? albumTitle,
    String? genre,
    String? description,
    String? coverImagePath,
    bool clearCover = false,
    bool persist = true,
    bool refreshPlayer = true,
    bool notifyAfter = true,
  }) async {
    final current = trackById(track.id) ?? track;
    final existingOverride = _trackOverrides[track.id];
    final normalizedTitle = title.trim().isEmpty ? current.title : title.trim();
    final normalizedArtistNames = switch (artistNames) {
      null => current.creditedArtistNames,
      final names when names.isEmpty && allowEmptyArtists => <String>[
        'Unknown artist',
      ],
      final names => _resolvedArtistNames(names),
    };
    final normalizedArtistIds = _artistIdsForNames(normalizedArtistNames);
    final normalizedAlbum =
        albumTitle == null
            ? current.albumTitle
            : (albumTitle.trim().isEmpty ? '' : albumTitle.trim());
    final normalizedGenre =
        genre == null || genre.trim().isEmpty ? null : genre.trim();
    final normalizedDescription =
        description == null
            ? current.description
            : (description.trim().isEmpty ? null : description.trim());

    String? nextArtworkPath = current.artworkPath;
    String? nextArtworkUrl = current.artworkUrl;
    final previousOverrideArtworkPath = existingOverride?.artworkPath;

    if (clearCover) {
      nextArtworkPath = null;
      nextArtworkUrl = null;
    } else if (coverImagePath != null && coverImagePath.trim().isNotEmpty) {
      nextArtworkPath = await _localStorageService.copyPlaylistCover(
        coverImagePath,
        '${track.id}-track-cover',
      );
      nextArtworkUrl = null;
    }

    if (previousOverrideArtworkPath != null &&
        previousOverrideArtworkPath != nextArtworkPath) {
      await _localStorageService.deleteManagedFile(previousOverrideArtworkPath);
    }

    final updatedTrack = current.copyWith(
      title: normalizedTitle,
      artistName: buildArtistDisplayName(normalizedArtistNames),
      artistId: normalizedArtistIds.first,
      artistNames: normalizedArtistNames,
      artistIds: normalizedArtistIds,
      albumTitle: normalizedAlbum,
      albumId: normalizedAlbum.trim().isEmpty ? null : _slug(normalizedAlbum),
      clearAlbumId: normalizedAlbum.trim().isEmpty,
      genre: normalizedGenre,
      clearGenre: normalizedGenre == null,
      description: normalizedDescription,
      clearDescription: normalizedDescription == null,
      artworkPath: nextArtworkPath,
      artworkUrl: nextArtworkUrl,
      clearArtworkPath: nextArtworkPath == null,
      clearArtworkUrl: nextArtworkUrl == null,
    );

    final updatedArtistIdSet = normalizedArtistIds.toSet();
    _trackOverrides[track.id] = updatedTrack;
    _savedArtists =
        _savedArtists.map((artist) {
          final nextTopTrackIds =
              artist.topTrackIds
                  .where((trackId) => trackId != track.id)
                  .toList();
          if (updatedArtistIdSet.contains(canonicalArtistIdentity(artist.id)) &&
              !nextTopTrackIds.contains(track.id)) {
            nextTopTrackIds.insert(0, track.id);
          }
          return artist.copyWith(topTrackIds: nextTopTrackIds);
        }).toList();
    _applyTrackOverrides();
    _rememberTrack(updatedTrack);
    _syncArtistPlaylists();
    _refreshPlaylistCoverArtwork();
    _refreshArtistCoverArtwork();
    if (refreshPlayer) {
      _audioPlayerService.refreshTrackMetadata(updatedTrack);
    }
    if (persist) {
      await _persistState();
    }
    if (notifyAfter) {
      notifyListeners();
    }
    return updatedTrack;
  }
}
