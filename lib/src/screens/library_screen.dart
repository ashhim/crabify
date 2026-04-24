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

enum _LibraryFilter { playlists, downloads, imported, recent }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onOpenUpload});

  final VoidCallback onOpenUpload;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _LibraryFilter _filter = _LibraryFilter.playlists;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();

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
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Downloads',
                  count: library.downloadedTracks.length,
                  color: const Color(0xFF14532D),
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
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Uploads',
                  count: library.uploadedTracks.length,
                  color: const Color(0xFF0F766E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            children:
                _LibraryFilter.values.map((filter) {
                  return ChoiceChip(
                    selected: _filter == filter,
                    label: Text(_labelForFilter(filter)),
                    onSelected: (_) => setState(() => _filter = filter),
                  );
                }).toList(),
          ),
          const SizedBox(height: 20),
          if (_filter == _LibraryFilter.playlists) ...<Widget>[
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
            else
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
                  subtitle: Text(
                    '${playlist.subtitle} • ${playlist.trackIds.length} tracks',
                  ),
                );
              }),
          ] else ...<Widget>[
            if (_filter == _LibraryFilter.downloads)
              _TrackSection(
                title: 'Downloaded songs',
                tracks: library.downloadedTracks,
                emptyTitle: 'No downloads yet',
                emptyMessage:
                    'Save tracks from the online catalog and they will appear here for offline playback.',
              ),
            if (_filter == _LibraryFilter.imported)
              _TrackSection(
                title: 'Imported audio',
                tracks: library.importedTracks,
                emptyTitle: 'No imported tracks yet',
                emptyMessage:
                    'Use the import button to scan chosen files from your device and bring them into Crabify.',
                actionLabel: 'Import',
                onAction: _importFiles,
              ),
            if (_filter == _LibraryFilter.recent)
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
    try {
      await context.read<LibraryService>().importLocalTracks();
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
      _LibraryFilter.downloads => 'Downloads',
      _LibraryFilter.imported => 'Imported',
      _LibraryFilter.recent => 'Recent',
    };
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
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
