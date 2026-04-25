import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music_track.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../screens/edit_track_screen.dart';

Future<void> showTrackActionsSheet(
  BuildContext context, {
  required MusicTrack track,
}) {
  final parentContext = context;
  final library = context.read<LibraryService>();
  final downloadInProgress = library.progressFor(track.id) != null;
  final downloadDisabledReason = library.downloadDisabledReason(track);
  final deleteLabel = switch (track.origin) {
    TrackOrigin.downloaded => 'Delete downloaded file',
    TrackOrigin.local => 'Delete imported file',
    TrackOrigin.uploaded => 'Delete local upload',
    TrackOrigin.online => null,
  };

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: CrabifyColors.surfaceRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
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
                icon: Icons.edit_rounded,
                title: 'Edit local metadata',
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await Navigator.of(parentContext).push<MusicTrack>(
                    MaterialPageRoute<MusicTrack>(
                      builder: (_) => EditTrackScreen(track: track),
                      fullscreenDialog: true,
                    ),
                  );
                },
              ),
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
                  Navigator.of(sheetContext).pop();
                  await library.toggleLike(track.id, trackSnapshot: track);
                },
              ),
              _ActionTile(
                icon: Icons.queue_music_rounded,
                title: 'Add to queue',
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await library.addToQueue(track);
                  if (parentContext.mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(content: Text('Added to queue')),
                    );
                  }
                },
              ),
              _ActionTile(
                icon: Icons.download_rounded,
                title:
                    downloadDisabledReason == null
                        ? 'Download for offline'
                        : downloadInProgress
                        ? 'Downloading...'
                        : downloadDisabledReason,
                enabled: downloadDisabledReason == null,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await library.downloadTrack(track);
                    if (parentContext.mounted) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        const SnackBar(
                          content: Text('Saved to offline downloads'),
                        ),
                      );
                    }
                  } catch (error) {
                    if (parentContext.mounted) {
                      ScaffoldMessenger.of(
                        parentContext,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  }
                },
              ),
              _ActionTile(
                icon: Icons.playlist_add_rounded,
                title: 'Add to playlist',
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _showPlaylistPicker(
                    parentContext,
                    track: track,
                    trackId: track.id,
                  );
                },
              ),
              if (deleteLabel != null)
                _ActionTile(
                  icon: Icons.delete_outline_rounded,
                  title: deleteLabel,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final confirmed = await _confirmDeleteLocalTrack(
                      parentContext,
                      track: track,
                    );
                    if (confirmed != true || !parentContext.mounted) {
                      return;
                    }
                    try {
                      await library.deleteLocalTrack(track);
                      if (parentContext.mounted) {
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${track.title} was removed from this device',
                            ),
                          ),
                        );
                      }
                    } catch (error) {
                      if (parentContext.mounted) {
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    }
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
  required MusicTrack track,
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
                      trackSnapshot: track,
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

Future<bool?> _confirmDeleteLocalTrack(
  BuildContext context, {
  required MusicTrack track,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: CrabifyColors.surfaceRaised,
        title: const Text('Delete local file?'),
        content: Text(
          'This removes ${track.title} from Crabify storage on this device. Online copies are not affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
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
