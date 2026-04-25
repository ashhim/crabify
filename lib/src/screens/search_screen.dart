import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/artist_profile.dart';
import '../models/music_collection.dart';
import '../models/music_track.dart';
import '../services/audio_player_service.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/skeletons.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';
import 'detail_screen.dart';

enum _SearchTag { crabify, downloaded, playlists, imported, liked, queue }

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
    final audio = context.watch<AudioPlayerService>();
    final query = _searchController.text.trim();
    final activeTag = _tagFromKey(library.selectedSearchTag);

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
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _browseTiles(context, activeTag),
            ),
            const SizedBox(height: 18),
            _SearchTagContent(tag: activeTag, library: library, audio: audio),
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

  List<Widget> _browseTiles(BuildContext context, _SearchTag activeTag) {
    final tiles = <({String label, Color color, _SearchTag tag})>[
      (
        label: 'Crabify',
        color: const Color(0xFF0A9396),
        tag: _SearchTag.crabify,
      ),
      (
        label: 'Download',
        color: const Color(0xFF5F0F40),
        tag: _SearchTag.downloaded,
      ),
      (
        label: 'Playlists',
        color: const Color(0xFF1D3557),
        tag: _SearchTag.playlists,
      ),
      (
        label: 'Imported',
        color: const Color(0xFF7C2D12),
        tag: _SearchTag.imported,
      ),
      (
        label: 'Liked Songs',
        color: const Color(0xFF1D4ED8),
        tag: _SearchTag.liked,
      ),
      (label: 'Queue', color: const Color(0xFF14532D), tag: _SearchTag.queue),
    ];

    return tiles.map((entry) {
      final active = entry.tag == activeTag;
      return InkWell(
        onTap:
            () => context.read<LibraryService>().setSelectedSearchTag(
              _keyForTag(entry.tag),
            ),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: (MediaQuery.of(context).size.width - 54) / 2,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: entry.color,
            borderRadius: BorderRadius.circular(20),
            border:
                active
                    ? Border.all(color: CrabifyColors.accent, width: 2)
                    : null,
            boxShadow:
                active
                    ? <BoxShadow>[
                      BoxShadow(
                        color: CrabifyColors.accent.withValues(alpha: 0.2),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                    : null,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  entry.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                active
                    ? Icons.radio_button_checked_rounded
                    : Icons.arrow_forward_rounded,
                size: 18,
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  _SearchTag _tagFromKey(String key) {
    return _SearchTag.values.firstWhere(
      (tag) => _keyForTag(tag) == key,
      orElse: () => _SearchTag.crabify,
    );
  }

  String _keyForTag(_SearchTag tag) {
    return switch (tag) {
      _SearchTag.crabify => 'crabify',
      _SearchTag.downloaded => 'downloaded',
      _SearchTag.playlists => 'playlists',
      _SearchTag.imported => 'imported',
      _SearchTag.liked => 'liked',
      _SearchTag.queue => 'queue',
    };
  }
}

class _SearchTagContent extends StatelessWidget {
  const _SearchTagContent({
    required this.tag,
    required this.library,
    required this.audio,
  });

  final _SearchTag tag;
  final LibraryService library;
  final AudioPlayerService audio;

  @override
  Widget build(BuildContext context) {
    return switch (tag) {
      _SearchTag.crabify => _TrackTagSection(
        title: 'Crabify online',
        tracks: library.onlineTracks,
        emptyMessage: 'Crabify is waiting for Audius tracks to load.',
      ),
      _SearchTag.downloaded => _TrackTagSection(
        title: 'Downloaded',
        tracks: library.downloadedTracks,
        emptyMessage: 'Downloaded songs will appear here for offline playback.',
      ),
      _SearchTag.imported => _TrackTagSection(
        title: 'Imported',
        tracks: library.importedTracks,
        emptyMessage: 'Imported songs from this device will appear here.',
      ),
      _SearchTag.liked => _TrackTagSection(
        title: 'Liked songs',
        tracks: library.likedTracks,
        emptyMessage: 'Like songs from any track menu or player screen.',
      ),
      _SearchTag.playlists => _PlaylistTagSection(library: library),
      _SearchTag.queue => _QueueTagSection(audio: audio),
    };
  }
}

class _TrackTagSection extends StatelessWidget {
  const _TrackTagSection({
    required this.title,
    required this.tracks,
    required this.emptyMessage,
  });

  final String title;
  final List<MusicTrack> tracks;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryService>();
    return _TagPanel(
      title: title,
      action:
          tracks.isEmpty
              ? null
              : TextButton.icon(
                onPressed:
                    () => library.playTracks(
                      tracks,
                      selectedTrackId: tracks.first.id,
                      shuffle: true,
                    ),
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Shuffle'),
              ),
      child:
          tracks.isEmpty
              ? Text(emptyMessage)
              : Column(
                children:
                    tracks.take(6).map((track) {
                      return TrackTile(
                        track: track,
                        onTap:
                            () => library.playTracks(
                              tracks,
                              selectedTrackId: track.id,
                            ),
                        trailing: IconButton(
                          onPressed:
                              () =>
                                  showTrackActionsSheet(context, track: track),
                          icon: const Icon(Icons.more_horiz_rounded),
                        ),
                      );
                    }).toList(),
              ),
    );
  }
}

class _PlaylistTagSection extends StatelessWidget {
  const _PlaylistTagSection({required this.library});

  final LibraryService library;

  @override
  Widget build(BuildContext context) {
    return _TagPanel(
      title: 'Playlists',
      action:
          library.playlists.isEmpty
              ? null
              : TextButton.icon(
                onPressed: library.shuffleAllPlaylists,
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Shuffle all'),
              ),
      child:
          library.playlists.isEmpty
              ? const Text('Create playlists from Your library first.')
              : Column(
                children:
                    library.playlists.take(6).map((playlist) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => CollectionDetailScreen(
                                    collection: playlist,
                                  ),
                            ),
                          );
                        },
                        leading: ArtworkTile(
                          seed: playlist.id,
                          artworkPath: playlist.artworkPath,
                          artworkUrl: playlist.artworkUrl,
                          size: 54,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        title: Text(playlist.title),
                        subtitle: Text('${playlist.trackIds.length} tracks'),
                        trailing: IconButton(
                          onPressed:
                              playlist.trackIds.isEmpty
                                  ? null
                                  : () => library.playPlaylist(
                                    playlist,
                                    shuffle: true,
                                  ),
                          icon: const Icon(Icons.shuffle_rounded),
                        ),
                      );
                    }).toList(),
              ),
    );
  }
}

class _QueueTagSection extends StatelessWidget {
  const _QueueTagSection({required this.audio});

  final AudioPlayerService audio;

  @override
  Widget build(BuildContext context) {
    return _TagPanel(
      title: 'Queue',
      child:
          audio.queue.isEmpty
              ? const Text('Start playback, then queue items will appear here.')
              : ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: audio.queue.length,
                onReorder:
                    (oldIndex, newIndex) => context
                        .read<LibraryService>()
                        .moveQueueItem(oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final track = audio.queue[index];
                  final active = index == audio.currentIndex;
                  return TrackTile(
                    key: ValueKey('search-queue-${track.cacheKey}-$index'),
                    track: track,
                    leadingIndex: index + 1,
                    active: active,
                    onTap:
                        () =>
                            context.read<LibraryService>().playQueueItem(index),
                    trailing: IconButton(
                      onPressed:
                          () => context.read<LibraryService>().removeQueueItem(
                            index,
                          ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  );
                },
              ),
    );
  }
}

class _TagPanel extends StatelessWidget {
  const _TagPanel({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CrabifyColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CrabifyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
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
