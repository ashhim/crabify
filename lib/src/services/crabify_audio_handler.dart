import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/music_track.dart';
import '../theme/crabify_theme.dart';
import 'audio_player_service.dart';

class CrabifyAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  CrabifyAudioHandler();

  static CrabifyAudioHandler? _instance;
  static Future<CrabifyAudioHandler>? _initializing;

  AudioPlayerService? _playerService;
  VoidCallback? _backgroundListener;
  Uri? _fallbackArtworkUri;
  final Completer<void> _bindingCompleter = Completer<void>();

  static Future<CrabifyAudioHandler> ensureInitialized() {
    final existing = _instance;
    if (existing != null) {
      return Future<CrabifyAudioHandler>.value(existing);
    }

    final inFlight = _initializing;
    if (inFlight != null) {
      return inFlight;
    }

    final future = AudioService.init(
      builder: CrabifyAudioHandler.new,
      config: AudioServiceConfig(
        androidResumeOnClick: true,
        androidNotificationChannelId: 'com.example.crabify.audio',
        androidNotificationChannelName: 'Crabify Playback',
        androidNotificationChannelDescription:
            'Playback controls for Crabify music',
        notificationColor: CrabifyColors.surfaceHighlightStrong,
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
        preloadArtwork: true,
      ),
    ).then((handler) async {
      await handler._ensureFallbackArtwork();
      _instance = handler;
      return handler;
    }).whenComplete(() {
      _initializing = null;
    });

    _initializing = future;
    return future;
  }

  void bindPlayer(AudioPlayerService playerService) {
    if (identical(_playerService, playerService)) {
      _syncFromPlayer();
      return;
    }

    final listener = _backgroundListener;
    final currentPlayer = _playerService;
    if (currentPlayer != null && listener != null) {
      currentPlayer.removeBackgroundStateListener(listener);
    }

    _playerService = playerService;
    _backgroundListener = _syncFromPlayer;
    playerService.addBackgroundStateListener(_backgroundListener!);
    if (!_bindingCompleter.isCompleted) {
      _bindingCompleter.complete();
    }
    _syncFromPlayer();
  }

  @override
  Future<void> play() async {
    await _runBoundAction('play', (player) => player.play());
  }

  @override
  Future<void> pause() async {
    await _runBoundAction('pause', (player) => player.pause());
  }

  @override
  Future<void> stop() async {
    await _runBoundAction('stop', (player) => player.stop());
    queue.add(const <MediaItem>[]);
    _publishPlaybackState(forceStopped: true);
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    await _runBoundAction('next', (player) => player.next());
  }

  @override
  Future<void> skipToPrevious() async {
    await _runBoundAction('previous', (player) => player.previous());
  }

  @override
  Future<void> seek(Duration position) async {
    await _runBoundAction('seek', (player) => player.seek(position));
  }

  void _syncFromPlayer() {
    final playerService = _playerService;
    if (playerService == null) {
      return;
    }

    try {
      debugPrint(
        '[Audio] Publishing background state'
        ' | track=${playerService.currentTrack?.title ?? 'none'}'
        ' | queueLength=${playerService.queue.length}'
        ' | playing=${playerService.isPlaying}'
        ' | processing=${playerService.processingState}'
        ' | index=${playerService.currentIndex}',
      );
      queue.add(
        playerService.queue.map(_mediaItemForTrack).toList(growable: false),
      );

      final currentTrack = playerService.currentTrack;
      if (currentTrack != null) {
        mediaItem.add(_mediaItemForTrack(currentTrack));
      }

      _publishPlaybackState();
    } catch (error, stackTrace) {
      debugPrint('[Audio] Background sync failed: $error');
      debugPrint('$stackTrace');
    }
  }

  void _publishPlaybackState({bool forceStopped = false}) {
    final playerService = _playerService;
    if (playerService == null) {
      return;
    }

    final hasTrack = playerService.currentTrack != null;
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      playerService.isPlaying ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const <int>[0, 1, 2],
        processingState:
            forceStopped
                ? AudioProcessingState.idle
                : _mapProcessingState(playerService),
        playing: !forceStopped && playerService.isPlaying,
        updatePosition: playerService.position,
        bufferedPosition: playerService.bufferedPosition,
        speed: 1.0,
        queueIndex:
            playerService.currentIndex >= 0 ? playerService.currentIndex : null,
        repeatMode: _mapRepeatMode(playerService.loopMode),
        shuffleMode:
            playerService.shuffleEnabled
                ? AudioServiceShuffleMode.all
                : AudioServiceShuffleMode.none,
      ),
    );

    debugPrint(
      '[Audio] playbackState.add'
      ' | forceStopped=$forceStopped'
      ' | playing=${!forceStopped && playerService.isPlaying}'
      ' | processing=${forceStopped ? AudioProcessingState.idle : _mapProcessingState(playerService)}'
      ' | queueIndex=${playerService.currentIndex >= 0 ? playerService.currentIndex : null}'
      ' | controls=${controls.map((control) => control.label).join(',')}',
    );

    if (!hasTrack && forceStopped) {
      queue.add(const <MediaItem>[]);
    }
  }

  AudioProcessingState _mapProcessingState(AudioPlayerService playerService) {
    if (playerService.isLoading) {
      return AudioProcessingState.loading;
    }

    return switch (playerService.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
  }

  AudioServiceRepeatMode _mapRepeatMode(LoopMode loopMode) {
    return switch (loopMode) {
      LoopMode.off => AudioServiceRepeatMode.none,
      LoopMode.one => AudioServiceRepeatMode.one,
      LoopMode.all => AudioServiceRepeatMode.all,
    };
  }

  MediaItem _mediaItemForTrack(MusicTrack track) {
    final artUri = switch ((track.artworkPath, track.artworkUrl)) {
      (String path, _) when path.isNotEmpty => Uri.file(path),
      (_, String url) when url.isNotEmpty => Uri.parse(url),
      _ => _fallbackArtworkUri,
    };

    return MediaItem(
      id: track.id,
      album: track.albumTitle,
      title: track.title,
      artist: track.artistName,
      artUri: artUri,
      playable: true,
      duration: track.duration,
    );
  }

  Future<void> _ensureFallbackArtwork() async {
    final tempDirectory = await getTemporaryDirectory();
    final targetFile = File(
      path.join(tempDirectory.path, 'crabify_notification_fallback.png'),
    );
    if (!await targetFile.exists()) {
      const width = 512;
      const height = 512;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      canvas.drawRect(
        bounds,
        Paint()..color = CrabifyColors.background,
      );

      final splitStart = width * 0.65;
      final goldRect = Rect.fromLTWH(
        splitStart,
        0,
        width - splitStart,
        height.toDouble(),
      );
      canvas.drawRect(
        goldRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(splitStart, 0),
            Offset(width.toDouble(), height.toDouble()),
            const <Color>[
              CrabifyColors.goldSecondary,
              CrabifyColors.goldPrimary,
            ],
          ),
      );
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            Offset(width.toDouble(), height.toDouble()),
            <Color>[
              Colors.transparent,
              CrabifyColors.goldGlow,
              Colors.transparent,
            ],
          ),
      );
      final image = await recorder.endRecording().toImage(width, height);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        await targetFile.writeAsBytes(
          byteData.buffer.asUint8List(),
          flush: true,
        );
      }
    }
    _fallbackArtworkUri = Uri.file(targetFile.path);
  }

  Future<void> _runBoundAction(
    String action,
    Future<void> Function(AudioPlayerService playerService) command,
  ) async {
    if (_playerService == null) {
      try {
        await _bindingCompleter.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        debugPrint(
          '[Audio] Ignoring $action from background controls because the player is not bound yet.',
        );
        return;
      }
    }

    final playerService = _playerService;
    if (playerService == null) {
      debugPrint(
        '[Audio] Ignoring $action from background controls because no player is available.',
      );
      return;
    }

    try {
      await command(playerService);
    } catch (error, stackTrace) {
      debugPrint('[Audio] Background action failed: $action | error=$error');
      debugPrint('$stackTrace');
    }
  }
}
