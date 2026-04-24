import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_track.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';

Future<void> showTrackActionsSheet(
  BuildContext context, {
  required MusicTrack track,
}) {
  final library = context.read<LibraryService>();

  return showModalBottomSheet<void>(
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
                track.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                track.artistName,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: CrabifyColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              _ActionTile(
                icon:
                    library.isLiked(track.id)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                title:
                    library.isLiked(track.id)
                        ? 'Remove from liked songs'
                        : 'Add to liked songs',
                onTap: () async {
                  Navigator.of(context).pop();
                  await library.toggleLike(track.id);
                },
              ),
              _ActionTile(
                icon: Icons.queue_music_rounded,
                title: 'Add to queue',
                onTap: () async {
                  Navigator.of(context).pop();
                  await library.addToQueue(track);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Added to queue')),
                    );
                  }
                },
              ),
              _ActionTile(
                icon: Icons.download_rounded,
                title:
                    track.downloadable
                        ? library.isDownloaded(track.id)
                            ? 'Downloaded'
                            : 'Download for offline'
                        : 'Download unavailable',
                enabled: track.downloadable && !library.isDownloaded(track.id),
                onTap: () async {
                  Navigator.of(context).pop();
                  try {
                    await library.downloadTrack(track);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Saved to offline downloads'),
                        ),
                      );
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  }
                },
              ),
              _ActionTile(
                icon: Icons.playlist_add_rounded,
                title: 'Add to playlist',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showPlaylistPicker(context, trackId: track.id);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _showPlaylistPicker(
  BuildContext context, {
  required String trackId,
}) async {
  final library = context.read<LibraryService>();

  if (library.playlists.isEmpty) {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: CrabifyColors.surfaceRaised,
          title: const Text('Create playlist'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Late tide mix'),
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

    if (created == true && controller.text.trim().isNotEmpty) {
      await library.createPlaylist(controller.text.trim());
    }
  }

  if (!context.mounted) {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: CrabifyColors.surfaceRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          children:
              library.playlists.map((playlist) {
                return ListTile(
                  onTap: () async {
                    Navigator.of(context).pop();
                    await library.addTrackToPlaylist(
                      playlistId: playlist.id,
                      trackId: trackId,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added to ${playlist.title}')),
                      );
                    }
                  },
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(playlist.title),
                  subtitle: Text(playlist.subtitle),
                );
              }).toList(),
        ),
      );
    },
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: enabled ? onTap : null,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        color: enabled ? CrabifyColors.textPrimary : CrabifyColors.textMuted,
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: enabled ? CrabifyColors.textPrimary : CrabifyColors.textMuted,
        ),
      ),
    );
  }
}
