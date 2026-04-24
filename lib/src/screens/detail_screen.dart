import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/artist_profile.dart';
import '../models/music_collection.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';

class CollectionDetailScreen extends StatelessWidget {
  const CollectionDetailScreen({super.key, required this.collection});

  final MusicCollection collection;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final tracks = library.tracksForCollection(collection);

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 320,
            backgroundColor: CrabifyColors.topBar,
            flexibleSpace: FlexibleSpaceBar(
              background: _DetailHeader(
                seed: collection.id,
                artworkPath: collection.artworkPath,
                artworkUrl: collection.artworkUrl,
                title: collection.title,
                subtitle: collection.subtitle,
                description: collection.description,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: <Widget>[
                  FilledButton.icon(
                    onPressed:
                        tracks.isEmpty
                            ? null
                            : () => library.playTracks(
                              tracks,
                              selectedTrackId: tracks.first.id,
                            ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed:
                        tracks.isEmpty
                            ? null
                            : () => library.playTracks(
                              tracks,
                              selectedTrackId: tracks.first.id,
                              shuffle: true,
                            ),
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('Shuffle'),
                  ),
                ],
              ),
            ),
          ),
          if (tracks.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: _EmptyState(
                  title: 'Nothing here yet',
                  message:
                      'This collection is ready, but it does not have any tracks in it yet.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return TrackTile(
                    track: track,
                    leadingIndex: index + 1,
                    onTap:
                        () => library.playTracks(
                          tracks,
                          selectedTrackId: track.id,
                        ),
                    trailing: IconButton(
                      onPressed:
                          () => showTrackActionsSheet(context, track: track),
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemCount: tracks.length,
              ),
            ),
        ],
      ),
    );
  }
}

class ArtistDetailScreen extends StatelessWidget {
  const ArtistDetailScreen({super.key, required this.artist});

  final ArtistProfile artist;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final tracks = library.tracksForArtist(artist);
    final collections =
        artist.collectionIds
            .map(library.collectionById)
            .whereType<MusicCollection>()
            .toList();

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _DetailHeader(
            seed: artist.id,
            artworkPath: artist.artworkPath,
            artworkUrl: artist.artworkUrl,
            title: artist.name,
            subtitle: 'Artist',
            description: artist.description,
            height: 360,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: <Widget>[
                FilledButton.icon(
                  onPressed:
                      tracks.isEmpty
                          ? null
                          : () => library.playTracks(
                            tracks,
                            selectedTrackId: tracks.first.id,
                          ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Popular'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed:
                      tracks.isEmpty
                          ? null
                          : () => library.playTracks(
                            tracks,
                            selectedTrackId: tracks.first.id,
                            shuffle: true,
                          ),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Shuffle'),
                ),
              ],
            ),
          ),
          _SectionHeader(title: 'Popular'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child:
                tracks.isEmpty
                    ? const _EmptyState(
                      title: 'No tracks yet',
                      message:
                          'This artist page will fill in automatically as you import or upload more songs.',
                    )
                    : Column(
                      children:
                          tracks.take(6).toList().asMap().entries.map((entry) {
                            final index = entry.key;
                            final track = entry.value;
                            return TrackTile(
                              track: track,
                              leadingIndex: index + 1,
                              onTap:
                                  () => library.playTracks(
                                    tracks,
                                    selectedTrackId: track.id,
                                  ),
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
          ),
          if (collections.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _SectionHeader(title: 'Releases'),
            SizedBox(
              height: 216,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final collection = collections[index];
                  return SizedBox(
                    width: 152,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => CollectionDetailScreen(
                                  collection: collection,
                                ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          ArtworkTile(
                            seed: collection.id,
                            artworkPath: collection.artworkPath,
                            artworkUrl: collection.artworkUrl,
                            size: 152,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            collection.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            collection.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: CrabifyColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemCount: collections.length,
              ),
            ),
          ],
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.seed,
    required this.title,
    required this.subtitle,
    required this.description,
    this.artworkPath,
    this.artworkUrl,
    this.height = 320,
  });

  final String seed;
  final String title;
  final String subtitle;
  final String description;
  final String? artworkPath;
  final String? artworkUrl;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF2F3343),
            CrabifyColors.topBar,
            CrabifyColors.background,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  ArtworkTile(
                    seed: seed,
                    artworkPath: artworkPath,
                    artworkUrl: artworkUrl,
                    size: 142,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          subtitle.toUpperCase(),
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(
                            color: CrabifyColors.textSecondary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: CrabifyColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CrabifyColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CrabifyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: CrabifyColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
