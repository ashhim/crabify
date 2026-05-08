import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../models/artist_profile.dart';
import '../models/music_collection.dart';
import '../models/music_track.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/surface_card.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';
import 'detail_screen.dart';
import 'device_scan_import_screen.dart';
import 'import_track_screen.dart';
import 'playlist_artist_picker_screen.dart';

enum _LibraryFilter {
  playlists,
  artists,
  liked,
  offline,
  recent,
}

enum _ImportFlowAction { quick, custom, autoDetect }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onOpenUpload});

  final VoidCallback onOpenUpload;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _artistSearchController = TextEditingController();
  List<ArtistProfile> _artistSearchResults = const <ArtistProfile>[];
  bool _artistSearchInFlight = false;
  String? _artistSearchError;
  Timer? _artistSearchDebounce;
  int _artistSearchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _artistSearchController.addListener(_handleArtistSearchChanged);
  }

  @override
  void dispose() {
    _artistSearchDebounce?.cancel();
    _artistSearchController.dispose();
    super.dispose();
  }

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
          if (library.importOperationInProgress) ...<Widget>[
            _ImportStatusCard(
              message: library.importStatusMessage ?? 'Working on import...',
              progress: library.importProgressValue,
            ),
            const SizedBox(height: 18),
          ],
          _SummaryCard(
            title: 'Playlist',
            count: library.playlists.length,
            color: CrabifyColors.summaryUploads,
            active: filter == _LibraryFilter.playlists,
            onTap:
                () => library.setSelectedLibraryFilter(
                  _keyForFilter(_LibraryFilter.playlists),
                ),
          ),
          const SizedBox(height: 10),
          _SummaryCard(
            title: 'Artists',
            count: library.localArtists.length,
            color: CrabifyColors.summaryArtists,
            active: filter == _LibraryFilter.artists,
            onTap:
                () => library.setSelectedLibraryFilter(
                  _keyForFilter(_LibraryFilter.artists),
                ),
          ),
          const SizedBox(height: 10),
          _SummaryCard(
            title: 'Liked',
            count: library.likedTracks.length,
            color: CrabifyColors.summaryLiked,
            active: filter == _LibraryFilter.liked,
            onTap:
                () => library.setSelectedLibraryFilter(
                  _keyForFilter(_LibraryFilter.liked),
                ),
          ),
          const SizedBox(height: 10),
          _SummaryCard(
            title: 'Offline',
            count: library.localTracks.length,
            color: CrabifyColors.summaryImported,
            active: filter == _LibraryFilter.offline,
            onTap:
                () => library.setSelectedLibraryFilter(
                  _keyForFilter(_LibraryFilter.offline),
                ),
          ),
          const SizedBox(height: 10),
          _SummaryCard(
            title: 'Recent',
            count: library.recentTracks.length,
            color: CrabifyColors.summaryRecent,
            active: filter == _LibraryFilter.recent,
            onTap:
                () => library.setSelectedLibraryFilter(
                  _keyForFilter(_LibraryFilter.recent),
                ),
          ),
          const SizedBox(height: 22),
          if (filter == _LibraryFilter.playlists) ...<Widget>[
            _SectionToolbar(
              title: 'Make this library yours',
              actions: <Widget>[
                IconButton.filledTonal(
                  tooltip: 'Import files',
                  onPressed: _importFiles,
                  icon: const Icon(Icons.file_upload_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: 'Shuffle all playlists',
                  onPressed:
                      library.playlists.isEmpty ? null : library.shuffleAllPlaylists,
                  icon: const Icon(Icons.shuffle_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (library.playlists.isEmpty)
              const _EmptyCard(
                title: 'No playlists yet',
                message:
                    '', //Create your first playlist, then add online or offline tracks to it from any track menu.
              )
            else ...<Widget>[
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
          ] else if (filter == _LibraryFilter.artists) ...<Widget>[
            _buildArtistSection(context, library),
          ] else ...<Widget>[
            if (filter == _LibraryFilter.liked)
              _TrackSection(
                title: 'Liked songs',
                tracks: library.likedTracks,
                emptyTitle: 'No liked songs yet',
                emptyMessage:
                    '', //Heart tracks from Home, Search, playlists, or the player and they will stay here.
              ),
            if (filter == _LibraryFilter.offline)
              _OfflineSection(onImport: _importFiles),
            if (filter == _LibraryFilter.recent) _RecentSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildArtistSection(BuildContext context, LibraryService library) {
    final artists = library.localArtists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionToolbar(
          title: 'Artists',
          actions: <Widget>[
            IconButton.filledTonal(
              tooltip: 'Import files',
              onPressed: _importFiles,
              icon: const Icon(Icons.file_upload_rounded),
            ),
            IconButton.filledTonal(
              tooltip: 'Add artist',
              onPressed: _showCreateArtistDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (artists.isEmpty)
          const _EmptyCard(
            title: 'No artists yet',
            message:
                '', //Import or download local tracks and Crabify will build artist pages from their metadata.
          )
        else
          ...artists.map((artist) {
            final trackCount = library.tracksForArtist(artist).length;
            final isSaved = library.savedArtistById(artist.id)?.pinned ?? false;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => _openArtistDetails(artist),
              leading: ArtworkTile(
                seed: artist.id,
                artworkPath: artist.artworkPath,
                artworkUrl: artist.artworkUrl,
                size: 58,
                borderRadius: BorderRadius.circular(16),
                icon: Icons.person_rounded,
              ),
              title: Text(artist.name),
              subtitle: Text(
                trackCount == 1
                    ? '1 song${isSaved ? ' • saved' : ''}'
                    : '$trackCount songs${isSaved ? ' • saved' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            );
          }),
        const SizedBox(height: 24),
        SurfaceCard(
          color: CrabifyColors.surfaceRaised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Search Crabify artists',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '', //Search Audius-backed artist matches and pin them into this artist shelf.
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: CrabifyColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _artistSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search artists',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon:
                            _artistSearchController.text.trim().isEmpty
                                ? null
                                : IconButton(
                                  onPressed: _artistSearchController.clear,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_artistSearchInFlight) ...<Widget>[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_artistSearchError != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _artistSearchError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CrabifyColors.textSecondary,
                  ),
                ),
              ],
              if (_artistSearchResults.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                ..._artistSearchResults.map((artist) {
                  final isSaved =
                      library.savedArtistById(artist.id)?.pinned ?? false;
                  final trackCount = library.tracksForArtist(artist).length;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () async {
                      if (!isSaved) {
                        await library.saveArtist(artist);
                      }
                      if (!mounted) {
                        return;
                      }
                      _openArtistDetails(artist);
                    },
                    leading: ArtworkTile(
                      seed: artist.id,
                      artworkPath: artist.artworkPath,
                      artworkUrl: artist.artworkUrl,
                      size: 54,
                      borderRadius: BorderRadius.circular(16),
                      icon: Icons.person_rounded,
                    ),
                    title: Text(artist.name),
                    subtitle: Text(
                      trackCount == 0
                          ? 'Artist match from Crabify'
                          : '$trackCount related tracks',
                    ),
                    trailing:
                        isSaved
                            ? const Icon(Icons.check_circle_rounded)
                            : const Icon(Icons.chevron_right_rounded),
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _handleArtistSearchChanged() {
    _artistSearchDebounce?.cancel();
    _artistSearchDebounce = Timer(
      const Duration(milliseconds: 260),
      _runArtistSearch,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _runArtistSearch() async {
    final query = _artistSearchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _artistSearchResults = const <ArtistProfile>[];
        _artistSearchError = null;
      });
      return;
    }

    setState(() {
      _artistSearchInFlight = true;
      _artistSearchError = null;
    });
    final requestId = ++_artistSearchRequestId;

    try {
      final results = await context.read<LibraryService>().searchRemoteArtists(
        query,
      );
      if (!mounted || requestId != _artistSearchRequestId) {
        return;
      }
      setState(() {
        _artistSearchResults = results;
      });
    } catch (error) {
      if (!mounted || requestId != _artistSearchRequestId) {
        return;
      }
      setState(() {
        _artistSearchError = error.toString();
        _artistSearchResults = const <ArtistProfile>[];
      });
    } finally {
      if (mounted && requestId == _artistSearchRequestId) {
        setState(() {
          _artistSearchInFlight = false;
        });
      }
    }
  }

  void _openArtistDetails(ArtistProfile artist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistDetailScreen(artist: artist),
      ),
    );
  }

  Future<void> _openScanDeviceSongs() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const DeviceScanImportScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _importFiles() async {
    final library = context.read<LibraryService>();
    final supportsAutoDetect =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    final importAction = await showModalBottomSheet<_ImportFlowAction>(
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
                const SizedBox(height: 12),
                if (supportsAutoDetect)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.radar_rounded),
                    title: const Text('Scan device songs'),
                    subtitle: const Text(
                      'List supported audio files from Android storage.',
                    ),
                    onTap:
                        () => Navigator.of(
                          sheetContext,
                        ).pop(_ImportFlowAction.autoDetect),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flash_on_rounded),
                  title: const Text('Quick import'),
                  subtitle: const Text(
                    'Auto-copy the song, metadata, and embedded artwork now.',
                  ),
                  onTap:
                      () => Navigator.of(
                        sheetContext,
                      ).pop(_ImportFlowAction.quick),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('Custom import'),
                  subtitle: const Text(
                    'Choose one file, edit metadata, then save it to the library.',
                  ),
                  onTap:
                      () => Navigator.of(
                        sheetContext,
                      ).pop(_ImportFlowAction.custom),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (importAction == null || !mounted) {
      return;
    }

    try {
      if (importAction == _ImportFlowAction.autoDetect) {
        await _openScanDeviceSongs();
        return;
      }

      if (importAction == _ImportFlowAction.quick) {
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

      final draft = await library.createCustomImportDraft();
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
    final action = await showModalBottomSheet<String>(
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
                  'Create playlist',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.queue_music_rounded),
                  title: const Text('Blank playlist'),
                  subtitle: const Text('Start empty and add tracks manually.'),
                  onTap: () => Navigator.of(sheetContext).pop('blank'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_search_rounded),
                  title: const Text('Playlist from artists'),
                  subtitle: const Text(
                    'Search artists, select them, and populate the playlist automatically.',
                  ),
                  onTap: () => Navigator.of(sheetContext).pop('artists'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == 'artists') {
      final playlist = await Navigator.of(context).push<MusicCollection>(
        MaterialPageRoute<MusicCollection>(
          builder: (_) => const PlaylistArtistPickerScreen(),
          fullscreenDialog: true,
        ),
      );
      if (playlist != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${playlist.title} created')));
      }
      return;
    }

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

  Future<void> _showCreateArtistDialog() async {
    await _showArtistEditor();
  }

  Future<void> _showArtistEditor({ArtistProfile? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CrabifyColors.surfaceRaised,
          title: Text(existing == null ? 'Add artist' : 'Edit artist'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Artist name'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final library = context.read<LibraryService>();
      if (existing == null) {
        await library.createManualArtist(
          name: nameController.text,
          description: descriptionController.text,
        );
      } else {
        await library.updateArtistDetails(
          artist: existing,
          name: nameController.text,
          description: descriptionController.text,
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

  _LibraryFilter _filterFromKey(String key) {
    return switch (key) {
      'playlists' => _LibraryFilter.playlists,
      'artists' => _LibraryFilter.artists,
      'liked' => _LibraryFilter.liked,
      'offline' || 'downloads' || 'imported' || 'uploads' =>
        _LibraryFilter.offline,
      'recent' => _LibraryFilter.recent,
      _ => _LibraryFilter.playlists,
    };
  }

  String _keyForFilter(_LibraryFilter filter) {
    return switch (filter) {
      _LibraryFilter.playlists => 'playlists',
      _LibraryFilter.artists => 'artists',
      _LibraryFilter.liked => 'liked',
      _LibraryFilter.offline => 'offline',
      _LibraryFilter.recent => 'recent',
    };
  }
}

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
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color:
              active
                  ? Color.alphaBlend(
                    CrabifyColors.accent.withValues(alpha: 0.08),
                    CrabifyColors.surfaceRaised,
                  )
                  : CrabifyColors.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? CrabifyColors.accent : CrabifyColors.border,
            width: active ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? CrabifyColors.accent : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$count items',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: CrabifyColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.chevron_right_rounded,
              color:
                  active
                      ? CrabifyColors.accent
                      : Colors.white.withValues(alpha: 0.78),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineSection extends StatelessWidget {
  const _OfflineSection({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final tracks = library.localTracks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionToolbar(
          title: 'Offline songs',
          actions: <Widget>[
            IconButton.filledTonal(
              tooltip: 'Import files',
              onPressed: onImport,
              icon: const Icon(Icons.file_upload_rounded),
            ),
            IconButton.filledTonal(
              tooltip: 'Shuffle offline songs',
              onPressed:
                  tracks.isEmpty ? null : () => library.playTracksShuffled(tracks),
              icon: const Icon(Icons.shuffle_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (tracks.isEmpty)
          const _EmptyCard(
            title: 'No offline songs yet',
            message:
                'Import local files, download tracks, or save uploads and they will appear here.',
          )
        else
          ...tracks.map((track) {
            return TrackTile(
              track: track,
              onTap:
                  () => library.playTracks(
                    tracks,
                    selectedTrackId: track.id,
                    selectedTrackCacheKey: track.cacheKey,
                  ),
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

class _ImportStatusCard extends StatelessWidget {
  const _ImportStatusCard({required this.message, this.progress});

  final String message;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: CrabifyColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (progress != null) ...<Widget>[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
          ],
        ],
      ),
    );
  }
}

class _SectionToolbar extends StatelessWidget {
  const _SectionToolbar({required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Wrap(spacing: 8, children: actions),
      ],
    );
  }
}

class _TrackSection extends StatelessWidget {
  const _TrackSection({
    required this.title,
    required this.tracks,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final String title;
  final List<MusicTrack> tracks;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (tracks.isEmpty)
          _EmptyCard(title: emptyTitle, message: emptyMessage)
        else
          ...tracks.map((track) {
            return TrackTile(
              track: track,
              onTap:
                  () => library.playTracks(
                    tracks,
                    selectedTrackId: track.id,
                    selectedTrackCacheKey: track.cacheKey,
                  ),
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

class _RecentSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final tracks = library.recentTracks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Recent plays',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (tracks.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) {
                      return AlertDialog(
                        backgroundColor: CrabifyColors.surfaceRaised,
                        title: const Text('Clear recent history?'),
                        content: const Text(
                          'This removes every recent song from the list on this device.',
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed:
                                () => Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed:
                                () => Navigator.of(dialogContext).pop(true),
                            child: const Text('Clear all'),
                          ),
                        ],
                      );
                    },
                  );
                  if (confirmed == true) {
                    await library.clearRecentTracks();
                  }
                },
                icon: const Icon(Icons.delete_sweep_rounded),
                label: const Text('Clear all'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (tracks.isEmpty)
          const _EmptyCard(
            title: 'Nothing played yet',
            message:
                'Start a queue from Home or Search and Crabify will build your recent shelf automatically.',
          )
        else
          ...tracks.map((track) {
            return TrackTile(
              track: track,
              onTap:
                  () => library.playTracks(
                    tracks,
                    selectedTrackId: track.id,
                    selectedTrackCacheKey: track.cacheKey,
                  ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    onPressed: () => library.removeRecentTrack(track.id),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  IconButton(
                    onPressed:
                        () => showTrackActionsSheet(context, track: track),
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
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
