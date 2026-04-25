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
  downloads,
  imported,
  uploads,
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
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _SummaryCard(
                  title: 'Artists',
                  count: library.localArtists.length,
                  color: const Color(0xFF1D4ED8),
                  active: filter == _LibraryFilter.artists,
                  onTap:
                      () => library.setSelectedLibraryFilter(
                        _keyForFilter(_LibraryFilter.artists),
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  title: 'Recent',
                  count: library.recentTracks.length,
                  color: const Color(0xFF5B21B6),
                  active: filter == _LibraryFilter.recent,
                  onTap:
                      () => library.setSelectedLibraryFilter(
                        _keyForFilter(_LibraryFilter.recent),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
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
                  '', //Create playlists, import audio files from your device, and keep offline tracks close
              actionLabel: 'Import files',
              onAction: _importFiles,
            ),
            const SizedBox(height: 18),
            if (library.playlists.isEmpty)
              const _EmptyCard(
                title: 'No playlists yet',
                message:
                    '', //Create your first playlist, then add online or offline tracks to it from any track menu.
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
            if (filter == _LibraryFilter.downloads)
              _TrackSection(
                title: 'Downloaded songs',
                tracks: library.downloadedTracks,
                emptyTitle: 'No downloads yet',
                emptyMessage:
                    '', //Save tracks from the online catalog and they will appear here for offline playback.
              ),
            if (filter == _LibraryFilter.imported)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Imported audio',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton(
                        onPressed: _importFiles,
                        child: const Text('Choose files'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (library.importedTracks.isEmpty)
                    const _EmptyCard(
                      title: 'No imported tracks yet',
                      message:
                          '', //Scan device songs or choose files from your device to bring them into Crabify.
                    )
                  else
                    ...library.importedTracks.map((track) {
                      return TrackTile(
                        track: track,
                        onTap:
                            () => library.playTracks(
                              library.importedTracks,
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
            if (filter == _LibraryFilter.uploads)
              _TrackSection(
                title: 'Uploaded tracks',
                tracks: library.uploadedTracks,
                emptyTitle: 'No uploads yet',
                emptyMessage:
                    '', //Save a track locally from the upload screen, then publish it through your secure backend when one is configured.
              ),
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
        _ActionBanner(
          title: 'Artist',
          message:
              '', //Crabify groups your imported, downloaded, and uploaded tracks into artist pages. Removing an artist here hides the artist card without touching any songs.
          actionLabel: 'Import files',
          onAction: _importFiles,
        ),
        const SizedBox(height: 18),
        Text(
          'Saved artists',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: _showCreateArtistDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add artist'),
            ),
          ],
        ),
        const SizedBox(height: 12),
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

  String _labelForFilter(_LibraryFilter filter) {
    return switch (filter) {
      _LibraryFilter.playlists => 'Playlists',
      _LibraryFilter.artists => 'Artists',
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
      _LibraryFilter.artists => 'artists',
      _LibraryFilter.liked => 'liked',
      _LibraryFilter.downloads => 'downloads',
      _LibraryFilter.imported => 'imported',
      _LibraryFilter.uploads => 'uploads',
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
                  () => library.playTracks(tracks, selectedTrackId: track.id),
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
