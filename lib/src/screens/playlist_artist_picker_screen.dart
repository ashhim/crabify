import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/artist_profile.dart';
import '../models/music_collection.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/surface_card.dart';

class PlaylistArtistPickerScreen extends StatefulWidget {
  const PlaylistArtistPickerScreen({super.key, this.playlist});

  final MusicCollection? playlist;

  @override
  State<PlaylistArtistPickerScreen> createState() =>
      _PlaylistArtistPickerScreenState();
}

class _PlaylistArtistPickerScreenState
    extends State<PlaylistArtistPickerScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedArtistIds = <String>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.playlist?.title ?? '';
    _selectedArtistIds.addAll(widget.playlist?.artistIds ?? const <String>[]);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final query = _searchController.text.trim().toLowerCase();
    final artists =
        library.artists.where((artist) {
          if (query.isEmpty) {
            return true;
          }
          return artist.name.toLowerCase().contains(query);
        }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: CrabifyColors.topBar,
        title: Text(
          widget.playlist == null
              ? 'Create playlist from artists'
              : 'Edit playlist artists',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.playlist == null
                        ? 'Build playlist from artists'
                        : 'Manage artist membership',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Playlist title',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Search artists',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  if (_selectedArtistIds.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          _selectedArtistIds.map((artistId) {
                            final artist = library.artistById(artistId);
                            return InputChip(
                              label: Text(artist?.name ?? artistId),
                              onDeleted:
                                  _saving
                                      ? null
                                      : () => setState(
                                        () =>
                                            _selectedArtistIds.remove(artistId),
                                      ),
                            );
                          }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (artists.isEmpty)
              const SurfaceCard(
                child: Text(
                  'No artists match that search yet. Import or download tracks to build artist-linked playlists.',
                ),
              )
            else
              ...artists.map((artist) {
                final selected = _selectedArtistIds.contains(artist.id);
                final trackCount = library.tracksForArtist(artist).length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SurfaceCard(
                    padding: EdgeInsets.zero,
                    child: CheckboxListTile(
                      value: selected,
                      onChanged:
                          _saving
                              ? null
                              : (_) => setState(() {
                                if (selected) {
                                  _selectedArtistIds.remove(artist.id);
                                } else {
                                  _selectedArtistIds.add(artist.id);
                                }
                              }),
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: ArtworkTile(
                        seed: artist.id,
                        artworkPath: artist.artworkPath,
                        artworkUrl: artist.artworkUrl,
                        size: 54,
                        borderRadius: BorderRadius.circular(16),
                        icon: Icons.person_rounded,
                      ),
                      title: Text(artist.name),
                      subtitle: Text(
                        trackCount == 1 ? '1 song' : '$trackCount songs',
                      ),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(library),
              icon:
                  _saving
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.queue_music_rounded),
              label: Text(
                _saving
                    ? 'Saving...'
                    : widget.playlist == null
                    ? 'Create playlist'
                    : 'Save artist selection',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(LibraryService library) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a playlist title.')));
      return;
    }
    if (widget.playlist == null && _selectedArtistIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one artist.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (widget.playlist == null) {
        final playlist = await library.createPlaylistFromArtists(
          title: title,
          artistIds: _selectedArtistIds.toList(),
        );
        if (!mounted) {
          return;
        }
        Navigator.of(context).pop(playlist);
        return;
      }

      await library.updatePlaylistArtistSelection(
        playlistId: widget.playlist!.id,
        title: title,
        artistIds: _selectedArtistIds.toList(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
