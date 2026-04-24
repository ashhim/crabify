import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/music_track.dart';
import 'audius_api_service.dart';

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
  String? _activeTrackId;
  bool _isBusy = false;
  bool _disposed = false;
  bool _handlingCompletion = false;

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
  bool get isBusy => _isBusy;
  String? get activeTrackId => _activeTrackId;

  Future<void> setQueue(
    List<MusicTrack> tracks, {
    String? initialTrackId,
    int initialIndex = 0,
    bool autoPlay = true,
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
      () async {
        _queue = preparedQueue.tracks;
        _currentIndex = preparedQueue.initialIndex;
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
          final insertIndex = _currentIndex < 0 ? _queue.length : _currentIndex + 1;
          _queue.insert(insertIndex, track);
        }
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
      () async {
        final wasCurrentTrack = index == _currentIndex;
        final shouldResume = _isPlaying;
        _queue.removeAt(index);

        if (_queue.isEmpty) {
          _currentIndex = -1;
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
      () async {
        if (_currentIndex < 0) {
          _currentIndex = 0;
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

        await _player.play();
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
      _player.playerStateStream.listen((state) {
        _isPlaying = state.playing;
        _processingState = state.processingState;

        if (state.processingState == ProcessingState.completed &&
            !_handlingCompletion) {
          _handlingCompletion = true;
          unawaited(_handleTrackCompletion());
        }

        notifyListeners();
      }),
    );

    debugPrint('[Audio] Player initialized. state=$_processingState');
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
          failureMessage: 'Playback ended, but Crabify could not reset cleanly.',
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

    final source = _sourceForTrack(track);
    final trackKey = _trackLoadKey(track);
    final shouldReload =
        forceReload || _loadedTrackKey != trackKey || _processingState == ProcessingState.idle;

    debugPrint(
      '[Audio] Loading track'
      ' | id=${track.id}'
      ' | title=${track.title}'
      ' | stream=${_streamUrlForTrack(track)}'
      ' | queueLength=${_queue.length}'
      ' | currentIndex=$_currentIndex'
      ' | playerState=$_processingState'
      ' | reason=$reason',
    );

    if (shouldReload) {
      await _player.stop();
      _position = Duration.zero;
      _bufferedPosition = Duration.zero;
      _duration = track.duration;
      notifyListeners();
      await _player.setAudioSource(source);
      _loadedTrackKey = trackKey;
    }

    if (autoPlay) {
      await _player.play();
    }
  }

  AudioSource _sourceForTrack(MusicTrack track) {
    final uri = track.isLocal
        ? Uri.file(track.localPath!)
        : Uri.parse(_streamUrlForTrack(track));
    final artUri = switch ((track.artworkPath, track.artworkUrl)) {
      (String path, _) when path.isNotEmpty => Uri.file(path),
      (_, String url) when url.isNotEmpty => Uri.parse(url),
      _ => null,
    };

    return AudioSource.uri(
      uri,
      tag: MediaItem(
        id: track.id,
        album: track.albumTitle,
        title: track.title,
        artist: track.artistName,
        artUri: artUri,
        playable: true,
      ),
    );
  }

  String _streamUrlForTrack(MusicTrack track) {
    return track.isLocal ? track.localPath! : _audiusApiService.resolveStreamUrl(track);
  }

  String _trackLoadKey(MusicTrack track) {
    return track.isLocal
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
    if (!track.isPlayable || !track.hasValidId) {
      return false;
    }

    if (track.isLocal) {
      return true;
    }

    return track.hasValidRemoteSource;
  }

  _PreparedQueue? _prepareQueue(
    List<MusicTrack> tracks, {
    String? initialTrackId,
    required int initialIndex,
  }) {
    final playableTracks =
        tracks.where(_canQueueTrack).fold<List<MusicTrack>>(<MusicTrack>[], (
          result,
          track,
        ) {
          final alreadyPresent = result.any(
            (existing) => existing.cacheKey == track.cacheKey,
          );
          if (!alreadyPresent) {
            result.add(track);
          }
          return result;
        });

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
      final candidates = List<int>.generate(_queue.length, (index) => index)
        ..remove(_currentIndex);
      return candidates[_random.nextInt(candidates.length)];
    }

    final sequentialNext = _currentIndex + 1;
    if (sequentialNext < _queue.length) {
      return sequentialNext;
    }

    if (_loopMode == LoopMode.all || onCompletion && _loopMode == LoopMode.all) {
      return 0;
    }

    return null;
  }

  int? _computePreviousIndex() {
    if (_queue.isEmpty || _currentIndex < 0) {
      return null;
    }

    if (_shuffleEnabled && _queue.length > 1) {
      final candidates = List<int>.generate(_queue.length, (index) => index)
        ..remove(_currentIndex);
      return candidates[_random.nextInt(candidates.length)];
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
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    if (clearLoadedTrack) {
      _loadedTrackKey = null;
    }
  }

  Future<T?> _runPlayerCommand<T>(
    String action,
    Future<T> Function() command, {
    String? failureMessage,
    MusicTrack? track,
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
          _activeTrackId = subject?.id;
          _isBusy = true;
          _clearError(notify: false);
          notifyListeners();

          debugPrint(
            '[Audio] Starting $action'
            ' | trackId=${subject?.id ?? 'none'}'
            ' | title=${subject?.title ?? 'none'}'
            ' | streamUrl=${subject == null ? 'n/a' : _streamUrlForTrack(subject)}'
            ' | queueLength=${_queue.length}'
            ' | currentIndex=$_currentIndex'
            ' | playerState=$_processingState'
            ' | isPlaying=$_isPlaying',
          );

          try {
            final result = await command();
            debugPrint(
              '[Audio] Completed $action'
              ' | trackId=${subject?.id ?? 'none'}'
              ' | queueLength=${_queue.length}'
              ' | playerState=$_processingState'
              ' | isPlaying=$_isPlaying',
            );
            completer.complete(result);
          } catch (error, stackTrace) {
            debugPrint(
              '[Audio] Failed to $action'
              ' | trackId=${subject?.id ?? 'none'}'
              ' | title=${subject?.title ?? 'none'}'
              ' | streamUrl=${subject == null ? 'n/a' : _streamUrlForTrack(subject)}'
              ' | queueLength=${_queue.length}'
              ' | playerState=$_processingState'
              ' | exception=$error',
            );
            debugPrint('$stackTrace');
            _recordError(failureMessage ?? 'Unable to $action right now.');
            completer.complete(null);
          } finally {
            _isBusy = false;
            _activeTrackId = null;
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

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}

class _PreparedQueue {
  const _PreparedQueue({required this.tracks, required this.initialIndex});

  final List<MusicTrack> tracks;
  final int initialIndex;
}
