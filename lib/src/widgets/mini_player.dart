import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_track.dart';
import '../services/audio_player_service.dart';
import '../theme/crabify_theme.dart';
import 'artwork_tile.dart';
import 'surface_card.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onOpenPlayer});

  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final track = context.select<AudioPlayerService, MusicTrack?>(
      (audio) => audio.currentTrack,
    );
    if (track == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: SurfaceCard(
        color: CrabifyColors.surfaceRaised,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(20),
        onTap: onOpenPlayer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _MiniPlayerProgress(track: track),
            Padding(
              padding: const EdgeInsets.all(10),
              child: _MiniPlayerContent(track: track),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayerProgress extends StatelessWidget {
  const _MiniPlayerProgress({required this.track});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    final progress = context.select<AudioPlayerService, double>((audio) {
      final durationMillis = audio.duration.inMilliseconds;
      if (durationMillis <= 0) {
        return 0;
      }
      return (audio.position.inMilliseconds / durationMillis).clamp(0, 1);
    });

    return LinearProgressIndicator(
      value: progress,
      minHeight: 2,
      backgroundColor: Colors.transparent,
      color: CrabifyColors.accent,
    );
  }
}

class _MiniPlayerContent extends StatelessWidget {
  const _MiniPlayerContent({required this.track});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerService>(
      builder: (context, audioPlayerService, _) {
        final busyForCurrentTrack =
            audioPlayerService.isLoading &&
            audioPlayerService.loadingTrackId == track.id;
        final subtitle =
            audioPlayerService.lastErrorMessage ??
            (busyForCurrentTrack ? 'Connecting to audio...' : null);
        final subtitleColor =
            audioPlayerService.lastErrorMessage != null
                ? CrabifyColors.dangerSoft
                : CrabifyColors.textSecondary;

        return Row(
          children: <Widget>[
            ArtworkTile(
              seed: track.cacheKey,
              artworkPath: track.artworkPath,
              artworkUrl: track.artworkUrl,
              size: 46,
              borderRadius: BorderRadius.circular(12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TrackText(
                track: track,
                statusMessage: subtitle,
                statusColor: subtitleColor,
              ),
            ),
            IconButton(
              onPressed:
                  busyForCurrentTrack ? null : audioPlayerService.previous,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            if (busyForCurrentTrack)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox.square(
                  dimension: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.3),
                ),
              )
            else
              IconButton(
                onPressed: audioPlayerService.togglePlayback,
                icon: Icon(
                  audioPlayerService.isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 34,
                ),
              ),
            IconButton(
              onPressed: busyForCurrentTrack ? null : audioPlayerService.next,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            IconButton(
              onPressed:
                  busyForCurrentTrack || !audioPlayerService.canStop
                      ? null
                      : audioPlayerService.stop,
              icon: const Icon(Icons.stop_rounded),
            ),
          ],
        );
      },
    );
  }
}

class _TrackText extends StatelessWidget {
  const _TrackText({
    required this.track,
    this.statusMessage,
    this.statusColor = CrabifyColors.textSecondary,
  });

  final MusicTrack track;
  final String? statusMessage;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          statusMessage ?? track.artistName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color:
                statusMessage == null
                    ? CrabifyColors.textSecondary
                    : statusColor,
          ),
        ),
      ],
    );
  }
}
