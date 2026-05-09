import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_track.dart';
import '../services/audio_player_service.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/track_actions.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final track = context.select<AudioPlayerService, MusicTrack?>(
      (audio) => audio.currentTrack,
    );
    if (track == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: CrabifyColors.topBar),
        body: const Center(
          child: Text('Pick something from the library to start listening.'),
        ),
      );
    }

    final library = context.read<LibraryService>();
    final isLiked = context.select<LibraryService, bool>(
      (service) => service.isLiked(track.id),
    );
    final downloadProgress = context.select<LibraryService, double?>(
      (service) => service.progressFor(track.id),
    );
    final isDownloaded = context.select<LibraryService, bool>(
      (service) => service.isDownloaded(track.id),
    );
    final downloadDisabledReason = context.select<LibraryService, String?>(
      (service) => service.downloadDisabledReason(track),
    );
    final paletteFuture = resolveArtworkThemePalette(
      seed: track.cacheKey,
      artworkPath: track.artworkPath,
      artworkUrl: track.artworkUrl,
    );

    return FutureBuilder<ArtworkThemePalette>(
      future: paletteFuture,
      initialData: artworkThemePaletteForSeed(track.cacheKey),
      builder: (context, snapshot) {
        final palette =
            snapshot.data ?? artworkThemePaletteForSeed(track.cacheKey);
        return Scaffold(
          backgroundColor: CrabifyColors.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: IconButton(
              style: _hoverIconButtonStyle(
                hoverColor: palette.controlColor,
                foregroundColor: palette.controlColor,
              ),
              onPressed: () => _showQueue(context),
              icon: const Icon(Icons.queue_music_rounded),
            ),
            title: const Text('Now playing'),
            centerTitle: true,
            actions: <Widget>[
              IconButton(
                style: _hoverIconButtonStyle(
                  hoverColor: palette.controlColor,
                  foregroundColor: CrabifyColors.textPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.expand_more_rounded),
              ),
              IconButton(
                style: _hoverIconButtonStyle(
                  hoverColor: palette.controlColor,
                  foregroundColor: CrabifyColors.textPrimary,
                ),
                onPressed: () => showTrackActionsSheet(context, track: track),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentMaxWidth =
                      math.min(constraints.maxWidth, 560.0).toDouble();
                  final artworkSize = math.min(
                    contentMaxWidth,
                    constraints.maxHeight * 0.44,
                  ).clamp(220.0, contentMaxWidth).toDouble();
                  final artworkSpacing = math.max(
                    20.0,
                    constraints.maxHeight * 0.03,
                  );
                  return Column(
                    children: <Widget>[
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: contentMaxWidth),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: math.max(8, constraints.maxHeight * 0.01),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    ArtworkTile(
                                      seed: track.cacheKey,
                                      artworkPath: track.artworkPath,
                                      artworkUrl: track.artworkUrl,
                                      size: artworkSize,
                                      borderRadius: BorderRadius.circular(28),
                                      icon: Icons.waves_rounded,
                                    ),
                                    SizedBox(height: artworkSpacing),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              _AnimatedTrackText(
                                                text: track.title,
                                                maxLines: 2,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headlineSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: palette.titleColor,
                                                    ),
                                              ),
                                              const SizedBox(height: 6),
                                              _AnimatedTrackText(
                                                text: track.artistName,
                                                maxLines: 2,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      color:
                                                          palette.subtitleColor,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          style: _hoverIconButtonStyle(
                                            hoverColor: palette.controlColor,
                                            foregroundColor:
                                                isLiked
                                                    ? palette.controlColor
                                                    : CrabifyColors
                                                        .textPrimary,
                                          ),
                                          onPressed:
                                              () => library.toggleLike(
                                                track.id,
                                                trackSnapshot: track,
                                              ),
                                          icon: Icon(
                                            isLiked
                                                ? Icons.favorite_rounded
                                                : Icons
                                                    .favorite_border_rounded,
                                          ),
                                        ),
                                        IconButton(
                                          style: _hoverIconButtonStyle(
                                            hoverColor: palette.controlColor,
                                            foregroundColor:
                                                isDownloaded
                                                    ? palette.controlColor
                                                    : CrabifyColors
                                                        .textPrimary,
                                          ),
                                          tooltip: downloadDisabledReason,
                                          onPressed:
                                              downloadDisabledReason == null
                                                  ? () async {
                                                    try {
                                                      await library
                                                          .downloadTrack(track);
                                                    } catch (error) {
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            error.toString(),
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  }
                                                  : null,
                                          icon:
                                              downloadProgress != null
                                                  ? SizedBox.square(
                                                    dimension: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          value:
                                                              downloadProgress,
                                                        ),
                                                  )
                                                  : Icon(
                                                    isDownloaded
                                                        ? Icons
                                                            .download_done_rounded
                                                        : Icons
                                                            .download_rounded,
                                                  ),
                                        ),
                                      ],
                                    ),
                                    _PlaybackStatus(track: track),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _PlaybackProgress(
                        track: track,
                        formatDuration: _formatDuration,
                      ),
                      const SizedBox(height: 18),
                      _PlaybackControls(palette: palette),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showQueue(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CrabifyColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _QueueSheet(),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _PlaybackStatus extends StatelessWidget {
  const _PlaybackStatus({required this.track});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    final audioState = context.select<
      AudioPlayerService,
      ({String? lastErrorMessage, bool isLoading, String? loadingTrackId})
    >(
      (audio) => (
        lastErrorMessage: audio.lastErrorMessage,
        isLoading: audio.isLoading,
        loadingTrackId: audio.loadingTrackId,
      ),
    );
    final widgets = <Widget>[];
    if (audioState.lastErrorMessage != null) {
      widgets.addAll(<Widget>[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CrabifyColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: CrabifyColors.border),
          ),
          child: Text(
            audioState.lastErrorMessage!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: CrabifyColors.dangerSoft),
          ),
        ),
      ]);
    }

    final busyForCurrentTrack =
        audioState.isLoading && audioState.loadingTrackId == track.id;
    if (busyForCurrentTrack) {
      widgets.addAll(<Widget>[
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading ${track.title}...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CrabifyColors.textSecondary,
              ),
            ),
          ],
        ),
      ]);
    }

    if (widgets.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

class _PlaybackProgress extends StatefulWidget {
  const _PlaybackProgress({required this.track, required this.formatDuration});

  final MusicTrack track;
  final String Function(Duration duration) formatDuration;

  @override
  State<_PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<_PlaybackProgress> {
  double? _dragValueMillis;

  @override
  Widget build(BuildContext context) {
    final audioState = context.select<
      AudioPlayerService,
      ({
        Duration position,
        Duration duration,
        bool isLoading,
        String? loadingTrackId,
      })
    >(
      (audio) => (
        position: audio.position,
        duration: audio.duration,
        isLoading: audio.isLoading,
        loadingTrackId: audio.loadingTrackId,
      ),
    );
    final audio = context.read<AudioPlayerService>();
    final total =
        audioState.duration.inMilliseconds <= 0
            ? (widget.track.duration?.inMilliseconds ?? 1)
            : audioState.duration.inMilliseconds;
    final currentValue = audioState.position.inMilliseconds.clamp(0, total);
    final effectiveValue =
        _dragValueMillis == null
            ? currentValue.toDouble()
            : _dragValueMillis!.clamp(0.0, total.toDouble()).toDouble();
    final busyForCurrentTrack =
        audioState.isLoading && audioState.loadingTrackId == widget.track.id;
    final displayedPosition = Duration(milliseconds: effectiveValue.round());

    return Column(
      children: <Widget>[
        Slider(
          value: effectiveValue,
          min: 0,
          max: total.toDouble(),
          onChangeStart:
              busyForCurrentTrack
                  ? null
                  : (value) => setState(() => _dragValueMillis = value),
          onChanged:
              busyForCurrentTrack
                  ? null
                  : (value) => setState(() => _dragValueMillis = value),
          onChangeEnd:
              busyForCurrentTrack
                  ? null
                  : (value) async {
                    final target = Duration(milliseconds: value.round());
                    if (mounted) {
                      setState(() => _dragValueMillis = null);
                    }
                    await audio.seek(target);
                  },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                widget.formatDuration(displayedPosition),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CrabifyColors.textSecondary,
                ),
              ),
              Text(
                widget.formatDuration(audioState.duration),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CrabifyColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.palette});

  final ArtworkThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final audioState = context.select<
      AudioPlayerService,
      ({
        String? currentTrackId,
        bool isLoading,
        String? loadingTrackId,
        bool shuffleEnabled,
        bool isPlaying,
        bool canStop,
        TrackRepeatMode repeatMode,
      })
    >(
      (audio) => (
        currentTrackId: audio.currentTrack?.id,
        isLoading: audio.isLoading,
        loadingTrackId: audio.loadingTrackId,
        shuffleEnabled: audio.shuffleEnabled,
        isPlaying: audio.isPlaying,
        canStop: audio.canStop,
        repeatMode: audio.repeatMode,
      ),
    );
    final audio = context.read<AudioPlayerService>();
    final busyForCurrentTrack =
        audioState.currentTrackId != null &&
        audioState.isLoading &&
        audioState.loadingTrackId == audioState.currentTrackId;
    final controlColor = palette.controlColor;
    final inactiveControlColor =
        Color.lerp(CrabifyColors.textPrimary, controlColor, 0.35)!;
    final filledForegroundColor = _playerControlForegroundColor(controlColor);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        IconButton(
          style: _hoverIconButtonStyle(
            hoverColor: controlColor,
            foregroundColor:
                audioState.shuffleEnabled ? controlColor : inactiveControlColor,
          ),
          onPressed: busyForCurrentTrack ? null : audio.toggleShuffle,
          icon: _AnimatedControlIcon(
            icon: Icons.shuffle_rounded,
            color:
                audioState.shuffleEnabled ? controlColor : inactiveControlColor,
          ),
        ),
        IconButton(
          style: _hoverIconButtonStyle(
            hoverColor: controlColor,
            foregroundColor: controlColor,
            fixedSize: const Size.square(54),
          ),
          onPressed: busyForCurrentTrack ? null : audio.previous,
          iconSize: 36,
          icon: _AnimatedControlIcon(
            icon: Icons.skip_previous_rounded,
            color: controlColor,
            size: 36,
          ),
        ),
        IconButton.filled(
          onPressed: busyForCurrentTrack ? null : audio.togglePlayback,
          style: _filledHoverIconButtonStyle(
            backgroundColor: controlColor,
            foregroundColor: filledForegroundColor,
            fixedSize: const Size.square(72),
          ),
          icon:
              busyForCurrentTrack
                  ? SizedBox.square(
                    dimension: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: filledForegroundColor,
                    ),
                  )
                  : Icon(
                    audioState.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 40,
                  ),
        ),
        IconButton(
          style: _hoverIconButtonStyle(
            hoverColor: controlColor,
            foregroundColor: controlColor,
            fixedSize: const Size.square(54),
          ),
          onPressed: busyForCurrentTrack ? null : audio.next,
          iconSize: 36,
          icon: _AnimatedControlIcon(
            icon: Icons.skip_next_rounded,
            color: controlColor,
            size: 36,
          ),
        ),
        IconButton(
          style: _hoverIconButtonStyle(
            hoverColor: controlColor,
            foregroundColor: inactiveControlColor,
          ),
          onPressed:
              busyForCurrentTrack || !audioState.canStop ? null : audio.stop,
          iconSize: 30,
          icon: _AnimatedControlIcon(
            icon: Icons.stop_rounded,
            color: inactiveControlColor,
            size: 30,
          ),
        ),
        IconButton(
          style: _hoverIconButtonStyle(
            hoverColor: controlColor,
            foregroundColor:
                audioState.repeatMode == TrackRepeatMode.off
                    ? inactiveControlColor
                    : controlColor,
          ),
          onPressed: busyForCurrentTrack ? null : audio.cycleLoopMode,
          icon: _AnimatedControlIcon(
            icon: switch (audioState.repeatMode) {
              TrackRepeatMode.once => Icons.repeat_one_rounded,
              TrackRepeatMode.loop => Icons.repeat_rounded,
              TrackRepeatMode.off => Icons.repeat_rounded,
            },
            color:
                audioState.repeatMode == TrackRepeatMode.off
                    ? inactiveControlColor
                    : controlColor,
          ),
        ),
      ],
    );
  }
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    context.select<AudioPlayerService, ({int queueVersion, int currentIndex})>(
      (audio) => (
        queueVersion: audio.queueVersion,
        currentIndex: audio.currentIndex,
      ),
    );
    final audio = context.read<AudioPlayerService>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Queue',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap to jump, long press and drag to reorder, or remove tracks you no longer want.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CrabifyColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 420,
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                primary: false,
                itemExtent: 74,
                physics: const ClampingScrollPhysics(),
                proxyDecorator: (child, _, _) {
                  return Material(color: Colors.transparent, child: child);
                },
                itemCount: audio.queue.length,
                onReorder: (oldIndex, newIndex) {
                  context.read<LibraryService>().moveQueueItem(
                    oldIndex,
                    newIndex,
                  );
                },
                itemBuilder: (context, index) {
                  final track = audio.queue[index];
                  final active = index == audio.currentIndex;
                  return _QueueListTile(
                    key: ValueKey(audio.queueEntryIdAt(index)),
                    track: track,
                    index: index,
                    active: active,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueListTile extends StatelessWidget {
  const _QueueListTile({
    super.key,
    required this.track,
    required this.index,
    required this.active,
  });

  final MusicTrack track;
  final int index;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final indexBadge = CircleAvatar(
      backgroundColor:
          active ? CrabifyColors.accent : CrabifyColors.surfaceMuted,
      child: Text(
        '${index + 1}',
        style: TextStyle(
          color: active ? Colors.black : CrabifyColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return ReorderableDelayedDragStartListener(
      key: key,
      index: index,
      child: ListTile(
        hoverColor: CrabifyColors.accent.withValues(alpha: 0.08),
        onTap: () => context.read<LibraryService>().playQueueItem(index),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: indexBadge,
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: active ? CrabifyColors.accent : CrabifyColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          track.artistName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              style: _hoverIconButtonStyle(
                hoverColor: CrabifyColors.accent,
                foregroundColor: CrabifyColors.textPrimary,
              ),
              tooltip: 'Remove from queue',
              onPressed:
                  () => context.read<LibraryService>().removeQueueItem(index),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}


class _AnimatedTrackText extends StatelessWidget {
  const _AnimatedTrackText({
    required this.text,
    required this.style,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 260),
      tween: ColorTween(end: style?.color ?? CrabifyColors.textPrimary),
      builder: (context, color, _) {
        return Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(color: color),
        );
      },
    );
  }
}

class _AnimatedControlIcon extends StatelessWidget {
  const _AnimatedControlIcon({
    required this.icon,
    required this.color,
    this.size,
  });

  final IconData icon;
  final Color color;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 260),
      tween: ColorTween(end: color),
      builder: (context, animatedColor, _) {
        return Icon(icon, color: animatedColor, size: size);
      },
    );
  }
}

Color _playerControlForegroundColor(Color backgroundColor) {
  return backgroundColor.computeLuminance() > 0.45
      ? Colors.black
      : Colors.white;
}

ButtonStyle _hoverIconButtonStyle({
  required Color hoverColor,
  required Color foregroundColor,
  Size? fixedSize,
}) {
  return ButtonStyle(
    foregroundColor: WidgetStatePropertyAll<Color>(foregroundColor),
    fixedSize:
        fixedSize == null ? null : WidgetStatePropertyAll<Size>(fixedSize),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.all(10),
    ),
    visualDensity: VisualDensity.compact,
    backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return Colors.transparent;
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return hoverColor.withValues(alpha: 0.12);
      }
      return Colors.transparent;
    }),
    overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.hovered)) {
        return hoverColor.withValues(alpha: 0.08);
      }
      if (states.contains(WidgetState.pressed)) {
        return hoverColor.withValues(alpha: 0.18);
      }
      return null;
    }),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

ButtonStyle _filledHoverIconButtonStyle({
  required Color backgroundColor,
  required Color foregroundColor,
  required Size fixedSize,
}) {
  return ButtonStyle(
    fixedSize: WidgetStatePropertyAll<Size>(fixedSize),
    foregroundColor: WidgetStatePropertyAll<Color>(foregroundColor),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.all(10),
    ),
    visualDensity: VisualDensity.compact,
    backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return backgroundColor.withValues(alpha: 0.32);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return Color.lerp(backgroundColor, Colors.white, 0.08);
      }
      return backgroundColor;
    }),
    overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return foregroundColor.withValues(alpha: 0.12);
      }
      return null;
    }),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}
