import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/music_track.dart';
import 'audius_api_service.dart';
import 'notification_artwork_service.dart';

enum PlaybackViewState { idle, loading, playing, paused, stopped, error }
enum TrackRepeatMode { off, once, loop }

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
  final Set<VoidCallback> _backgroundStateListeners = <VoidCallback>{};

  late final Future<void> _initialization;
  Future<void> _commandChain = Future<void>.value();

  List<MusicTrack> _queue = <MusicTrack>[];
  List<String> _queueEntryIds = <String>[];
  int _currentIndex = -1;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration? _duration;
  bool _isPlaying = false;
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  TrackRepeatMode _repeatMode = TrackRepeatMode.off;
  ProcessingState _processingState = ProcessingState.idle;
  String? _lastErrorMessage;
  String? _loadedTrackKey;
  String? _activeCommandTrackId;
  String? _activeCommandAction;
  String? _loadingTrackId;
  bool _disposed = false;
  bool _handlingCompletion = false;
  Duration? _pendingRestorePosition;
  String? _pendingRestoreTrackId;
  final List<String> _shuffleOrderKeys = <String>[];
  DateTime _lastUiProgressNotificationAt = DateTime.fromMillisecondsSinceEpoch(
    0,
  );
  DateTime _lastBackgroundProgressNotificationAt =
      DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastUiNotifiedPosition = Duration.zero;
  Duration _lastUiNotifiedBufferedPosition = Duration.zero;
  Duration _lastBackgroundNotifiedPosition = Duration.zero;
  int _queueEntrySeed = 0;
  int _queueVersion = 0;

  static const Duration _loadTimeout = Duration(seconds: 12);
  static const Duration _uiProgressNotificationInterval = Duration(
    milliseconds: 300,
  );
  static const Duration _backgroundProgressNotificationInterval = Duration(
    seconds: 15,
  );
  static const Duration _bufferedPositionThreshold = Duration(
    milliseconds: 750,
  );

  void Function(MusicTrack? track)? onTrackChanged;

  List<MusicTrack> get queue => List<MusicTrack>.unmodifiable(_queue);
  String queueEntryIdAt(int index) =>
      index >= 0 && index < _queueEntryIds.length
          ? _queueEntryIds[index]
          : 'queue-entry-$index';
  MusicTrack? get currentTrack =>
      _currentIndex < 0 || _currentIndex >= _queue.length
          ? null
          : _queue[_currentIndex];
  int get currentIndex => _currentIndex;
  int get queueVersion => _queueVersion;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition;
  Duration get duration => _duration ?? currentTrack?.duration ?? Duration.zero;
  bool get isPlaying => _isPlaying;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get loopMode => _loopMode;
  TrackRepeatMode get repeatMode => _repeatMode;
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

  Map<String, dynamic>? exportSessionState() {
    final track = currentTrack;
    if (track == null || _queue.isEmpty || _currentIndex < 0) {
      return null;
    }

    return <String, dynamic>{
      'queue': _queue.map((track) => track.toJson()).toList(),
      'currentTrackId': track.id,
      'currentTrackCacheKey': track.cacheKey,
      'currentIndex': _currentIndex,
      'positionMillis': _position.inMilliseconds,
      'shuffleEnabled': _shuffleEnabled,
      'loopMode': _loopMode.name,
      'repeatMode': _repeatMode.name,
      'isPlaying': _isPlaying,
    };
  }

  Future<void> restoreSession({
    required List<MusicTrack> tracks,
    required String? currentTrackId,
    required String? currentTrackCacheKey,
    required int? currentIndex,
    required Duration position,
    required bool shuffleEnabled,
    required LoopMode loopMode,
    TrackRepeatMode repeatMode = TrackRepeatMode.off,
  }) async {
    await _initialization;
    if (_disposed || tracks.isEmpty) {
      return;
    }

    var resolvedIndex = currentIndex ?? 0;
    if (currentTrackCacheKey != null) {
      final locatedIndex = tracks.indexWhere(
        (track) => track.cacheKey == currentTrackCacheKey,
      );
      if (locatedIndex >= 0) {
        resolvedIndex = locatedIndex;
      }
    } else if (currentTrackId != null) {
      final locatedIndex = tracks.indexWhere((track) => track.id == currentTrackId);
      if (locatedIndex >= 0) {
        resolvedIndex = locatedIndex;
      }
    }
    resolvedIndex = resolvedIndex.clamp(0, tracks.length - 1);

    _queue = List<MusicTrack>.from(tracks);
    _queueEntryIds = List<String>.generate(
      tracks.length,
      (index) => _newQueueEntryId(tracks[index]),
    );
    _bumpQueueVersion();
    _currentIndex = resolvedIndex;
    _shuffleEnabled = shuffleEnabled;
    _repeatMode =
        repeatMode == TrackRepeatMode.off && loopMode == LoopMode.one
            ? TrackRepeatMode.loop
            : repeatMode;
    _loopMode = switch (_repeatMode) {
      TrackRepeatMode.off => LoopMode.off,
      TrackRepeatMode.once || TrackRepeatMode.loop => LoopMode.one,
    };
    await _player.setLoopMode(_loopMode);
    _isPlaying = false;
    _processingState = ProcessingState.idle;
    _loadedTrackKey = null;
    _bufferedPosition = Duration.zero;
    _duration = currentTrack?.duration;
    _position = _clampRestorePosition(position, currentTrack?.duration);
    _pendingRestoreTrackId = currentTrack?.id;
    _pendingRestorePosition = _position > Duration.zero ? _position : null;
    _refreshShuffleOrder(
      moveCurrentToFront: _shuffleEnabled,
      reshuffleTail: false,
    );
    _clearError(notify: false);
    _notifyUiListeners();
    _notifyBackgroundStateListeners();
  }

  void addBackgroundStateListener(VoidCallback listener) {
    _backgroundStateListeners.add(listener);
  }

  void removeBackgroundStateListener(VoidCallback listener) {
    _backgroundStateListeners.remove(listener);
  }

  Future<void> setQueue(
    List<MusicTrack> tracks, {
    String? initialTrackId,
    String? initialTrackCacheKey,
    int initialIndex = 0,
    bool autoPlay = true,
    bool shuffle = false,
  }) async {
    final preparedQueue = _prepareQueue(
      tracks,
      initialTrackId: initialTrackId,
      initialTrackCacheKey: initialTrackCacheKey,
      initialIndex: initialIndex,
    );

    if (preparedQueue == null) {
      _recordError('No playable tracks are available in this queue.');
      return;
    }

    final effectiveQueue =
        shuffle ? _shufflePreparedQueue(preparedQueue) : preparedQueue;

    final previousQueue = List<MusicTrack>.from(_queue);
    final previousQueueEntryIds = List<String>.from(_queueEntryIds);
    final previousIndex = _currentIndex;
    final previousLoadedTrackKey = _loadedTrackKey;
    final previousShuffleEnabled = _shuffleEnabled;
    final previousWasPlaying = _isPlaying;
    final previousPosition = _position;
    final selectedTrack = effectiveQueue.tracks[effectiveQueue.initialIndex];

    final started = await _runPlayerCommand<bool>(
      'set queue',
      track: selectedTrack,
      markLoading: true,
      () async {
        _queue = effectiveQueue.tracks;
        _queueEntryIds = effectiveQueue.entryIds;
        _bumpQueueVersion();
        _currentIndex = effectiveQueue.initialIndex;
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
    _queueEntryIds = previousQueueEntryIds;
    _bumpQueueVersion();
    _currentIndex = previousIndex;
    _loadedTrackKey = previousLoadedTrackKey;
    _shuffleEnabled = previousShuffleEnabled;
    _refreshShuffleOrder(
      moveCurrentToFront: _shuffleEnabled,
      reshuffleTail: false,
    );
    await _restorePlaybackSnapshot(
      reason: 'setQueue-rollback',
      resumePlayback: previousWasPlaying,
      preservePosition: previousPosition,
    );
    _notifyUiListeners();
    _notifyBackgroundStateListeners();
  }

  Future<void> addToQueue(MusicTrack track) async {
    if (!_canQueueTrack(track)) {
      _recordError('${track.title} is not available for playback.');
      return;
    }

    final previousQueue = List<MusicTrack>.from(_queue);
    final previousQueueEntryIds = List<String>.from(_queueEntryIds);
    final previousIndex = _currentIndex;
    final previousLoadedTrackKey = _loadedTrackKey;
    final previousWasPlaying = _isPlaying;
    final previousPosition = _position;

    final added = await _runPlayerCommand<bool>(
      'add to queue',
      track: track,
      () async {
        final hadActiveTrack = currentTrack != null && _loadedTrackKey != null;
        final canMutateQueueInPlace = hadActiveTrack && _canUseLoadedQueuePlaylist;
        if (_queue.isEmpty) {
          _queue = <MusicTrack>[track];
          _queueEntryIds = <String>[_newQueueEntryId(track)];
          _bumpQueueVersion();
          _currentIndex = -1;
        } else {
          final insertIndex =
              _currentIndex < 0 ? _queue.length : _currentIndex + 1;
          _queue.insert(insertIndex, track);
          _queueEntryIds.insert(insertIndex, _newQueueEntryId(track));
          _bumpQueueVersion();
          if (canMutateQueueInPlace) {
            final source = await _audioSourceForTrack(track);
            if (source != null) {
              await _player.insertAudioSource(insertIndex, source);
            }
          }
        }
        _refreshShuffleOrder();
        if (hadActiveTrack && _queue.isNotEmpty && !canMutateQueueInPlace) {
          await _syncActiveQueueState(
            reason: 'addToQueue',
            resumePlayback: _isPlaying,
            preservePosition: _position,
          );
        }
        return true;
      },
      failureMessage: 'Unable to add ${track.title} to the queue.',
    );

    if (added != true) {
      _queue = previousQueue;
      _queueEntryIds = previousQueueEntryIds;
      _bumpQueueVersion();
      _currentIndex = previousIndex;
      _loadedTrackKey = previousLoadedTrackKey;
      _refreshShuffleOrder(
        moveCurrentToFront: _shuffleEnabled,
        reshuffleTail: false,
      );
      await _restorePlaybackSnapshot(
        reason: 'addToQueue-rollback',
        resumePlayback: previousWasPlaying,
        preservePosition: previousPosition,
      );
      _notifyUiListeners();
      _notifyBackgroundStateListeners();
    }
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }

    final previousQueue = List<MusicTrack>.from(_queue);
    final previousQueueEntryIds = List<String>.from(_queueEntryIds);
    final previousIndex = _currentIndex;
    final previousLoadedTrackKey = _loadedTrackKey;
    final previousWasPlaying = _isPlaying;
    final previousPosition = _position;
    final removedTrack = _queue[index];

    final removed = await _runPlayerCommand<bool>(
      'remove a queue item',
      track: removedTrack,
      markLoading: index == _currentIndex,
      () async {
        final wasCurrentTrack = index == _currentIndex;
        final shouldResume = _isPlaying;
        final preservePosition = _position;
        final canMutateQueueInPlace = !wasCurrentTrack && _canUseLoadedQueuePlaylist;
        _queue.removeAt(index);
        _queueEntryIds.removeAt(index);
        _bumpQueueVersion();

        if (_queue.isEmpty) {
          _currentIndex = -1;
          _refreshShuffleOrder();
          await _stopUnlocked(clearLoadedTrack: true);
          _announceTrackChange();
          return true;
        }

        if (index < _currentIndex) {
          _currentIndex -= 1;
          _refreshShuffleOrder();
          if (canMutateQueueInPlace) {
            await _player.removeAudioSourceAt(index);
          } else {
            await _syncActiveQueueState(
              reason: 'removeAt-shift-current',
              resumePlayback: shouldResume,
              preservePosition: preservePosition,
            );
          }
          return true;
        }

        if (!wasCurrentTrack) {
          _refreshShuffleOrder();
          if (canMutateQueueInPlace) {
            await _player.removeAudioSourceAt(index);
          } else {
            await _syncActiveQueueState(
              reason: 'removeAt-noncurrent',
              resumePlayback: shouldResume,
              preservePosition: preservePosition,
            );
          }
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
      _queueEntryIds = previousQueueEntryIds;
      _bumpQueueVersion();
      _currentIndex = previousIndex;
      _loadedTrackKey = previousLoadedTrackKey;
      _refreshShuffleOrder(
        moveCurrentToFront: _shuffleEnabled,
        reshuffleTail: false,
      );
      await _restorePlaybackSnapshot(
        reason: 'removeAt-rollback',
        resumePlayback: previousWasPlaying,
        preservePosition: previousPosition,
      );
      _notifyUiListeners();
      _notifyBackgroundStateListeners();
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

    final previousQueue = List<MusicTrack>.from(_queue);
    final previousQueueEntryIds = List<String>.from(_queueEntryIds);
    final previousIndex = _currentIndex;
    final previousLoadedTrackKey = _loadedTrackKey;
    final previousWasPlaying = _isPlaying;
    final previousPosition = _position;

    final moved = await _runPlayerCommand<bool>(
      'reorder the queue',
      track: currentTrack,
      () async {
        final resumePlayback = _isPlaying;
        final preservePosition = _position;
        final canMutateQueueInPlace = _canUseLoadedQueuePlaylist;
        final track = _queue.removeAt(oldIndex);
        final entryId = _queueEntryIds.removeAt(oldIndex);
        _queue.insert(adjustedIndex, track);
        _queueEntryIds.insert(adjustedIndex, entryId);
        _bumpQueueVersion();

        if (_currentIndex == oldIndex) {
          _currentIndex = adjustedIndex;
        } else if (oldIndex < _currentIndex && adjustedIndex >= _currentIndex) {
          _currentIndex -= 1;
        } else if (oldIndex > _currentIndex && adjustedIndex <= _currentIndex) {
          _currentIndex += 1;
        }
        _refreshShuffleOrder();
        if (canMutateQueueInPlace) {
          await _player.moveAudioSource(oldIndex, adjustedIndex);
        } else {
          await _syncActiveQueueState(
            reason: 'moveQueueItem',
            resumePlayback: resumePlayback,
            preservePosition: preservePosition,
          );
        }
        return true;
      },
      failureMessage: 'Unable to reorder the queue right now.',
    );

    if (moved != true) {
      _queue = previousQueue;
      _queueEntryIds = previousQueueEntryIds;
      _bumpQueueVersion();
      _currentIndex = previousIndex;
      _loadedTrackKey = previousLoadedTrackKey;
      _refreshShuffleOrder(
        moveCurrentToFront: _shuffleEnabled,
        reshuffleTail: false,
      );
      await _restorePlaybackSnapshot(
        reason: 'moveQueueItem-rollback',
        resumePlayback: previousWasPlaying,
        preservePosition: previousPosition,
      );
      _notifyUiListeners();
      _notifyBackgroundStateListeners();
    }
  }

  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }

    final selectedTrack = _queue[index];
    final previousIndex = _currentIndex;
    final previousLoadedTrackKey = _loadedTrackKey;
    final previousWasPlaying = _isPlaying;
    final previousPosition = _position;
    final started = await _runPlayerCommand<bool>(
      'play the selected queue item',
      track: selectedTrack,
      markLoading: true,
      () async {
        await _switchToQueueIndex(index, reason: 'playFromQueue');
        return true;
      },
      failureMessage: 'Unable to play ${selectedTrack.title}.',
    );

    if (started == true) {
      _announceTrackChange();
      return;
    }

    _currentIndex = previousIndex;
    _loadedTrackKey = previousLoadedTrackKey;
    await _restorePlaybackSnapshot(
      reason: 'playFromQueue-rollback',
      resumePlayback: previousWasPlaying,
      preservePosition: previousPosition,
    );
    _notifyUiListeners();
    _notifyBackgroundStateListeners();
  }

  void refreshTrackMetadata(MusicTrack updatedTrack) {
    var changed = false;
    final previousCurrentTrack = currentTrack;
    _queue =
        _queue.map((track) {
          if (track.id != updatedTrack.id) {
            return track;
          }
          changed = true;
          return _mergeTrackMetadataPreservingSource(track, updatedTrack);
        }).toList();

    if (!changed) {
      return;
    }
    _bumpQueueVersion();

    if (previousCurrentTrack?.id == updatedTrack.id) {
      final resumePlayback = _isPlaying;
      final preservePosition = _position;
      unawaited(
        _runPlayerCommand<void>(
          'refresh current track metadata',
          track: currentTrack,
          () => _syncActiveQueueState(
            reason: 'refreshTrackMetadata',
            resumePlayback: resumePlayback,
            preservePosition: preservePosition,
          ),
          failureMessage: 'Unable to refresh the current track metadata.',
        ),
      );
      _announceTrackChange();
      return;
    }

    _notifyUiListeners();
    _notifyBackgroundStateListeners();
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
    final previousIndex = _currentIndex;
    final previousLoadedTrackKey = _loadedTrackKey;
    final previousWasPlaying = _isPlaying;
    final previousPosition = _position;
    final advanced = await _runPlayerCommand<bool>(
      'skip to the next track',
      track: track,
      markLoading: true,
      () async {
        await _switchToQueueIndex(nextIndex, reason: 'next');
        return true;
      },
      failureMessage: 'Unable to skip to the next track.',
    );

    if (advanced == true) {
      _announceTrackChange();
      return;
    }

    _currentIndex = previousIndex;
    _loadedTrackKey = previousLoadedTrackKey;
    await _restorePlaybackSnapshot(
      reason: 'next-rollback',
      resumePlayback: previousWasPlaying,
      preservePosition: previousPosition,
    );
    _notifyUiListeners();
    _notifyBackgroundStateListeners();
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
    final existingIndex = _currentIndex;
    final previousLoadedTrackKey = _loadedTrackKey;
    final previousWasPlaying = _isPlaying;
    final previousPosition = _position;
    final moved = await _runPlayerCommand<bool>(
      'return to the previous track',
      track: track,
      markLoading: true,
      () async {
        await _switchToQueueIndex(previousIndex, reason: 'previous');
        return true;
      },
      failureMessage: 'Unable to return to the previous track.',
    );

    if (moved == true) {
      _announceTrackChange();
      return;
    }

    _currentIndex = existingIndex;
    _loadedTrackKey = previousLoadedTrackKey;
    await _restorePlaybackSnapshot(
      reason: 'previous-rollback',
      resumePlayback: previousWasPlaying,
      preservePosition: previousPosition,
    );
    _notifyUiListeners();
    _notifyBackgroundStateListeners();
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
    if (_queue.isEmpty) {
      return;
    }

    final previousQueue = List<MusicTrack>.from(_queue);
    final previousQueueEntryIds = List<String>.from(_queueEntryIds);
    final previousIndex = _currentIndex;
    final previousLoadedTrackKey = _loadedTrackKey;
    final previousShuffleEnabled = _shuffleEnabled;
    final previousWasPlaying = _isPlaying;
    final previousPosition = _position;

    final shuffled = await _runPlayerCommand<bool>(
      'toggle shuffle',
      track: currentTrack,
      () async {
        if (_queue.length <= 1) {
          _shuffleEnabled = true;
          _refreshShuffleOrder(moveCurrentToFront: true, reshuffleTail: true);
          return true;
        }

        final currentCacheKey = currentTrack?.cacheKey;
        if (currentCacheKey == null) {
          return false;
        }

        final resumePlayback = _isPlaying;
        final queueEntries = List.generate(
          _queue.length,
          (index) => (
            track: _queue[index],
            entryId: _queueEntryIds[index],
          ),
        );
        final candidateStartIndexes =
            List<int>.generate(queueEntries.length, (index) => index)
              ..removeWhere(
                (index) =>
                    queueEntries[index].track.cacheKey == currentCacheKey,
              );
        final startIndex =
            candidateStartIndexes.isEmpty
                ? 0
                : candidateStartIndexes[
                  _random.nextInt(candidateStartIndexes.length)
                ];
        final startEntry = queueEntries.removeAt(startIndex);
        queueEntries.shuffle(_random);
        queueEntries.insert(0, startEntry);

        _queue =
            queueEntries.map((entry) => entry.track).toList(growable: false);
        _queueEntryIds =
            queueEntries.map((entry) => entry.entryId).toList(growable: false);
        _bumpQueueVersion();
        _currentIndex = 0;
        _shuffleEnabled = true;
        _refreshShuffleOrder(
          moveCurrentToFront: true,
          reshuffleTail: true,
        );
        await _syncActiveQueueState(
          reason: 'toggleShuffle',
          resumePlayback: resumePlayback,
          preservePosition: Duration.zero,
        );
        return true;
      },
      failureMessage: 'Unable to toggle shuffle right now.',
    );

    if (shuffled != true) {
      _queue = previousQueue;
      _queueEntryIds = previousQueueEntryIds;
      _bumpQueueVersion();
      _currentIndex = previousIndex;
      _loadedTrackKey = previousLoadedTrackKey;
      _shuffleEnabled = previousShuffleEnabled;
      _refreshShuffleOrder(
        moveCurrentToFront: _shuffleEnabled,
        reshuffleTail: false,
      );
      await _restorePlaybackSnapshot(
        reason: 'toggleShuffle-rollback',
        resumePlayback: previousWasPlaying,
        preservePosition: previousPosition,
      );
      _notifyUiListeners();
      _notifyBackgroundStateListeners();
    }
  }

  Future<void> cycleLoopMode() async {
    await _runPlayerCommand<void>(
      'change repeat mode',
      track: currentTrack,
      () async {
        _repeatMode = switch (_repeatMode) {
          TrackRepeatMode.off => TrackRepeatMode.once,
          TrackRepeatMode.once => TrackRepeatMode.loop,
          TrackRepeatMode.loop => TrackRepeatMode.off,
        };
        _loopMode = switch (_repeatMode) {
          TrackRepeatMode.off => LoopMode.off,
          TrackRepeatMode.once || TrackRepeatMode.loop => LoopMode.one,
        };
        await _player.setLoopMode(_loopMode);
      },
      failureMessage: 'Unable to change repeat mode right now.',
    );
  }

  Future<void> _initialize() async {
    debugPrint('[Audio] Initializing player on $_platformLabel');
    await _player.setLoopMode(_loopMode);

    _subscriptions.add(
      _player.positionStream.listen((position) {
        _position = position;
        if (_shouldNotifyUiProgress(position)) {
          _notifyUiListeners();
        }
        if (_shouldNotifyBackgroundProgress(position)) {
          _notifyBackgroundStateListeners();
        }
      }),
    );

    _subscriptions.add(
      _player.bufferedPositionStream.listen((position) {
        _bufferedPosition = position;
        if (_shouldNotifyBufferedProgress(position)) {
          _notifyUiListeners();
        }
      }),
    );

    _subscriptions.add(
      _player.durationStream.listen((duration) {
        if (_duration == duration) {
          return;
        }
        _duration = duration;
        _notifyUiListeners();
        _notifyBackgroundStateListeners();
      }),
    );

    _subscriptions.add(
      _player.currentIndexStream.listen((index) {
        if (index == null || index < 0 || index >= _queue.length) {
          return;
        }
        if (index == _currentIndex) {
          return;
        }
        _currentIndex = index;
        final track = currentTrack;
        _loadedTrackKey = track == null ? null : _trackLoadKey(track);
        _duration = track?.duration;
        _clearLoadingState(trackId: track?.id, notify: false);
        _announceTrackChange();
      }),
    );

    _subscriptions.add(
      _player.positionDiscontinuityStream.listen((discontinuity) {
        if (_repeatMode != TrackRepeatMode.once ||
            discontinuity.reason != PositionDiscontinuityReason.autoAdvance ||
            currentTrack == null) {
          return;
        }

        _repeatMode = TrackRepeatMode.off;
        _loopMode = LoopMode.off;
        unawaited(_player.setLoopMode(LoopMode.off));
        _notifyUiListeners();
        _notifyBackgroundStateListeners();
      }),
    );

    _subscriptions.add(
      _player.errorStream.listen((error) {
        if (_isInterruptedLoadError(error)) {
          return;
        }
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
        final previousPlaying = _isPlaying;
        final previousProcessingState = _processingState;
        final previousLoadingTrackId = _loadingTrackId;
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

        if (previousPlaying != _isPlaying ||
            previousProcessingState != _processingState ||
            previousLoadingTrackId != _loadingTrackId) {
          _notifyUiListeners();
          _notifyBackgroundStateListeners();
        }
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
      if (_repeatMode == TrackRepeatMode.once && currentTrack != null) {
        return;
      }

      if (_repeatMode == TrackRepeatMode.loop && currentTrack != null) {
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

      await _runPlayerCommand<void>(
        'continue to the next track',
        track: _queue[nextIndex],
        () => _switchToQueueIndex(nextIndex, reason: 'completed-next'),
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
      _notifyUiListeners();
      Duration? loadedDuration;
      if (_queue.length > 1) {
        loadedDuration = await _loadQueuedTracks(track: track);
      } else {
        final tag = _mediaItemForTrack(track);
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
      }
      _duration = loadedDuration ?? track.duration;
      await _applyPendingRestorePosition(track, loadedDuration);
      _loadedTrackKey = trackKey;
      _clearLoadingState(trackId: track.id, notify: false);
      _notifyUiListeners();
      _notifyBackgroundStateListeners();
    }

    if (autoPlay) {
      _startPlayback(track, reason: reason);
    }
  }

  Future<Duration?> _loadQueuedTracks({required MusicTrack track}) async {
    final preparedQueue = await _buildPlayerQueueSources();
    if (preparedQueue.sources.length <= 1) {
      return track.hasValidLocalSource
          ? _withLoadTimeout(
            _player.setFilePath(
              track.localPath!.trim(),
              tag: _mediaItemForTrack(track),
            ),
            track: track,
            sourceDescription: track.localPath!.trim(),
          )
          : _loadRemoteTrack(track, tag: _mediaItemForTrack(track));
    }

    debugPrint(
      '[Audio] setAudioSources'
      ' | platform=$_platformLabel'
      ' | queueLength=${preparedQueue.sources.length}'
      ' | currentIndex=${preparedQueue.initialIndex}'
      ' | trackId=${track.id}'
      ' | title=${track.title}',
    );
    return _withLoadTimeout(
      _player.setAudioSources(
        preparedQueue.sources,
        initialIndex: preparedQueue.initialIndex,
      ),
      track: track,
      sourceDescription: 'queue',
    );
  }

  bool get _canUseLoadedQueuePlaylist =>
      _queue.length > 1 && _player.audioSources.length == _queue.length;

  Future<AudioSource?> _audioSourceForTrack(MusicTrack track) async {
    if (!_canQueueTrack(track)) {
      return null;
    }

    if (track.hasValidLocalSource) {
      final filePath = track.localPath!.trim();
      if (!await File(filePath).exists()) {
        return null;
      }
      return AudioSource.file(filePath, tag: _mediaItemForTrack(track));
    }

    return AudioSource.uri(
      Uri.parse(_streamUrlForTrack(track)),
      tag: _mediaItemForTrack(track),
    );
  }

  Future<_PreparedPlayerQueue> _buildPlayerQueueSources() async {
    final sources = <AudioSource>[];
    int? initialIndex;

    final resolvedSources = await Future.wait(
      _queue.asMap().entries.map((entry) async {
        final index = entry.key;
        final track = entry.value;
        if (!_canQueueTrack(track)) {
          return (index: index, source: null as AudioSource?);
        }

        if (track.hasValidLocalSource) {
          final filePath = track.localPath!.trim();
          if (!await File(filePath).exists()) {
            return (index: index, source: null as AudioSource?);
          }
          return (
            index: index,
            source: AudioSource.file(
              filePath,
              tag: _mediaItemForTrack(track),
            ),
          );
        }

        final streamUrl = _streamUrlForTrack(track);
        return (
          index: index,
          source: AudioSource.uri(
            Uri.parse(streamUrl),
            tag: _mediaItemForTrack(track),
          ),
        );
      }),
    );

    for (final resolved in resolvedSources) {
      final source = resolved.source;
      if (source == null) {
        continue;
      }

      if (resolved.index == _currentIndex) {
        initialIndex = sources.length;
      }
      sources.add(source);
    }

    if (sources.isEmpty || initialIndex == null) {
      throw StateError('No playable tracks are available in this queue.');
    }

    return _PreparedPlayerQueue(
      sources: sources,
      initialIndex: initialIndex,
    );
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
    _notifyUiListeners();
    _notifyBackgroundStateListeners();
  }

  Future<void> _switchToQueueIndex(int index, {required String reason}) async {
    final track = _queue[index];
    _currentIndex = index;

    if (_canUseLoadedQueuePlaylist) {
      debugPrint(
        '[Audio] seekToQueueIndex'
        ' | platform=$_platformLabel'
        ' | trackId=${track.id}'
        ' | title=${track.title}'
        ' | queueIndex=$index'
        ' | reason=$reason',
      );
      await _player.seek(Duration.zero, index: index);
      _loadedTrackKey = _trackLoadKey(track);
      _position = Duration.zero;
      _bufferedPosition = Duration.zero;
      _duration = track.duration;
      _clearLoadingState(trackId: track.id, notify: false);
      _notifyUiListeners();
      _notifyBackgroundStateListeners();
      if (!_isPlaying) {
        _startPlayback(track, reason: reason);
      }
      return;
    }

    await _loadCurrentTrack(
      autoPlay: true,
      forceReload: true,
      reason: reason,
    );
  }

  Future<void> _syncActiveQueueState({
    required String reason,
    required bool resumePlayback,
    required Duration preservePosition,
  }) async {
    final track = currentTrack;
    if (track == null || _loadedTrackKey == null) {
      return;
    }

    await _loadCurrentTrack(
      autoPlay: false,
      forceReload: true,
      reason: reason,
    );

    final targetPosition = _clampRestorePosition(
      preservePosition,
      _duration ?? track.duration,
    );
    if (targetPosition > Duration.zero) {
      await _player.seek(targetPosition, index: _currentIndex >= 0 ? _currentIndex : null);
      _position = targetPosition;
    } else {
      _position = Duration.zero;
    }

    if (resumePlayback && currentTrack != null) {
      _startPlayback(currentTrack!, reason: reason);
    }

    _notifyUiListeners();
    _notifyBackgroundStateListeners();
  }

  Future<void> _restorePlaybackSnapshot({
    required String reason,
    required bool resumePlayback,
    required Duration preservePosition,
  }) async {
    if (_queue.isEmpty || _currentIndex < 0 || _currentIndex >= _queue.length) {
      return;
    }

    final track = currentTrack;
    if (track == null || _loadedTrackKey == null) {
      return;
    }

    try {
      await _syncActiveQueueState(
        reason: reason,
        resumePlayback: resumePlayback,
        preservePosition: preservePosition,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[Audio] Failed to restore playback snapshot'
        ' | platform=$_platformLabel'
        ' | trackId=${track.id}'
        ' | title=${track.title}'
        ' | reason=$reason'
        ' | exception=$error',
      );
      debugPrint('$stackTrace');
    }
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
        if (_isInterruptedLoadError(error)) {
          return;
        }
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
      _ => NotificationArtworkService.cachedFallbackArtworkUri,
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

  Duration _clampRestorePosition(
    Duration position,
    Duration? maxDuration,
  ) {
    if (position <= Duration.zero) {
      return Duration.zero;
    }
    final duration = maxDuration;
    if (duration == null || duration <= Duration.zero) {
      return position;
    }
    return position > duration ? duration : position;
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
    String? initialTrackCacheKey,
    required int initialIndex,
  }) {
    final playableTracks = <MusicTrack>[];
    final entryIds = <String>[];
    for (final track in tracks) {
      if (!_canQueueTrack(track)) {
        continue;
      }
      final alreadyPresent = playableTracks.any(
        (existing) => existing.cacheKey == track.cacheKey,
      );
      if (alreadyPresent) {
        continue;
      }
      playableTracks.add(track);
      entryIds.add(_newQueueEntryId(track));
    }

    if (playableTracks.isEmpty) {
      return null;
    }

    final index =
        initialTrackCacheKey != null
            ? playableTracks.indexWhere(
              (track) => track.cacheKey == initialTrackCacheKey,
            )
            : initialTrackId == null
            ? initialIndex.clamp(0, playableTracks.length - 1)
            : playableTracks.indexWhere((track) => track.id == initialTrackId);

    return _PreparedQueue(
      tracks: playableTracks,
      entryIds: entryIds,
      initialIndex: index < 0 ? 0 : index,
    );
  }

  _PreparedQueue _shufflePreparedQueue(_PreparedQueue preparedQueue) {
    if (preparedQueue.tracks.length <= 1) {
      return preparedQueue;
    }

    final entries = List.generate(
      preparedQueue.tracks.length,
      (index) => (
        track: preparedQueue.tracks[index],
        entryId: preparedQueue.entryIds[index],
      ),
    );
    final selectedEntry = entries.removeAt(preparedQueue.initialIndex);
    entries.shuffle(_random);
    entries.insert(0, selectedEntry);

    return _PreparedQueue(
      tracks: entries.map((entry) => entry.track).toList(growable: false),
      entryIds: entries.map((entry) => entry.entryId).toList(growable: false),
      initialIndex: 0,
    );
  }

  int? _computeNextIndex({bool onCompletion = false}) {
    if (_queue.isEmpty || _currentIndex < 0) {
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
          _notifyUiListeners();
          _notifyBackgroundStateListeners();

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
            final message = _messageForCommandFailure(
              error,
              action: action,
              track: subject,
              fallbackMessage: failureMessage,
            );
            if (message.isNotEmpty) {
              _recordError(message);
            }
            completer.complete(null);
          } finally {
            _activeCommandAction = null;
            _activeCommandTrackId = null;
            if (!_disposed) {
              _notifyUiListeners();
              _notifyBackgroundStateListeners();
            }
          }
        });

    return completer.future;
  }

  void _announceTrackChange() {
    onTrackChanged?.call(currentTrack);
    _notifyUiListeners();
    _notifyBackgroundStateListeners();
  }

  Future<void> _applyPendingRestorePosition(
    MusicTrack track,
    Duration? loadedDuration,
  ) async {
    if (_pendingRestoreTrackId != track.id || _pendingRestorePosition == null) {
      return;
    }

    final desiredPosition = _clampRestorePosition(
      _pendingRestorePosition!,
      loadedDuration ?? track.duration,
    );
    _pendingRestoreTrackId = null;
    _pendingRestorePosition = null;

    if (desiredPosition <= Duration.zero) {
      _position = Duration.zero;
      return;
    }

    await _player.seek(desiredPosition);
    _position = desiredPosition;
  }

  MusicTrack _mergeTrackMetadataPreservingSource(
    MusicTrack base,
    MusicTrack metadata,
  ) {
    return base.copyWith(
      title: metadata.title,
      artistName: metadata.artistName,
      artistId: metadata.artistId,
      artistNames: metadata.artistNames,
      artistIds: metadata.artistIds,
      albumTitle: metadata.albumTitle,
      albumId: metadata.albumId,
      clearAlbumId: metadata.albumId == null,
      artworkPath: metadata.artworkPath,
      artworkUrl: metadata.artworkUrl,
      clearArtworkPath: metadata.artworkPath == null,
      clearArtworkUrl: metadata.artworkUrl == null,
      description: metadata.description,
      clearDescription: metadata.description == null,
      genre: metadata.genre,
      clearGenre: metadata.genre == null,
      durationSeconds: metadata.durationSeconds,
    );
  }

  void _recordError(String message) {
    _lastErrorMessage = message;
    _notifyUiListeners();
    _notifyBackgroundStateListeners();
  }

  void _clearError({bool notify = true}) {
    if (_lastErrorMessage == null) {
      return;
    }
    _lastErrorMessage = null;
    if (notify) {
      _notifyUiListeners();
      _notifyBackgroundStateListeners();
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

    if (_isInterruptedLoadError(error)) {
      return '';
    }

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
      return '';
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
    if (notify) {
      _notifyUiListeners();
      _notifyBackgroundStateListeners();
    }
  }

  void _notifyUiListeners() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  void _notifyBackgroundStateListeners() {
    if (_disposed || _backgroundStateListeners.isEmpty) {
      return;
    }
    for (final listener in _backgroundStateListeners.toList()) {
      listener();
    }
  }

  bool _shouldNotifyUiProgress(Duration position) {
    final now = DateTime.now();
    final shouldNotify =
        now.difference(_lastUiProgressNotificationAt) >=
            _uiProgressNotificationInterval ||
        (position - _lastUiNotifiedPosition).inMilliseconds.abs() >= 250;
    if (shouldNotify) {
      _lastUiProgressNotificationAt = now;
      _lastUiNotifiedPosition = position;
    }
    return shouldNotify;
  }

  bool _shouldNotifyBackgroundProgress(Duration position) {
    final now = DateTime.now();
    final shouldNotify =
        now.difference(_lastBackgroundProgressNotificationAt) >=
            _backgroundProgressNotificationInterval ||
        (position - _lastBackgroundNotifiedPosition).inSeconds.abs() >= 1;
    if (shouldNotify) {
      _lastBackgroundProgressNotificationAt = now;
      _lastBackgroundNotifiedPosition = position;
    }
    return shouldNotify;
  }

  bool _shouldNotifyBufferedProgress(Duration position) {
    final shouldNotify =
        (position - _lastUiNotifiedBufferedPosition).inMilliseconds.abs() >=
        _bufferedPositionThreshold.inMilliseconds;
    if (shouldNotify) {
      _lastUiNotifiedBufferedPosition = position;
    }
    return shouldNotify;
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

  String _newQueueEntryId(MusicTrack track) {
    _queueEntrySeed += 1;
    return '${track.cacheKey}-${_queueEntrySeed.toRadixString(36)}';
  }

  bool _isInterruptedLoadError(Object error) {
    if (error is PlayerInterruptedException) {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('loading interrupted') ||
        message.contains('interrupted while loading');
  }

  void _bumpQueueVersion() {
    _queueVersion += 1;
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
  const _PreparedQueue({
    required this.tracks,
    required this.entryIds,
    required this.initialIndex,
  });

  final List<MusicTrack> tracks;
  final List<String> entryIds;
  final int initialIndex;
}

class _PreparedPlayerQueue {
  const _PreparedPlayerQueue({
    required this.sources,
    required this.initialIndex,
  });

  final List<AudioSource> sources;
  final int initialIndex;
}
