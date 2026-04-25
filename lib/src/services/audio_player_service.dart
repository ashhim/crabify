import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/music_track.dart';
import 'audius_api_service.dart';

enum PlaybackViewState { idle, loading, playing, paused, stopped, error }

class AudioPlayerService extends ChangeNotifier {
  AudioPlayerService({required AudiusApiService audiusApiService})
    : _audiusApiService = audiusApiService {
    _initialization = _initialize();
  }

  final AudioPlayer _player = AudioPlayer();
  final AudiusApiService _audiusApiService;
  final Random _random = Random();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  late final Future<void> _initialization;
  Future<void> _commandChain = Future<void>.value();

  List<MusicTrack> _queue = <MusicTrack>[];
  int _currentIndex = -1;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration? _duration;
  bool _isPlaying = false;
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  ProcessingState _processingState = ProcessingState.idle;
  String? _lastErrorMessage;
  String? _loadedTrackKey;
  String? _activeCommandTrackId;
  String? _activeCommandAction;
  String? _loadingTrackId;
  bool _disposed = false;
  bool _handlingCompletion = false;
  final List<String> _shuffleOrderKeys = <String>[];

  static const Duration _loadTimeout = Duration(seconds: 12);

  void Function(MusicTrack? track)? onTrackChanged;

  List<MusicTrack> get queue => List<MusicTrack>.unmodifiable(_queue);
  MusicTrack? get currentTrack =>
      _currentIndex < 0 || _currentIndex >= _queue.length
          ? null
          : _queue[_currentIndex];
  int get currentIndex => _currentIndex;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition;
  Duration get duration => _duration ?? currentTrack?.duration ?? Duration.zero;
  bool get isPlaying => _isPlaying;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get loopMode => _loopMode;
  ProcessingState get processingState => _processingState;
  String? get lastErrorMessage => _lastErrorMessage;
  bool get isBusy => _activeCommandAction != null;
  String? get activeTrackId => _activeCommandTrackId;
  bool get isLoading => _loadingTrackId != null;
  String? get loadingTrackId => _loadingTrackId;
  bool get canStop =>
      currentTrack != null &&
      (_isPlaying ||
          _processingState != ProcessingState.idle ||
          _loadingTrackId != null);
  PlaybackViewState get playbackViewState {
    if (_loadingTrackId != null) {
      return PlaybackViewState.loading;
    }
    if (_lastErrorMessage != null && currentTrack != null) {
      return PlaybackViewState.error;
    }
    if (currentTrack == null) {
      return PlaybackViewState.idle;
    }
    if (_isPlaying) {
      return PlaybackViewState.playing;
    }
    if (_processingState == ProcessingState.idle) {
      return PlaybackViewState.stopped;
    }
    return PlaybackViewState.paused;
  }

  void reportError(String message) {
    _recordError(message);
  }

  Future<void> setQueue(
    List<MusicTrack> tracks, {
    String? initialTrackId,
    int initialIndex = 0,
    bool autoPlay = true,
    bool shuffle = false,
  }) async {
    final preparedQueue = _prepareQueue(
      tracks,
      initialTrackId: initialTrackId,
      initialIndex: initialIndex,
    );

    if (preparedQueue == null) {
      _recordError('No playable tracks are available in this queue.');
      return;
    }

    final previousQueue = List<MusicTrack>.from(_queue);
    final previousIndex = _currentIndex;
    final previousLoadedTrackKey = _loadedTrackKey;
    final selectedTrack = preparedQueue.tracks[preparedQueue.initialIndex];

    final started = await _runPlayerCommand<bool>(
      'set queue',
      track: selectedTrack,
      markLoading: true,
      () async {
        _queue = preparedQueue.tracks;
        _currentIndex = preparedQueue.initialIndex;
        _shuffleEnabled = shuffle;
        _refreshShuffleOrder(
          moveCurrentToFront: _shuffleEnabled,
          reshuffleTail: _shuffleEnabled,
        );
        await _loadCurrentTrack(
          autoPlay: autoPlay,
          forceReload: true,
          reason: 'setQueue',
        );
        return true;
      },
      failureMessage: 'Unable to play ${selectedTrack.title}.',
    );

    if (started == true) {
      _announceTrackChange();
      return;
    }

    _queue = previousQueue;
    _currentIndex = previousIndex;
    _loadedTrackKey = previousLoadedTrackKey;
    notifyListeners();
  }

  Future<void> addToQueue(MusicTrack track) async {
    if (!_canQueueTrack(track)) {
      _recordError('${track.title} is not available for playback.');
      return;
    }

    await _runPlayerCommand<void>(
      'add to queue',
      track: track,
      () async {
        if (_queue.isEmpty) {
          _queue = <MusicTrack>[track];
          _currentIndex = -1;
        } else {
          final insertIndex =
              _currentIndex < 0 ? _queue.length : _currentIndex + 1;
          _queue.insert(insertIndex, track);
        }
        _refreshShuffleOrder();
      },
      failureMessage: 'Unable to add ${track.title} to the queue.',
    );
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }

    final previousQueue = List<MusicTrack>.from(_queue);
    final previousIndex = _currentIndex;
    final removedTrack = _queue[index];

    final removed = await _runPlayerCommand<bool>(
      'remove a queue item',
      track: removedTrack,
      markLoading: index == _currentIndex,
      () async {
        final wasCurrentTrack = index == _currentIndex;
        final shouldResume = _isPlaying;
        _queue.removeAt(index);

        if (_queue.isEmpty) {
          _currentIndex = -1;
          _refreshShuffleOrder();
          await _stopUnlocked(clearLoadedTrack: true);
          _announceTrackChange();
          return true;
        }

        if (index < _currentIndex) {
          _currentIndex -= 1;
          return true;
        }

        if (!wasCurrentTrack) {
          return true;
        }

        if (_currentIndex >= _queue.length) {
          _currentIndex = _queue.length - 1;
        }

        _refreshShuffleOrder();
        await _loadCurrentTrack(
          autoPlay: shouldResume,
          forceReload: true,
          reason: 'removeAt',
        );
        _announceTrackChange();
        return true;
      },
      failureMessage: 'Unable to update the queue right now.',
    );

    if (removed != true) {
      _queue = previousQueue;
      _currentIndex = previousIndex;
      notifyListeners();
    }
  }

  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex < 0 ||
        newIndex > _queue.length) {
      return;
    }

    final adjustedIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;
    if (adjustedIndex == oldIndex) {
      return;
    }

    await _runPlayerCommand<void>(
      'reorder the queue',
      track: currentTrack,
      () async {
        final track = _queue.removeAt(oldIndex);
        _queue.insert(adjustedIndex, track);

        if (_currentIndex == oldIndex) {
          _currentIndex = adjustedIndex;
          return;
        }

        if (oldIndex < _currentIndex && adjustedIndex >= _currentIndex) {
          _currentIndex -= 1;
          return;
        }

        if (oldIndex > _currentIndex && adjustedIndex <= _currentIndex) {
          _currentIndex += 1;
        }
        _refreshShuffleOrder();
      },
      failureMessage: 'Unable to reorder the queue right now.',
    );
  }

  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }

    final selectedTrack = _queue[index];
    final started = await _runPlayerCommand<bool>(
      'play the selected queue item',
      track: selectedTrack,
      markLoading: true,
      () async {
        _currentIndex = index;
        await _loadCurrentTrack(
          autoPlay: true,
          forceReload: true,
          reason: 'playFromQueue',
        );
        return true;
      },
      failureMessage: 'Unable to play ${selectedTrack.title}.',
    );

    if (started == true) {
      _announceTrackChange();
    }
  }

  Future<void> play() async {
    if (_queue.isEmpty) {
      _recordError('Pick a track first, then press play.');
      return;
    }

    await _runPlayerCommand<void>(
      'resume playback',
      track: currentTrack ?? _queue.first,
      markLoading: _needsReloadCurrentTrack,
      () async {
        if (_currentIndex < 0) {
          _currentIndex = 0;
          _refreshShuffleOrder();
        }

        if (_needsReloadCurrentTrack) {
          await _loadCurrentTrack(
            autoPlay: true,
            forceReload: true,
            reason: 'play',
          );
          _announceTrackChange();
          return;
        }

        _startPlayback(currentTrack ?? _queue.first, reason: 'resume');
      },
      failureMessage: 'Unable to resume playback.',
    );
  }

  Future<void> pause() async {
    await _runPlayerCommand<void>(
      'pause playback',
      track: currentTrack,
      () => _player.pause(),
      failureMessage: 'Unable to pause playback.',
    );
  }

  Future<void> stop() async {
    await _runPlayerCommand<void>(
      'stop playback',
      track: currentTrack,
      () => _stopUnlocked(clearLoadedTrack: true),
      failureMessage: 'Unable to stop playback.',
    );
  }

  Future<void> togglePlayback() async {
    if (_isPlaying) {
      await pause();
      return;
    }
    await play();
  }

  Future<void> next() async {
    final nextIndex = _computeNextIndex();
    if (nextIndex == null) {
      return;
    }

    final track = _queue[nextIndex];
    final advanced = await _runPlayerCommand<bool>(
      'skip to the next track',
      track: track,
      markLoading: true,
      () async {
        _currentIndex = nextIndex;
        await _loadCurrentTrack(
          autoPlay: true,
          forceReload: true,
          reason: 'next',
        );
        return true;
      },
      failureMessage: 'Unable to skip to the next track.',
    );

    if (advanced == true) {
      _announceTrackChange();
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty) {
      return;
    }

    if (position.inSeconds >= 3 && currentTrack != null) {
      await seek(Duration.zero);
      return;
    }

    final previousIndex = _computePreviousIndex();
    if (previousIndex == null) {
      return;
    }

    final track = _queue[previousIndex];
    final moved = await _runPlayerCommand<bool>(
      'return to the previous track',
      track: track,
      markLoading: true,
      () async {
        _currentIndex = previousIndex;
        await _loadCurrentTrack(
          autoPlay: true,
          forceReload: true,
          reason: 'previous',
        );
        return true;
      },
      failureMessage: 'Unable to return to the previous track.',
    );

    if (moved == true) {
      _announceTrackChange();
    }
  }

  Future<void> seek(Duration position) async {
    if (currentTrack == null) {
      return;
    }

    await _runPlayerCommand<void>(
      'seek within the current track',
      track: currentTrack,
      () => _player.seek(position),
      failureMessage: 'Unable to seek within this track.',
    );
  }

  Future<void> toggleShuffle() async {
    await _runPlayerCommand<void>(
      'toggle shuffle',
      track: currentTrack,
      () async {
        _shuffleEnabled = !_shuffleEnabled;
        _refreshShuffleOrder(
          moveCurrentToFront: _shuffleEnabled,
          reshuffleTail: _shuffleEnabled,
        );
      },
      failureMessage: 'Unable to toggle shuffle right now.',
    );
  }

  Future<void> cycleLoopMode() async {
    await _runPlayerCommand<void>(
      'change repeat mode',
      track: currentTrack,
      () async {
        _loopMode = switch (_loopMode) {
          LoopMode.off => LoopMode.all,
          LoopMode.all => LoopMode.one,
          LoopMode.one => LoopMode.off,
        };
      },
      failureMessage: 'Unable to change repeat mode right now.',
    );
  }

  Future<void> _initialize() async {
    debugPrint('[Audio] Initializing player on $_platformLabel');

    _subscriptions.add(
      _player.positionStream.listen((position) {
        _position = position;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.bufferedPositionStream.listen((position) {
        _bufferedPosition = position;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.durationStream.listen((duration) {
        _duration = duration;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.errorStream.listen((error) {
        final track = currentTrack;
        debugPrint(
          '[Audio] Player error'
          ' | platform=$_platformLabel'
          ' | trackId=${track?.id ?? 'none'}'
          ' | title=${track?.title ?? 'none'}'
          ' | sourceType=${track == null ? 'none' : _sourceTypeForTrack(track)}'
          ' | source=${track == null ? 'n/a' : _streamOrPathForTrack(track)}'
          ' | error=$error',
        );
        _clearLoadingState(trackId: track?.id, notify: false);
        _logErrorDetails(error, track: track, context: 'player error stream');
        _recordError(
          _messageForCommandFailure(
            error,
            action: 'play this track',
            track: track,
          ),
        );
      }),
    );

    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        _isPlaying = state.playing;
        _processingState = state.processingState;

        if (state.playing || state.processingState == ProcessingState.ready) {
          _clearLoadingState(trackId: currentTrack?.id, notify: false);
        } else if (state.processingState == ProcessingState.idle) {
          _clearLoadingState(notify: false);
        }

        if (state.processingState == ProcessingState.completed &&
            !_handlingCompletion) {
          _handlingCompletion = true;
          unawaited(_handleTrackCompletion());
        }

        notifyListeners();
      }),
    );

    debugPrint(
      '[Audio] Player initialized.'
      ' platform=$_platformLabel'
      ' state=$_processingState',
    );
  }

  Future<void> _handleTrackCompletion() async {
    try {
      if (_loopMode == LoopMode.one && currentTrack != null) {
        await _runPlayerCommand<void>(
          'restart the current track',
          track: currentTrack,
          () async {
            await _loadCurrentTrack(
              autoPlay: true,
              forceReload: true,
              reason: 'completed-loop-one',
            );
          },
          failureMessage: 'Unable to restart the current track.',
        );
        return;
      }

      final nextIndex = _computeNextIndex(onCompletion: true);
      if (nextIndex == null) {
        await _runPlayerCommand<void>(
          'finish playback',
          track: currentTrack,
          () => _stopUnlocked(clearLoadedTrack: true),
          failureMessage:
              'Playback ended, but Crabify could not reset cleanly.',
        );
        return;
      }

      _currentIndex = nextIndex;
      await _runPlayerCommand<void>(
        'continue to the next track',
        track: currentTrack,
        () async {
          await _loadCurrentTrack(
            autoPlay: true,
            forceReload: true,
            reason: 'completed-next',
          );
        },
        failureMessage: 'Unable to continue to the next track.',
      );
      _announceTrackChange();
    } finally {
      _handlingCompletion = false;
    }
  }

  Future<void> _loadCurrentTrack({
    required bool autoPlay,
    required bool forceReload,
    required String reason,
  }) async {
    final track = currentTrack;
    if (track == null) {
      throw StateError('No track is selected to load.');
    }

    if (!_canQueueTrack(track)) {
      throw StateError('Track ${track.title} is not playable.');
    }

    final trackKey = _trackLoadKey(track);
    final shouldReload =
        forceReload ||
        _loadedTrackKey != trackKey ||
        _processingState == ProcessingState.idle;
    final sourceType = _sourceTypeForTrack(track);
    final source = _streamOrPathForTrack(track);

    debugPrint(
      '[Audio] Loading track'
      ' | id=${track.id}'
      ' | title=${track.title}'
      ' | sourceType=$sourceType'
      ' | source=$source'
      ' | queueLength=${_queue.length}'
      ' | currentIndex=$_currentIndex'
      ' | playerState=$_processingState'
      ' | platform=$_platformLabel'
      ' | reason=$reason',
    );

    if (shouldReload) {
      await _player.stop();
      _position = Duration.zero;
      _bufferedPosition = Duration.zero;
      _duration = track.duration;
      notifyListeners();
      final tag = _mediaItemForTrack(track);
      Duration? loadedDuration;
      if (track.hasValidLocalSource) {
        final filePath = track.localPath!.trim();
        final file = File(filePath);
        if (!await file.exists()) {
          throw StateError(
            'The local audio file for ${track.title} is missing from $filePath.',
          );
        }
        debugPrint(
          '[Audio] setFilePath'
          ' | platform=$_platformLabel'
          ' | trackId=${track.id}'
          ' | title=${track.title}'
          ' | path=$filePath',
        );
        loadedDuration = await _withLoadTimeout(
          _player.setFilePath(filePath, tag: tag),
          track: track,
          sourceDescription: filePath,
        );
      } else {
        loadedDuration = await _loadRemoteTrack(track, tag: tag);
      }
      _duration = loadedDuration ?? track.duration;
      _loadedTrackKey = trackKey;
      _clearLoadingState(trackId: track.id, notify: false);
      notifyListeners();
    }

    if (autoPlay) {
      _startPlayback(track, reason: reason);
    }
  }

  Future<Duration?> _loadRemoteTrack(
    MusicTrack track, {
    required MediaItem tag,
  }) async {
    final streamUrl = _audiusApiService.resolveStreamUrl(track).trim();

    try {
      return await _setRemoteUrl(
        track,
        tag: tag,
        url: streamUrl,
        strategy: 'canonical-audius-stream',
      );
    } catch (error, stackTrace) {
      _logErrorDetails(
        error,
        track: track,
        context: 'load canonical remote source',
      );

      if (!_shouldRetryRemoteLoad(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }

      return _retryAndroidRemoteTrackLoad(
        track,
        tag: tag,
        failedUrl: streamUrl,
        initialError: error,
        initialStackTrace: stackTrace,
      );
    }
  }

  Future<Duration?> _retryAndroidRemoteTrackLoad(
    MusicTrack track, {
    required MediaItem tag,
    required String failedUrl,
    required Object initialError,
    required StackTrace initialStackTrace,
  }) async {
    debugPrint(
      '[Audio] Android fallback after canonical stream failure'
      ' | platform=$_platformLabel'
      ' | trackId=${track.id}'
      ' | title=${track.title}'
      ' | failedUrl=$failedUrl'
      ' | exception=$initialError',
    );
    debugPrint('$initialStackTrace');

    await _resetAfterLoadFailure(track);

    final freshStreamUrl = await _audiusApiService.resolveFreshPlaybackUrl(
      track,
    );
    return _setRemoteUrl(
      track,
      tag: tag,
      url: freshStreamUrl.trim(),
      strategy: 'android-fresh-direct-stream',
    );
  }

  Future<void> _resetAfterLoadFailure(MusicTrack track) async {
    try {
      debugPrint(
        '[Audio] Resetting player after load failure'
        ' | platform=$_platformLabel'
        ' | trackId=${track.id}'
        ' | title=${track.title}',
      );
      await _player.stop();
    } catch (error, stackTrace) {
      debugPrint(
        '[Audio] Failed to reset player after load failure'
        ' | platform=$_platformLabel'
        ' | trackId=${track.id}'
        ' | title=${track.title}'
        ' | exception=$error',
      );
      debugPrint('$stackTrace');
    }

    _loadedTrackKey = null;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _processingState = ProcessingState.idle;
    _clearLoadingState(trackId: track.id, notify: false);
    notifyListeners();
  }

  Future<Duration?> _setRemoteUrl(
    MusicTrack track, {
    required MediaItem tag,
    required String url,
    required String strategy,
  }) async {
    debugPrint(
      '[Audio] setUrl'
      ' | platform=$_platformLabel'
      ' | trackId=${track.id}'
      ' | title=${track.title}'
      ' | strategy=$strategy'
      ' | url=$url',
    );
    return _withLoadTimeout(
      _player.setUrl(url, tag: tag),
      track: track,
      sourceDescription: url,
    );
  }

  Future<Duration?> _withLoadTimeout(
    Future<Duration?> future, {
    required MusicTrack track,
    required String sourceDescription,
  }) {
    return future.timeout(
      _loadTimeout,
      onTimeout:
          () =>
              throw TimeoutException(
                'Loading ${track.title} timed out from $sourceDescription.',
              ),
    );
  }

  void _startPlayback(MusicTrack track, {required String reason}) {
    debugPrint(
      '[Audio] play'
      ' | platform=$_platformLabel'
      ' | trackId=${track.id}'
      ' | title=${track.title}'
      ' | sourceType=${_sourceTypeForTrack(track)}'
      ' | source=${_streamOrPathForTrack(track)}'
      ' | reason=$reason',
    );
    unawaited(
      _player.play().catchError((Object error, StackTrace stackTrace) {
        debugPrint(
          '[Audio] Failed during play future'
          ' | platform=$_platformLabel'
          ' | trackId=${track.id}'
          ' | title=${track.title}'
          ' | exception=$error',
        );
        debugPrint('$stackTrace');
        _clearLoadingState(trackId: track.id, notify: false);
        _logErrorDetails(error, track: track, context: 'play future');
        _recordError(
          _messageForCommandFailure(
            error,
            action: 'start playback',
            track: track,
          ),
        );
      }),
    );
  }

  MediaItem _mediaItemForTrack(MusicTrack track) {
    final artUri = switch ((track.artworkPath, track.artworkUrl)) {
      (String path, _) when path.isNotEmpty => Uri.file(path),
      (_, String url) when url.isNotEmpty => Uri.parse(url),
      _ => null,
    };

    return MediaItem(
      id: track.id,
      album: track.albumTitle,
      title: track.title,
      artist: track.artistName,
      artUri: artUri,
      playable: true,
    );
  }

  String _sourceTypeForTrack(MusicTrack track) {
    return track.hasValidLocalSource ? 'file' : 'url';
  }

  String _streamOrPathForTrack(MusicTrack track) {
    return track.hasValidLocalSource
        ? track.localPath!.trim()
        : _streamUrlForTrack(track);
  }

  String _streamUrlForTrack(MusicTrack track) {
    return track.hasValidLocalSource
        ? track.localPath!.trim()
        : _audiusApiService.resolveStreamUrl(track).trim();
  }

  String _trackLoadKey(MusicTrack track) {
    return track.hasValidLocalSource
        ? '${track.id}:${track.localPath}'
        : '${track.id}:${_audiusApiService.resolveStreamUrl(track)}';
  }

  bool get _needsReloadCurrentTrack {
    final track = currentTrack;
    if (track == null) {
      return true;
    }
    return _loadedTrackKey != _trackLoadKey(track) ||
        _processingState == ProcessingState.idle;
  }

  bool _canQueueTrack(MusicTrack track) {
    if (!track.hasValidId) {
      return false;
    }

    if (track.hasValidLocalSource) {
      return true;
    }

    return track.hasValidRemoteSource;
  }

  _PreparedQueue? _prepareQueue(
    List<MusicTrack> tracks, {
    String? initialTrackId,
    required int initialIndex,
  }) {
    final playableTracks = tracks.where(_canQueueTrack).fold<List<MusicTrack>>(
      <MusicTrack>[],
      (result, track) {
        final alreadyPresent = result.any(
          (existing) => existing.cacheKey == track.cacheKey,
        );
        if (!alreadyPresent) {
          result.add(track);
        }
        return result;
      },
    );

    if (playableTracks.isEmpty) {
      return null;
    }

    final index =
        initialTrackId == null
            ? initialIndex.clamp(0, playableTracks.length - 1)
            : playableTracks.indexWhere((track) => track.id == initialTrackId);

    return _PreparedQueue(
      tracks: playableTracks,
      initialIndex: index < 0 ? 0 : index,
    );
  }

  int? _computeNextIndex({bool onCompletion = false}) {
    if (_queue.isEmpty || _currentIndex < 0) {
      return null;
    }

    if (_shuffleEnabled && _queue.length > 1) {
      _refreshShuffleOrder();
      final currentKey = currentTrack?.cacheKey;
      final currentOrderIndex = _shuffleOrderKeys.indexOf(currentKey ?? '');
      if (currentOrderIndex < 0) {
        return _queueIndexForCacheKey(
          _shuffleOrderKeys.isEmpty ? null : _shuffleOrderKeys.first,
        );
      }

      final nextOrderIndex = currentOrderIndex + 1;
      if (nextOrderIndex < _shuffleOrderKeys.length) {
        return _queueIndexForCacheKey(_shuffleOrderKeys[nextOrderIndex]);
      }

      if (_loopMode == LoopMode.all ||
          onCompletion && _loopMode == LoopMode.all) {
        return _queueIndexForCacheKey(
          _shuffleOrderKeys.isEmpty ? null : _shuffleOrderKeys.first,
        );
      }

      return null;
    }

    final sequentialNext = _currentIndex + 1;
    if (sequentialNext < _queue.length) {
      return sequentialNext;
    }

    if (_loopMode == LoopMode.all ||
        onCompletion && _loopMode == LoopMode.all) {
      return 0;
    }

    return null;
  }

  int? _computePreviousIndex() {
    if (_queue.isEmpty || _currentIndex < 0) {
      return null;
    }

    if (_shuffleEnabled && _queue.length > 1) {
      _refreshShuffleOrder();
      final currentKey = currentTrack?.cacheKey;
      final currentOrderIndex = _shuffleOrderKeys.indexOf(currentKey ?? '');
      if (currentOrderIndex > 0) {
        return _queueIndexForCacheKey(_shuffleOrderKeys[currentOrderIndex - 1]);
      }
      if (_loopMode == LoopMode.all && _shuffleOrderKeys.isNotEmpty) {
        return _queueIndexForCacheKey(_shuffleOrderKeys.last);
      }
      return null;
    }

    final sequentialPrevious = _currentIndex - 1;
    if (sequentialPrevious >= 0) {
      return sequentialPrevious;
    }

    if (_loopMode == LoopMode.all) {
      return _queue.length - 1;
    }

    return null;
  }

  Future<void> _stopUnlocked({required bool clearLoadedTrack}) async {
    await _player.stop();
    _isPlaying = false;
    _processingState = ProcessingState.idle;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _clearLoadingState(notify: false);
    if (clearLoadedTrack) {
      _loadedTrackKey = null;
    }
  }

  Future<T?> _runPlayerCommand<T>(
    String action,
    Future<T> Function() command, {
    String? failureMessage,
    MusicTrack? track,
    bool markLoading = false,
  }) {
    final completer = Completer<T?>();
    final subject = track ?? currentTrack;

    _commandChain = _commandChain
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[Audio] Previous command failed: $error');
          debugPrint('$stackTrace');
        })
        .then((_) async {
          if (_disposed) {
            completer.complete(null);
            return;
          }

          await _initialization;
          _activeCommandTrackId = subject?.id;
          _activeCommandAction = action;
          if (markLoading && subject != null) {
            _loadingTrackId = subject.id;
          }
          _clearError(notify: false);
          notifyListeners();

          debugPrint(
            '[Audio] Starting $action'
            ' | trackId=${subject?.id ?? 'none'}'
            ' | title=${subject?.title ?? 'none'}'
            ' | sourceType=${subject == null ? 'none' : _sourceTypeForTrack(subject)}'
            ' | source=${subject == null ? 'n/a' : _streamOrPathForTrack(subject)}'
            ' | queueLength=${_queue.length}'
            ' | currentIndex=$_currentIndex'
            ' | playerState=$_processingState'
            ' | platform=$_platformLabel'
            ' | isPlaying=$_isPlaying',
          );

          try {
            final result = await command();
            debugPrint(
              '[Audio] Completed $action'
              ' | trackId=${subject?.id ?? 'none'}'
              ' | queueLength=${_queue.length}'
              ' | playerState=$_processingState'
              ' | platform=$_platformLabel'
              ' | isPlaying=$_isPlaying',
            );
            completer.complete(result);
          } catch (error, stackTrace) {
            debugPrint(
              '[Audio] Failed to $action'
              ' | trackId=${subject?.id ?? 'none'}'
              ' | title=${subject?.title ?? 'none'}'
              ' | sourceType=${subject == null ? 'none' : _sourceTypeForTrack(subject)}'
              ' | source=${subject == null ? 'n/a' : _streamOrPathForTrack(subject)}'
              ' | queueLength=${_queue.length}'
              ' | playerState=$_processingState'
              ' | platform=$_platformLabel'
              ' | exception=$error',
            );
            debugPrint('$stackTrace');
            _logErrorDetails(error, track: subject, context: action);
            _clearLoadingState(trackId: subject?.id, notify: false);
            _recordError(
              _messageForCommandFailure(
                error,
                action: action,
                track: subject,
                fallbackMessage: failureMessage,
              ),
            );
            completer.complete(null);
          } finally {
            _activeCommandAction = null;
            _activeCommandTrackId = null;
            if (!_disposed) {
              notifyListeners();
            }
          }
        });

    return completer.future;
  }

  void _announceTrackChange() {
    onTrackChanged?.call(currentTrack);
    notifyListeners();
  }

  void _recordError(String message) {
    _lastErrorMessage = message;
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _clearError({bool notify = true}) {
    if (_lastErrorMessage == null) {
      return;
    }
    _lastErrorMessage = null;
    if (notify && !_disposed) {
      notifyListeners();
    }
  }

  String get _platformLabel {
    if (kIsWeb) {
      return 'web';
    }
    if (Platform.isWindows) {
      return 'windows';
    }
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isIOS) {
      return 'ios';
    }
    if (Platform.isMacOS) {
      return 'macos';
    }
    if (Platform.isLinux) {
      return 'linux';
    }
    return 'unknown';
  }

  String _messageForCommandFailure(
    Object error, {
    required String action,
    MusicTrack? track,
    String? fallbackMessage,
  }) {
    final trackLabel = track == null ? 'this track' : track.title;

    if (error is MissingPluginException ||
        error.toString().contains('MissingPluginException')) {
      return 'Audio playback is not ready on $_platformLabel yet. '
          'Rebuild Crabify and make sure the audio plugins are registered for this platform.';
    }

    if (error is PlayerException) {
      final detail = _cleanErrorText(error.message);
      final codeSuffix = error.code > 0 ? ' (player code ${error.code})' : '';
      return detail.isEmpty
          ? 'Crabify could not $action for $trackLabel$codeSuffix.'
          : 'Crabify could not $action for $trackLabel: $detail$codeSuffix';
    }

    if (error is PlayerInterruptedException) {
      final detail = _cleanErrorText(error.message);
      return detail.isEmpty
          ? 'Playback for $trackLabel was interrupted while loading.'
          : 'Playback for $trackLabel was interrupted while loading: $detail';
    }

    if (error is FileSystemException) {
      final detail = _cleanErrorText(error.message);
      return detail.isEmpty
          ? 'Crabify could not open the local file for $trackLabel.'
          : 'Crabify could not open the local file for $trackLabel: $detail';
    }

    if (error is PlatformException) {
      final detail = _cleanErrorText(error.message);
      final detailsText = _cleanErrorText(error.details?.toString());
      final mergedDetail = <String>[
        if (detail.isNotEmpty) detail,
        if (detailsText.isNotEmpty && detailsText != detail) detailsText,
      ].join(' | ');

      return mergedDetail.isEmpty
          ? 'Crabify could not $action for $trackLabel.'
          : 'Crabify could not $action for $trackLabel: $mergedDetail';
    }

    final detail = _cleanErrorText(error.toString());
    if (detail.isNotEmpty) {
      return detail;
    }

    return fallbackMessage ?? 'Unable to $action right now.';
  }

  bool _shouldRetryRemoteLoad(Object error) {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }
    return error is PlayerException || error is PlatformException;
  }

  void _logErrorDetails(
    Object error, {
    MusicTrack? track,
    required String context,
  }) {
    if (error is PlayerException) {
      debugPrint(
        '[Audio] PlayerException details'
        ' | context=$context'
        ' | platform=$_platformLabel'
        ' | trackId=${track?.id ?? 'none'}'
        ' | title=${track?.title ?? 'none'}'
        ' | code=${error.code}'
        ' | index=${error.index}'
        ' | message=${error.message}',
      );
      return;
    }

    if (error is PlatformException) {
      debugPrint(
        '[Audio] PlatformException details'
        ' | context=$context'
        ' | platform=$_platformLabel'
        ' | trackId=${track?.id ?? 'none'}'
        ' | title=${track?.title ?? 'none'}'
        ' | code=${error.code}'
        ' | message=${error.message}'
        ' | details=${error.details}',
      );
    }
  }

  void _clearLoadingState({String? trackId, bool notify = true}) {
    if (_loadingTrackId == null) {
      return;
    }
    if (trackId != null && _loadingTrackId != trackId) {
      return;
    }
    _loadingTrackId = null;
    if (notify && !_disposed) {
      notifyListeners();
    }
  }

  void _refreshShuffleOrder({
    bool moveCurrentToFront = false,
    bool reshuffleTail = false,
  }) {
    if (!_shuffleEnabled || _queue.isEmpty) {
      _shuffleOrderKeys.clear();
      return;
    }

    final queueKeys = _queue.map((track) => track.cacheKey).toList();
    final currentKey = currentTrack?.cacheKey;
    final retainedTail =
        reshuffleTail
            ? <String>[]
            : _shuffleOrderKeys.where(queueKeys.contains).toList();
    final missingKeys =
        queueKeys.where((key) => !retainedTail.contains(key)).toList()
          ..shuffle(_random);

    final nextOrder = <String>[...retainedTail, ...missingKeys];
    if (moveCurrentToFront &&
        currentKey != null &&
        queueKeys.contains(currentKey)) {
      nextOrder.remove(currentKey);
      nextOrder.insert(0, currentKey);
    }

    _shuffleOrderKeys
      ..clear()
      ..addAll(nextOrder);
  }

  int? _queueIndexForCacheKey(String? cacheKey) {
    if (cacheKey == null) {
      return null;
    }
    final index = _queue.indexWhere((track) => track.cacheKey == cacheKey);
    return index < 0 ? null : index;
  }

  String _cleanErrorText(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) {
      return '';
    }
    return text
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .replaceFirst('Invalid argument(s): ', '');
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    unawaited(
      _player.dispose().catchError((Object error, StackTrace stackTrace) {
        debugPrint(
          '[Audio] Failed to dispose player'
          ' | platform=$_platformLabel'
          ' | exception=$error',
        );
        debugPrint('$stackTrace');
      }),
    );
    super.dispose();
  }
}

class _PreparedQueue {
  const _PreparedQueue({required this.tracks, required this.initialIndex});

  final List<MusicTrack> tracks;
  final int initialIndex;
}
