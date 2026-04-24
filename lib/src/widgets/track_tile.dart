import 'package:flutter/material.dart';

import '../models/music_track.dart';
import '../theme/crabify_theme.dart';
import 'artwork_tile.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.trailing,
    this.leadingIndex,
    this.active = false,
  });

  final MusicTrack track;
  final VoidCallback? onTap;
  final Widget? trailing;
  final int? leadingIndex;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final titleColor =
        active ? CrabifyColors.accent : CrabifyColors.textPrimary;
    final subtitleStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: CrabifyColors.textSecondary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: <Widget>[
              if (leadingIndex != null) ...<Widget>[
                SizedBox(
                  width: 28,
                  child: Text(
                    '$leadingIndex',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: CrabifyColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              ArtworkTile(
                seed: track.cacheKey,
                artworkPath: track.artworkPath,
                artworkUrl: track.artworkUrl,
                size: 56,
                borderRadius: BorderRadius.circular(14),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
