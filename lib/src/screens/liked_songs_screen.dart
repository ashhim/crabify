import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_track.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';

class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final filteredTracks = _filterTracks(
      library.likedTracks,
      _searchController.text,
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF312E81),
            Color(0xFF1F1A4F),
            CrabifyColors.background,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          children: <Widget>[
            Text(
              'Liked songs',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              '${library.likedTracks.length} tracks saved across online, downloaded, and imported music.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CrabifyColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search liked songs',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                FilledButton.icon(
                  onPressed:
                      filteredTracks.isEmpty
                          ? null
                          : () => library.playTracks(
                            filteredTracks,
                            selectedTrackId: filteredTracks.first.id,
                          ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed:
                      filteredTracks.isEmpty
                          ? null
                          : () => library.playTracks(
                            filteredTracks,
                            selectedTrackId: filteredTracks.first.id,
                            shuffle: true,
                          ),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Shuffle'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (filteredTracks.isEmpty)
              const _LikedEmpty()
            else
              ...filteredTracks.asMap().entries.map((entry) {
                final index = entry.key;
                final track = entry.value;
                return TrackTile(
                  track: track,
                  leadingIndex: index + 1,
                  onTap:
                      () => library.playTracks(
                        filteredTracks,
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
        ),
      ),
    );
  }

  List<MusicTrack> _filterTracks(List<MusicTrack> tracks, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return tracks;
    }

    return tracks.where((track) {
      final haystack =
          <String>[
            track.title,
            track.artistName,
            track.albumTitle,
          ].join(' ').toLowerCase();
      return haystack.contains(normalized);
    }).toList();
  }
}

class _LikedEmpty extends StatelessWidget {
  const _LikedEmpty();

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
        'Heart a few songs from Home, Search, or the player and they will appear here.',
      ),
    );
  }
}
