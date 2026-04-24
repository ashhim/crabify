import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/music_track.dart';
import 'audius_api_service.dart';

class AudioPlayerService extends ChangeNotifier {
  AudioPlayerService({required AudiusApiService audiusApiService})
    : _audiusApiService = audiusApiService {
    _subscriptions.add(
      _player.currentIndexStream.listen((index) {
        if (index != null) {
          _currentIndex = index;
          onTrackChanged?.call(currentTrack);
        }
        notifyListeners();
      }),
    );

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
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.loopModeStream.listen((loopMode) {
        _loopMode = loopMode;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.shuffleModeEnabledStream.listen((enabled) {
        _shuffleEnabled = enabled;
        notifyListeners();
      }),
    );
  }

  final AudioPlayer _player = AudioPlayer();
  final AudiusApiService _audiusApiService;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  List<MusicTrack> _queue = <MusicTrack>[];
  int _currentIndex = 0;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration? _duration;
  bool _isPlaying = false;
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  ProcessingState _processingState = ProcessingState.idle;

  void Function(MusicTrack? track)? onTrackChanged;

  List<MusicTrack> get queue => List<MusicTrack>.unmodifiable(_queue);
  MusicTrack? get currentTrack =>
      _queue.isEmpty || _currentIndex < 0 || _currentIndex >= _queue.length
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

  Future<void> setQueue(
    List<MusicTrack> tracks, {
    String? initialTrackId,
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    final playableTracks = tracks.where((track) => track.isPlayable).toList();
    if (playableTracks.isEmpty) {
      return;
    }

    _queue = playableTracks;
    final resolvedIndex =
        initialTrackId == null
            ? initialIndex.clamp(0, playableTracks.length - 1)
            : playableTracks.indexWhere((track) => track.id == initialTrackId);
    final selectedIndex = resolvedIndex < 0 ? 0 : resolvedIndex;

    final audioSources = await Future.wait(playableTracks.map(_sourceForTrack));

    await _player.setAudioSources(audioSources, initialIndex: selectedIndex);
    _currentIndex = selectedIndex;
    if (autoPlay) {
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> addToQueue(MusicTrack track) async {
    if (!track.isPlayable) {
      return;
    }

    if (_queue.isEmpty) {
      await setQueue(<MusicTrack>[track], autoPlay: false);
      return;
    }

    final insertIndex = (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insert(insertIndex, track);
    await _player.insertAudioSource(insertIndex, await _sourceForTrack(track));
    notifyListeners();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }

    _queue.removeAt(index);
    await _player.removeAudioSourceAt(index);
    if (_queue.isEmpty) {
      await _player.stop();
    }
    notifyListeners();
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

    final track = _queue.removeAt(oldIndex);
    _queue.insert(adjustedIndex, track);
    await _player.moveAudioSource(oldIndex, adjustedIndex);
    notifyListeners();
  }

  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();

  Future<void> togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }
    await _player.play();
  }

  Future<void> next() =>
      _player.hasNext ? _player.seekToNext() : Future.value();
  Future<void> previous() =>
      _player.hasPrevious ? _player.seekToPrevious() : Future.value();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> toggleShuffle() async {
    final shouldEnable = !_shuffleEnabled;
    if (shouldEnable) {
      await _player.shuffle();
    }
    await _player.setShuffleModeEnabled(shouldEnable);
  }

  Future<void> cycleLoopMode() async {
    final nextMode = switch (_loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(nextMode);
  }

  Future<AudioSource> _sourceForTrack(MusicTrack track) async {
    final uri =
        track.isLocal
            ? Uri.file(track.localPath!)
            : Uri.parse(await _audiusApiService.fetchFreshStreamUrl(track));
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

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
