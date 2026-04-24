import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/artist_profile.dart';
import '../models/music_collection.dart';
import '../models/music_track.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/skeletons.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  bool _searching = false;
  List<MusicTrack> _tracks = <MusicTrack>[];
  List<ArtistProfile> _artists = <ArtistProfile>[];
  List<MusicCollection> _collections = <MusicCollection>[];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final query = _searchController.text.trim();

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Search',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => _searchController.clear(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'What do you want to play?',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 24),
          if (query.isEmpty) ...<Widget>[
            Text(
              'Browse all',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: _browseTiles(context)),
            const SizedBox(height: 28),
            Text(
              'Popular artists',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 212,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final artist = library.artists[index];
                  return _ArtistCard(artist: artist);
                },
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemCount: library.artists.length.clamp(0, 6),
              ),
            ),
          ] else if (_searching) ...<Widget>[
            const TrackListSkeleton(count: 4),
          ] else ...<Widget>[
            if (_tracks.isEmpty && _artists.isEmpty && _collections.isEmpty)
              const _SearchEmpty()
            else ...<Widget>[
              if (_tracks.isNotEmpty) ...<Widget>[
                _SectionHeader(title: 'Songs'),
                ..._tracks.take(8).map((track) {
                  return TrackTile(
                    track: track,
                    onTap:
                        () => library.playTracks(
                          _tracks,
                          selectedTrackId: track.id,
                        ),
                    trailing: IconButton(
                      onPressed:
                          () => showTrackActionsSheet(context, track: track),
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                  );
                }),
              ],
              if (_artists.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                _SectionHeader(title: 'Artists'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 208,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder:
                        (context, index) =>
                            _ArtistCard(artist: _artists[index]),
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemCount: _artists.length,
                  ),
                ),
              ],
              if (_collections.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                _SectionHeader(title: 'Albums & playlists'),
                const SizedBox(height: 8),
                ..._collections.map((collection) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
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
                    leading: ArtworkTile(
                      seed: collection.id,
                      artworkPath: collection.artworkPath,
                      artworkUrl: collection.artworkUrl,
                      size: 58,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    title: Text(collection.title),
                    subtitle: Text(collection.subtitle),
                  );
                }),
              ],
            ],
          ],
        ],
      ),
    );
  }

  void _handleSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _performSearch);
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _searching = false;
        _tracks = <MusicTrack>[];
        _artists = <ArtistProfile>[];
        _collections = <MusicCollection>[];
      });
      return;
    }

    setState(() => _searching = true);
    final library = context.read<LibraryService>();
    final tracks = await library.searchTracks(query);
    final artists = library.searchArtists(query);
    final collections = library.searchCollections(query);

    if (!mounted) {
      return;
    }

    setState(() {
      _tracks = tracks;
      _artists = artists;
      _collections = collections;
      _searching = false;
    });
  }

  List<Widget> _browseTiles(BuildContext context) {
    final tiles = <MapEntry<String, Color>>[
      const MapEntry<String, Color>('Audius', Color(0xFF0A9396)),
      const MapEntry<String, Color>('Downloaded', Color(0xFF5F0F40)),
      const MapEntry<String, Color>('Playlists', Color(0xFF1D3557)),
      const MapEntry<String, Color>('Imported', Color(0xFF7C2D12)),
      const MapEntry<String, Color>('Liked Songs', Color(0xFF1D4ED8)),
      const MapEntry<String, Color>('Queue', Color(0xFF14532D)),
    ];

    return tiles.map((entry) {
      return Container(
        width: (MediaQuery.of(context).size.width - 54) / 2,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: entry.value,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          entry.key,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      );
    }).toList();
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.artist});

  final ArtistProfile artist;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 152,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ArtistDetailScreen(artist: artist),
            ),
          );
        },
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipOval(
              child: ArtworkTile(
                seed: artist.id,
                artworkPath: artist.artworkPath,
                artworkUrl: artist.artworkUrl,
                size: 152,
                icon: Icons.person_rounded,
                borderRadius: BorderRadius.circular(76),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Artist',
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CrabifyColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CrabifyColors.border),
      ),
      child: const Text(
        'No tracks, artists, or playlists matched that search yet.',
      ),
    );
  }
}
