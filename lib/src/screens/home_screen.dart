import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_collection.dart';
import '../models/music_track.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/skeletons.dart';
import '../widgets/surface_card.dart';
import '../widgets/track_actions.dart';
import 'detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenUpload});

  final VoidCallback onOpenUpload;

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryService>(
      builder: (context, library, _) {
        final quickPicks =
            library.recentTracks.isNotEmpty
                ? library.recentTracks.take(4).toList()
                : library.onlineTracks.take(4).toList();
        final playlists = library.playlists.take(6).toList();
        final onlineTracks = library.onlineTracks.take(8).toList();
        final offlineTracks =
            <MusicTrack>[
              ...library.downloadedTracks,
              ...library.importedTracks,
            ].take(6).toList();

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0xFF252B38),
                CrabifyColors.background,
                CrabifyColors.background,
              ],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: <Widget>[
                _TopBar(onOpenUpload: onOpenUpload),
                const SizedBox(height: 22),
                Text(
                  'Good evening',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                if (library.onlineError != null) ...<Widget>[
                  _StatusBanner(message: library.onlineError!),
                  const SizedBox(height: 18),
                ],
                if (library.isLoading &&
                    library.onlineTracks.isEmpty) ...<Widget>[
                  const PlaylistSkeletonCarousel(),
                  const SizedBox(height: 24),
                  const TrackListSkeleton(),
                ] else ...<Widget>[
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: quickPicks.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 74,
                        ),
                    itemBuilder: (context, index) {
                      final track = quickPicks[index];
                      return _QuickPickCard(
                        track: track,
                        onTap:
                            () => library.playTracks(
                              quickPicks,
                              selectedTrackId: track.id,
                            ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  _SectionHeader(
                    title: 'Crabify playlists',
                    actionLabel: 'See all',
                    onAction: () {
                      if (playlists.isEmpty) {
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) => CollectionDetailScreen(
                                collection: playlists.first,
                              ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 240,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final collection = playlists[index];
                        return _PlaylistCard(collection: collection);
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemCount: playlists.length,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _SectionHeader(title: 'Fresh from Audius'),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 240,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final track = onlineTracks[index];
                        return _TrackCard(
                          track: track,
                          onTap:
                              () => library.playTracks(
                                onlineTracks,
                                selectedTrackId: track.id,
                              ),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemCount: onlineTracks.length,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _SectionHeader(
                    title: 'Offline library',
                    actionLabel: offlineTracks.isEmpty ? null : 'Manage',
                  ),
                  const SizedBox(height: 14),
                  if (offlineTracks.isEmpty)
                    const SurfaceCard(
                      child: Text(
                        'Import local files or download eligible online tracks to keep playback going when you are offline.',
                      ),
                    )
                  else
                    Column(
                      children:
                          offlineTracks.map((track) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              onTap:
                                  () => library.playTracks(
                                    offlineTracks,
                                    selectedTrackId: track.id,
                                  ),
                              leading: ArtworkTile(
                                seed: track.cacheKey,
                                artworkPath: track.artworkPath,
                                artworkUrl: track.artworkUrl,
                                size: 56,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              title: Text(track.title),
                              subtitle: Text(track.subtitle),
                              trailing: IconButton(
                                onPressed:
                                    () => showTrackActionsSheet(
                                      context,
                                      track: track,
                                    ),
                                icon: const Icon(Icons.more_horiz_rounded),
                              ),
                            );
                          }).toList(),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onOpenUpload});

  final VoidCallback onOpenUpload;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _RoundIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: () {}),
        const SizedBox(width: 10),
        _RoundIconButton(icon: Icons.arrow_forward_ios_rounded, onTap: () {}),
        const Spacer(),
        FilledButton.tonal(
          onPressed: onOpenUpload,
          child: const Text('Upload'),
        ),
        const SizedBox(width: 10),
        _RoundIconButton(
          icon: Icons.shuffle_rounded,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Shuffle from the player or any collection view.',
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

class _QuickPickCard extends StatelessWidget {
  const _QuickPickCard({required this.track, required this.onTap});

  final MusicTrack track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: CrabifyColors.surfaceRaised,
      padding: EdgeInsets.zero,
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Row(
        children: <Widget>[
          ArtworkTile(
            seed: track.cacheKey,
            artworkPath: track.artworkPath,
            artworkUrl: track.artworkUrl,
            size: 74,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.collection});

  final MusicCollection collection;

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryService>();
    final tracks = library.tracksForCollection(collection);

    return SizedBox(
      width: 164,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CollectionDetailScreen(collection: collection),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                ArtworkTile(
                  seed: collection.id,
                  artworkPath: collection.artworkPath,
                  artworkUrl: collection.artworkUrl,
                  size: 164,
                  borderRadius: BorderRadius.circular(20),
                  icon: Icons.queue_music_rounded,
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: InkWell(
                    onTap:
                        tracks.isEmpty
                            ? null
                            : () => library.playTracks(
                              tracks,
                              selectedTrackId: tracks.first.id,
                            ),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: CrabifyColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              collection.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              collection.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: CrabifyColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({required this.track, required this.onTap});

  final MusicTrack track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 164,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ArtworkTile(
              seed: track.cacheKey,
              artworkPath: track.artworkPath,
              artworkUrl: track.artworkUrl,
              size: 164,
              borderRadius: BorderRadius.circular(20),
            ),
            const SizedBox(height: 10),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              track.artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: CrabifyColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => showTrackActionsSheet(context, track: track),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('More'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: const Color(0xFF1E2E24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.info_outline_rounded,
              color: CrabifyColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CrabifyColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
