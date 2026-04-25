import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../models/import_draft.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/surface_card.dart';

class ImportTrackScreen extends StatefulWidget {
  const ImportTrackScreen({super.key, required this.initialDraft});

  final ImportDraft initialDraft;

  @override
  State<ImportTrackScreen> createState() => _ImportTrackScreenState();
}

class _ImportTrackScreenState extends State<ImportTrackScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _genreController;

  late bool _useEmbeddedArtwork;
  String? _coverImagePath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialDraft.title);
    _artistController = TextEditingController(
      text: widget.initialDraft.artistName,
    );
    _albumController = TextEditingController(
      text: widget.initialDraft.albumTitle,
    );
    _genreController = TextEditingController(text: widget.initialDraft.genre);
    _useEmbeddedArtwork = widget.initialDraft.hasEmbeddedArtwork;
    _coverImagePath = widget.initialDraft.coverImagePath;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final coverStatus =
        _coverImagePath != null
            ? path.basename(_coverImagePath!)
            : _useEmbeddedArtwork
            ? 'Embedded artwork will be used'
            : 'No cover image selected';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: CrabifyColors.topBar,
        title: const Text('Custom import'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            if (_saving && library.importProgressValue != null) ...<Widget>[
              LinearProgressIndicator(value: library.importProgressValue),
              const SizedBox(height: 16),
            ],
            SurfaceCard(
              color: CrabifyColors.surfaceRaised,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ArtworkTile(
                    seed:
                        _coverImagePath ?? widget.initialDraft.sourceAudioPath,
                    artworkPath: _coverImagePath,
                    size: 88,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          path.basename(widget.initialDraft.sourceAudioPath),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          coverStatus,
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
                            if (_coverImagePath != null || _useEmbeddedArtwork)
                              OutlinedButton.icon(
                                onPressed:
                                    _saving
                                        ? null
                                        : () {
                                          setState(() {
                                            _coverImagePath = null;
                                            _useEmbeddedArtwork = false;
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
                      'Metadata',
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _saveImport,
              icon:
                  _saving
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.library_music_rounded),
              label: Text(
                _saving
                    ? (library.importStatusMessage ?? 'Saving...')
                    : 'Save to library',
              ),
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
      _useEmbeddedArtwork = false;
    });
  }

  Future<void> _saveImport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    try {
      final updatedDraft = widget.initialDraft.copyWith(
        title: _titleController.text.trim(),
        artistName: _artistController.text.trim(),
        albumTitle: _albumController.text.trim(),
        genre: _genreController.text.trim(),
        coverImagePath: _coverImagePath,
        clearCoverImagePath: _coverImagePath == null,
        clearEmbeddedArtwork: !_useEmbeddedArtwork,
      );
      final track = await context.read<LibraryService>().saveCustomImport(
        updatedDraft,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(track);
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
