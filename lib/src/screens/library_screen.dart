import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_track.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/surface_card.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';
import 'detail_screen.dart';
import 'import_track_screen.dart';

enum _LibraryFilter { playlists, liked, downloads, imported, uploads, recent }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onOpenUpload});

  final VoidCallback onOpenUpload;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final filter = _filterFromKey(library.selectedLibraryFilter);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Your library',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _createPlaylist,
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: widget.onOpenUpload,
                icon: const Icon(Icons.cloud_upload_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: _SummaryCard(
                  title: 'Liked songs',
                  count: library.likedTracks.length,
                  color: const Color(0xFF312E81),
                  active: filter == _LibraryFilter.liked,
                  onTap:
                      () => library.setSelectedLibraryFilter(
                        _keyForFilter(_LibraryFilter.liked),
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Downloads',
                  count: library.downloadedTracks.length,
                  color: const Color(0xFF14532D),
                  active: filter == _LibraryFilter.downloads,
                  onTap:
                      () => library.setSelectedLibraryFilter(
                        _keyForFilter(_LibraryFilter.downloads),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _SummaryCard(
                  title: 'Imported',
                  count: library.importedTracks.length,
                  color: const Color(0xFF7C2D12),
                  active: filter == _LibraryFilter.imported,
                  onTap:
                      () => library.setSelectedLibraryFilter(
                        _keyForFilter(_LibraryFilter.imported),
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Uploads',
                  count: library.uploadedTracks.length,
                  color: const Color(0xFF0F766E),
                  active: filter == _LibraryFilter.uploads,
                  onTap:
                      () => library.setSelectedLibraryFilter(
                        _keyForFilter(_LibraryFilter.uploads),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            children:
                _LibraryFilter.values.map((candidate) {
                  return ChoiceChip(
                    selected: filter == candidate,
                    label: Text(_labelForFilter(candidate)),
                    onSelected:
                        (_) => library.setSelectedLibraryFilter(
                          _keyForFilter(candidate),
                        ),
                  );
                }).toList(),
          ),
          const SizedBox(height: 20),
          if (filter == _LibraryFilter.playlists) ...<Widget>[
            _ActionBanner(
              title: 'Make this library yours',
              message:
                  'Create playlists, import audio files from your device, and keep offline tracks close.',
              actionLabel: 'Import files',
              onAction: _importFiles,
            ),
            const SizedBox(height: 18),
            if (library.playlists.isEmpty)
              const _EmptyCard(
                title: 'No playlists yet',
                message:
                    'Create your first playlist, then add online or offline tracks to it from any track menu.',
              )
            else ...<Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: library.shuffleAllPlaylists,
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Shuffle all playlists'),
                ),
              ),
              const SizedBox(height: 8),
              ...library.playlists.map((playlist) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) =>
                                  CollectionDetailScreen(collection: playlist),
                        ),
                      ),
                  leading: ArtworkTile(
                    seed: playlist.id,
                    artworkPath: playlist.artworkPath,
                    artworkUrl: playlist.artworkUrl,
                    size: 58,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: Text(playlist.title),
                  trailing: IconButton(
                    onPressed:
                        playlist.trackIds.isEmpty
                            ? null
                            : () =>
                                library.playPlaylist(playlist, shuffle: true),
                    icon: const Icon(Icons.shuffle_rounded),
                  ),
                  subtitle: Text(
                    '${playlist.subtitle} • ${playlist.trackIds.length} tracks',
                  ),
                );
              }),
            ],
          ] else ...<Widget>[
            if (filter == _LibraryFilter.liked)
              _TrackSection(
                title: 'Liked songs',
                tracks: library.likedTracks,
                emptyTitle: 'No liked songs yet',
                emptyMessage:
                    'Heart tracks from Home, Search, playlists, or the player and they will stay here.',
              ),
            if (filter == _LibraryFilter.downloads)
              _TrackSection(
                title: 'Downloaded songs',
                tracks: library.downloadedTracks,
                emptyTitle: 'No downloads yet',
                emptyMessage:
                    'Save tracks from the online catalog and they will appear here for offline playback.',
              ),
            if (filter == _LibraryFilter.imported)
              _TrackSection(
                title: 'Imported audio',
                tracks: library.importedTracks,
                emptyTitle: 'No imported tracks yet',
                emptyMessage:
                    'Use the import button to scan chosen files from your device and bring them into Crabify.',
                actionLabel: 'Import',
                onAction: _importFiles,
              ),
            if (filter == _LibraryFilter.uploads)
              _TrackSection(
                title: 'Uploaded tracks',
                tracks: library.uploadedTracks,
                emptyTitle: 'No uploads yet',
                emptyMessage:
                    'Save a track locally from the upload screen, then publish it through your secure backend when one is configured.',
              ),
            if (filter == _LibraryFilter.recent)
              _TrackSection(
                title: 'Recent plays',
                tracks: library.recentTracks,
                emptyTitle: 'Nothing played yet',
                emptyMessage:
                    'Start a queue from Home or Search and Crabify will build your recent shelf automatically.',
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _importFiles() async {
    final importMode = await showModalBottomSheet<_ImportMode>(
      context: context,
      backgroundColor: CrabifyColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Import local audio',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quick import saves the file immediately. Custom import lets you edit title, artist, album, genre, and cover before saving.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CrabifyColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flash_on_rounded),
                  title: const Text('Quick import'),
                  subtitle: const Text(
                    'Auto-copy the song, metadata, and embedded artwork now.',
                  ),
                  onTap: () => Navigator.of(context).pop(_ImportMode.quick),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('Custom import'),
                  subtitle: const Text(
                    'Choose one file, edit metadata, then save it to the library.',
                  ),
                  onTap: () => Navigator.of(context).pop(_ImportMode.custom),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (importMode == null || !mounted) {
      return;
    }

    try {
      if (importMode == _ImportMode.quick) {
        final library = context.read<LibraryService>();
        final beforeCount = library.importedTracks.length;
        await library.quickImportTracks();
        if (!mounted) {
          return;
        }
        final importedCount = library.importedTracks.length - beforeCount;
        if (importedCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                importedCount == 1
                    ? '1 file imported into your library'
                    : '$importedCount files imported into your library',
              ),
            ),
          );
        }
        return;
      }

      final draft =
          await context.read<LibraryService>().createCustomImportDraft();
      if (draft == null || !mounted) {
        return;
      }

      final MusicTrack? importedTrack = await Navigator.of(
        context,
      ).push<MusicTrack>(
        MaterialPageRoute<MusicTrack>(
          builder: (_) => ImportTrackScreen(initialDraft: draft),
          fullscreenDialog: true,
        ),
      );

      if (importedTrack != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${importedTrack.title} imported')),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: CrabifyColors.surfaceRaised,
          title: const Text('Create playlist'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Crab night mix'),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (created != true || controller.text.trim().isEmpty || !mounted) {
      return;
    }

    await context.read<LibraryService>().createPlaylist(controller.text.trim());
  }

  String _labelForFilter(_LibraryFilter filter) {
    return switch (filter) {
      _LibraryFilter.playlists => 'Playlists',
      _LibraryFilter.liked => 'Liked Songs',
      _LibraryFilter.downloads => 'Downloads',
      _LibraryFilter.imported => 'Imported',
      _LibraryFilter.uploads => 'Uploads',
      _LibraryFilter.recent => 'Recent',
    };
  }

  _LibraryFilter _filterFromKey(String key) {
    return _LibraryFilter.values.firstWhere(
      (filter) => _keyForFilter(filter) == key,
      orElse: () => _LibraryFilter.playlists,
    );
  }

  String _keyForFilter(_LibraryFilter filter) {
    return switch (filter) {
      _LibraryFilter.playlists => 'playlists',
      _LibraryFilter.liked => 'liked',
      _LibraryFilter.downloads => 'downloads',
      _LibraryFilter.imported => 'imported',
      _LibraryFilter.uploads => 'uploads',
      _LibraryFilter.recent => 'recent',
    };
  }
}

enum _ImportMode { quick, custom }

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.count,
    required this.color,
    required this.onTap,
    this.active = false,
  });

  final String title;
  final int count;
  final Color color;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
          border:
              active ? Border.all(color: CrabifyColors.accent, width: 2) : null,
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
              '$count items',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBanner extends StatelessWidget {
  const _ActionBanner({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: CrabifyColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 14),
          FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _TrackSection extends StatelessWidget {
  const _TrackSection({
    required this.title,
    required this.tracks,
    required this.emptyTitle,
    required this.emptyMessage,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final List<MusicTrack> tracks;
  final String emptyTitle;
  final String emptyMessage;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryService>();

    return Column(
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
            if (actionLabel != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
        const SizedBox(height: 12),
        if (tracks.isEmpty)
          _EmptyCard(title: emptyTitle, message: emptyMessage)
        else
          ...tracks.map((track) {
            return TrackTile(
              track: track,
              onTap:
                  () => library.playTracks(tracks, selectedTrackId: track.id),
              trailing: IconButton(
                onPressed: () => showTrackActionsSheet(context, track: track),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            );
          }),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
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
          Text(message),
        ],
      ),
    );
  }
}
