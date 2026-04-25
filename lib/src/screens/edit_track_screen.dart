import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../models/music_track.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/surface_card.dart';

class EditTrackScreen extends StatefulWidget {
  const EditTrackScreen({super.key, required this.track});

  final MusicTrack track;

  @override
  State<EditTrackScreen> createState() => _EditTrackScreenState();
}

class _EditTrackScreenState extends State<EditTrackScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _genreController;
  late final TextEditingController _descriptionController;

  String? _coverImagePath;
  bool _clearCover = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.track.title);
    _artistController = TextEditingController(text: widget.track.artistName);
    _albumController = TextEditingController(text: widget.track.albumTitle);
    _genreController = TextEditingController(text: widget.track.genre);
    _descriptionController = TextEditingController(
      text: widget.track.description,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coverLabel =
        _clearCover
            ? 'Cover removed locally'
            : _coverImagePath != null
            ? path.basename(_coverImagePath!)
            : (widget.track.artworkPath ?? widget.track.artworkUrl) != null
            ? 'Using current cover'
            : 'No cover image selected';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: CrabifyColors.topBar,
        title: const Text('Edit song'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            SurfaceCard(
              color: CrabifyColors.surfaceRaised,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ArtworkTile(
                    seed: _coverImagePath ?? widget.track.cacheKey,
                    artworkPath:
                        _clearCover
                            ? null
                            : _coverImagePath ?? widget.track.artworkPath,
                    artworkUrl:
                        _clearCover
                            ? null
                            : (_coverImagePath == null
                                ? widget.track.artworkUrl
                                : null),
                    size: 88,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.track.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          coverLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: CrabifyColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _pickCover,
                              icon: const Icon(Icons.image_rounded),
                              label: const Text('Choose cover'),
                            ),
                            if (!_clearCover &&
                                (_coverImagePath != null ||
                                    widget.track.artworkPath != null ||
                                    widget.track.artworkUrl != null))
                              OutlinedButton.icon(
                                onPressed:
                                    _saving
                                        ? null
                                        : () {
                                          setState(() {
                                            _clearCover = true;
                                            _coverImagePath = null;
                                          });
                                        },
                                icon: const Icon(Icons.hide_image_rounded),
                                label: const Text('No cover'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SurfaceCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Local metadata override',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _titleController,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Title'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter a title';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _artistController,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Artist'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter an artist';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _albumController,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Album (optional)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _genreController,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Genre (optional)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _descriptionController,
                      enabled: !_saving,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon:
                  _saving
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Saving...' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final selectedPath = result?.files.single.path;
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return;
    }

    setState(() {
      _coverImagePath = selectedPath;
      _clearCover = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    try {
      final updatedTrack = await context.read<LibraryService>().saveTrackEdits(
        track: widget.track,
        title: _titleController.text,
        artistName: _artistController.text,
        albumTitle: _albumController.text,
        genre: _genreController.text,
        description: _descriptionController.text,
        coverImagePath: _coverImagePath,
        clearCover: _clearCover,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(updatedTrack);
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
