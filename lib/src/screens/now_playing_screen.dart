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

    return Scaffold(
      backgroundColor: CrabifyColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.expand_more_rounded),
        ),
        title: const Text('Now playing'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            onPressed: () => _showQueue(context),
            icon: const Icon(Icons.queue_music_rounded),
          ),
          IconButton(
            onPressed: () => showTrackActionsSheet(context, track: track),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                final artworkSize = constraints.maxWidth;
                return ArtworkTile(
                  seed: track.cacheKey,
                  artworkPath: track.artworkPath,
                  artworkUrl: track.artworkUrl,
                  size: artworkSize,
                  borderRadius: BorderRadius.circular(28),
                  icon: Icons.waves_rounded,
                );
              },
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        track.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        track.artistName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: CrabifyColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed:
                      () => library.toggleLike(
                        track.id,
                        trackSnapshot: track,
                      ),
                  icon: Icon(
                    isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color:
                        isLiked
                            ? CrabifyColors.accent
                            : CrabifyColors.textPrimary,
                  ),
                ),
                IconButton(
                  tooltip: downloadDisabledReason,
                  onPressed:
                      downloadDisabledReason == null
                          ? () async {
                            try {
                              await library.downloadTrack(track);
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                          }
                          : null,
                  icon:
                      downloadProgress != null
                          ? SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: downloadProgress,
                            ),
                          )
                          : Icon(
                            isDownloaded
                                ? Icons.download_done_rounded
                                : Icons.download_rounded,
                          ),
                ),
              ],
            ),
            _PlaybackStatus(track: track),
            const SizedBox(height: 18),
            _PlaybackProgress(track: track, formatDuration: _formatDuration),
            const SizedBox(height: 10),
            const _PlaybackControls(),
            const SizedBox(height: 20),
            const _QueueSection(),
          ],
        ),
      ),
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
    return Consumer<AudioPlayerService>(
      builder: (context, audio, _) {
        final widgets = <Widget>[];
        if (audio.lastErrorMessage != null) {
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
                audio.lastErrorMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: CrabifyColors.dangerSoft,
                ),
              ),
            ),
          ]);
        }

        final busyForCurrentTrack =
            audio.isLoading && audio.loadingTrackId == track.id;
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
      },
    );
  }
}

class _PlaybackProgress extends StatelessWidget {
  const _PlaybackProgress({
    required this.track,
    required this.formatDuration,
  });

  final MusicTrack track;
  final String Function(Duration duration) formatDuration;

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerService>(
      builder: (context, audio, _) {
        final total =
            audio.duration.inMilliseconds <= 0
                ? (track.duration?.inMilliseconds ?? 1)
                : audio.duration.inMilliseconds;
        final currentValue = audio.position.inMilliseconds.clamp(0, total);
        final busyForCurrentTrack =
            audio.isLoading && audio.loadingTrackId == track.id;

        return Column(
          children: <Widget>[
            Slider(
              value: currentValue.toDouble(),
              min: 0,
              max: total.toDouble(),
              onChanged:
                  busyForCurrentTrack
                      ? null
                      : (value) => audio.seek(
                        Duration(milliseconds: value.round()),
                      ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    formatDuration(audio.position),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CrabifyColors.textSecondary,
                    ),
                  ),
                  Text(
                    formatDuration(audio.duration),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CrabifyColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls();

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerService>(
      builder: (context, audio, _) {
        final track = audio.currentTrack;
        final busyForCurrentTrack =
            track != null && audio.isLoading && audio.loadingTrackId == track.id;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            IconButton(
              onPressed: busyForCurrentTrack ? null : audio.toggleShuffle,
              icon: Icon(
                Icons.shuffle_rounded,
                color:
                    audio.shuffleEnabled
                        ? CrabifyColors.accent
                        : CrabifyColors.textPrimary,
              ),
            ),
            IconButton(
              onPressed: busyForCurrentTrack ? null : audio.previous,
              iconSize: 36,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton.filled(
              onPressed: busyForCurrentTrack ? null : audio.togglePlayback,
              style: IconButton.styleFrom(
                backgroundColor: CrabifyColors.accent,
                foregroundColor: Colors.black,
                fixedSize: const Size.square(72),
              ),
              icon:
                  busyForCurrentTrack
                      ? const SizedBox.square(
                        dimension: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: Colors.black,
                        ),
                      )
                      : Icon(
                        audio.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 40,
                      ),
            ),
            IconButton(
              onPressed: busyForCurrentTrack ? null : audio.next,
              iconSize: 36,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            IconButton(
              onPressed: busyForCurrentTrack ? null : audio.stop,
              iconSize: 30,
              icon: const Icon(Icons.stop_rounded),
            ),
            IconButton(
              onPressed: busyForCurrentTrack ? null : audio.cycleLoopMode,
              icon: Icon(
                audio.repeatMode == TrackRepeatMode.loop
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                color:
                    audio.repeatMode == TrackRepeatMode.off
                        ? CrabifyColors.textPrimary
                        : CrabifyColors.accent,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QueueSection extends StatelessWidget {
  const _QueueSection();

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioPlayerService>();
    final queue = audio.queue;
    final hasUpcomingTracks = queue.length > 1;
    final listHeight = math.min(queue.length * 76.0, 340.0).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: CrabifyColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CrabifyColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
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
            hasUpcomingTracks
                ? 'Tap a track to jump to it. Long press and drag to reorder in real time.'
                : 'Your queue currently ends with the current track.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: CrabifyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          if (!hasUpcomingTracks)
            Text(
              'No upcoming tracks',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: CrabifyColors.textMuted),
            )
          else
            SizedBox(
              height: listHeight,
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                primary: false,
                physics: const ClampingScrollPhysics(),
                itemCount: queue.length,
                onReorder:
                    (oldIndex, newIndex) => context
                        .read<LibraryService>()
                        .moveQueueItem(oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final item = queue[index];
                  final active = index == audio.currentIndex;
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(audio.queueEntryIdAt(index)),
                    index: index,
                    child: _QueueListTile(
                      track: item,
                      index: index,
                      active: active,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerService>(
      builder: (context, audio, _) {
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
                    physics: const ClampingScrollPhysics(),
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
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(audio.queueEntryIdAt(index)),
                        index: index,
                        child: _QueueListTile(
                          track: track,
                          index: index,
                          active: active,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QueueListTile extends StatelessWidget {
  const _QueueListTile({
    required this.track,
    required this.index,
    required this.active,
  });

  final MusicTrack track;
  final int index;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: key,
      onTap: () => context.read<LibraryService>().playQueueItem(index),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        backgroundColor:
            active ? CrabifyColors.accent : CrabifyColors.surfaceMuted,
        child: Text(
          '${index + 1}',
          style: TextStyle(
            color: active ? Colors.black : CrabifyColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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
            tooltip: 'Remove from queue',
            onPressed: () => context.read<LibraryService>().removeQueueItem(index),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
