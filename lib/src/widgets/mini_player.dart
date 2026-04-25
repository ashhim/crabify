import 'package:flutter/material.dart';

import '../models/music_track.dart';
import '../services/audio_player_service.dart';
import '../theme/crabify_theme.dart';
import 'artwork_tile.dart';
import 'surface_card.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.audioPlayerService,
    required this.onOpenPlayer,
  });

  final AudioPlayerService audioPlayerService;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final track = audioPlayerService.currentTrack;
    if (track == null) {
      return const SizedBox.shrink();
    }
    final busyForCurrentTrack =
        audioPlayerService.isLoading &&
        audioPlayerService.loadingTrackId == track.id;
    final subtitle =
        audioPlayerService.lastErrorMessage ??
        (busyForCurrentTrack ? 'Connecting to audio...' : null);
    final subtitleColor =
        audioPlayerService.lastErrorMessage != null
            ? const Color(0xFFFFB4A5)
            : CrabifyColors.textSecondary;

    final progress =
        audioPlayerService.duration.inMilliseconds == 0
            ? 0.0
            : audioPlayerService.position.inMilliseconds /
                audioPlayerService.duration.inMilliseconds;

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
            LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: CrabifyColors.accent,
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
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
                        busyForCurrentTrack
                            ? null
                            : audioPlayerService.previous,
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
                    onPressed:
                        busyForCurrentTrack ? null : audioPlayerService.next,
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
              ),
            ),
          ],
        ),
      ),
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
