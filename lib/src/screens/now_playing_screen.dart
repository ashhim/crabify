import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
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
    return Consumer2<AudioPlayerService, LibraryService>(
      builder: (context, audio, library, _) {
        final track = audio.currentTrack;
        if (track == null) {
          return Scaffold(
            appBar: AppBar(backgroundColor: CrabifyColors.topBar),
            body: const Center(
              child: Text(
                'Pick something from the library to start listening.',
              ),
            ),
          );
        }

        final total =
            audio.duration.inMilliseconds <= 0
                ? (track.duration?.inMilliseconds ?? 1)
                : audio.duration.inMilliseconds;
        final currentValue = audio.position.inMilliseconds.clamp(0, total);
        final progress = library.progressFor(track.id);
        final busyForCurrentTrack =
            audio.isBusy && audio.activeTrackId == track.id;

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
                      onPressed: () => library.toggleLike(track.id),
                      icon: Icon(
                        library.isLiked(track.id)
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color:
                            library.isLiked(track.id)
                                ? CrabifyColors.accent
                                : CrabifyColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      onPressed:
                          track.downloadable &&
                                  !track.hasValidLocalSource &&
                                  !library.isDownloaded(track.id) &&
                                  progress == null
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
                          progress != null
                              ? SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: progress,
                                ),
                              )
                              : Icon(
                                library.isDownloaded(track.id)
                                    ? Icons.download_done_rounded
                                    : Icons.download_rounded,
                              ),
                    ),
                  ],
                ),
                if (audio.lastErrorMessage != null) ...<Widget>[
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
                        color: const Color(0xFFFFB4A5),
                      ),
                    ),
                  ),
                ],
                if (busyForCurrentTrack) ...<Widget>[
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
                ],
                const SizedBox(height: 18),
                Slider(
                  value: currentValue.toDouble(),
                  min: 0,
                  max: total.toDouble(),
                  onChanged:
                      busyForCurrentTrack
                          ? null
                          : (value) =>
                              audio.seek(Duration(milliseconds: value.round())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        _formatDuration(audio.position),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CrabifyColors.textSecondary,
                        ),
                      ),
                      Text(
                        _formatDuration(audio.duration),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CrabifyColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    IconButton(
                      onPressed:
                          busyForCurrentTrack ? null : audio.toggleShuffle,
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
                      onPressed:
                          busyForCurrentTrack ? null : audio.togglePlayback,
                      style: IconButton.styleFrom(
                        backgroundColor: CrabifyColors.textPrimary,
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
                      onPressed:
                          busyForCurrentTrack ? null : audio.cycleLoopMode,
                      icon: Icon(
                        audio.loopMode == LoopMode.off
                            ? Icons.repeat_rounded
                            : audio.loopMode == LoopMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        color:
                            audio.loopMode == LoopMode.off
                                ? CrabifyColors.textPrimary
                                : CrabifyColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _QueuePreview(track: track),
              ],
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

class _QueuePreview extends StatelessWidget {
  const _QueuePreview({required this.track});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioPlayerService>();
    final upcoming = audio.queue.skip(audio.currentIndex + 1).take(3).toList();

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
            'Up next',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            upcoming.isEmpty
                ? 'Your queue ends with ${track.title}.'
                : 'Drag tracks in the queue panel to rearrange the order.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: CrabifyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          if (upcoming.isEmpty)
            Text(
              'No upcoming tracks',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: CrabifyColors.textMuted),
            )
          else
            ...upcoming.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${item.title} • ${item.artistName}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CrabifyColors.textPrimary,
                  ),
                ),
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
                  'Tap to jump, drag to reorder, or remove tracks you no longer want.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CrabifyColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 420,
                  child: ReorderableListView.builder(
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
                      return ListTile(
                        key: ValueKey(track.cacheKey),
                        onTap:
                            () => context.read<LibraryService>().playQueueItem(
                              index,
                            ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        leading: CircleAvatar(
                          backgroundColor:
                              active
                                  ? CrabifyColors.accent
                                  : CrabifyColors.surface,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color:
                                  active
                                      ? Colors.black
                                      : CrabifyColors.textPrimary,
                            ),
                          ),
                        ),
                        title: Text(
                          track.title,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            color:
                                active
                                    ? CrabifyColors.accent
                                    : CrabifyColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(track.artistName),
                        trailing: IconButton(
                          onPressed:
                              () => context
                                  .read<LibraryService>()
                                  .removeQueueItem(index),
                          icon: const Icon(Icons.close_rounded),
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
