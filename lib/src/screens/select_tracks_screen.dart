import 'package:flutter/material.dart';

import '../models/music_track.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';

class SelectTracksScreen extends StatefulWidget {
  const SelectTracksScreen({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.tracks,
    this.emptyMessage = 'No songs available here yet.',
    this.initiallySelectedTrackIds = const <String>{},
    this.allowEmptySelection = false,
  });

  final String title;
  final String actionLabel;
  final List<MusicTrack> tracks;
  final String emptyMessage;
  final Set<String> initiallySelectedTrackIds;
  final bool allowEmptySelection;

  @override
  State<SelectTracksScreen> createState() => _SelectTracksScreenState();
}

class _SelectTracksScreenState extends State<SelectTracksScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final Set<String> _selectedTrackIds;

  @override
  void initState() {
    super.initState();
    _selectedTrackIds = <String>{...widget.initiallySelectedTrackIds};
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MusicTrack> get _visibleTracks {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.tracks;
    }
    return widget.tracks.where((track) {
      final haystack =
          <String>[
            track.title,
            track.artistName,
            track.albumTitle,
            track.genre ?? '',
          ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleTracks = _visibleTracks;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: CrabifyColors.topBar,
        title: Text(widget.title),
        actions: <Widget>[
          TextButton(
            onPressed:
                !widget.allowEmptySelection && _selectedTrackIds.isEmpty
                    ? null
                    : _submitSelection,
            child: Text(widget.actionLabel),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search songs',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 16),
            if (visibleTracks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.emptyMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CrabifyColors.textSecondary,
                  ),
                ),
              )
            else
              ...visibleTracks.map((track) {
                final selected = _selectedTrackIds.contains(track.cacheKey);
                return CheckboxListTile(
                  value: selected,
                  onChanged: (_) => _toggleTrack(track),
                  controlAffinity: ListTileControlAffinity.leading,
                  secondary: ArtworkTile(
                    seed: track.cacheKey,
                    artworkPath: track.artworkPath,
                    artworkUrl: track.artworkUrl,
                    size: 52,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: Text(track.title),
                  subtitle: Text(track.subtitle),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _toggleTrack(MusicTrack track) {
    setState(() {
      if (_selectedTrackIds.contains(track.cacheKey)) {
        _selectedTrackIds.remove(track.cacheKey);
      } else {
        _selectedTrackIds.add(track.cacheKey);
      }
    });
  }

  void _submitSelection() {
    final selectedTracks =
        widget.tracks
            .where((track) => _selectedTrackIds.contains(track.cacheKey))
            .toList();
    Navigator.of(context).pop(selectedTracks);
  }
}
