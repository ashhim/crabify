import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

import '../models/upload_draft.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/artwork_tile.dart';
import '../widgets/surface_card.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _genreController = TextEditingController(text: 'Electronic');
  final _descriptionController = TextEditingController();

  String? _audioFilePath;
  String? _coverImagePath;
  bool _allowDownload = false;
  bool _rightsConfirmed = false;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _genreController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: CrabifyColors.topBar,
        title: const Text('Upload to Crabify'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            if (library.uploadUsesStub)
              const SurfaceCard(
                color: CrabifyColors.surfaceRaised,
                child: Text(
                  'This demo uses a secure local stub for uploads. Plug a backend into `CRABIFY_UPLOAD_PROXY` when you are ready to send tracks to Audius for real.',
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
                      'Track details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _titleController,
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
                      decoration: const InputDecoration(labelText: 'Artist'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter an artist name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _genreController,
                      decoration: const InputDecoration(labelText: 'Genre'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Add a genre';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Files',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ArtworkTile(
                        seed: _coverImagePath ?? _titleController.text,
                        artworkPath: _coverImagePath,
                        size: 96,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            FilledButton.tonalIcon(
                              onPressed: _pickAudio,
                              icon: const Icon(Icons.audio_file_rounded),
                              label: Text(
                                _audioFilePath == null
                                    ? 'Choose audio file'
                                    : path.basename(_audioFilePath!),
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _pickCover,
                              icon: const Icon(Icons.image_rounded),
                              label: Text(
                                _coverImagePath == null
                                    ? 'Choose cover image'
                                    : path.basename(_coverImagePath!),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Only upload tracks you created yourself or have clear rights to distribute.',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color: CrabifyColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _allowDownload,
                    onChanged:
                        (value) => setState(() => _allowDownload = value),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow offline download'),
                    subtitle: const Text(
                      'Enable this only if your rights allow listeners to save the file locally.',
                    ),
                  ),
                  CheckboxListTile(
                    value: _rightsConfirmed,
                    onChanged: (value) {
                      setState(() => _rightsConfirmed = value ?? false);
                    },
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'I own this track or I am licensed to upload it',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon:
                  _submitting
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.cloud_upload_rounded),
              label: Text(_submitting ? 'Uploading...' : 'Publish track'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>[
        'mp3',
        'm4a',
        'wav',
        'flac',
        'ogg',
        'opus',
      ],
    );

    if (result == null || result.files.single.path == null) {
      return;
    }

    setState(() {
      _audioFilePath = result.files.single.path;
      if (_titleController.text.trim().isEmpty) {
        _titleController.text = path.basenameWithoutExtension(_audioFilePath!);
      }
    });
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) {
      return;
    }

    setState(() => _coverImagePath = result.files.single.path);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_audioFilePath == null || _audioFilePath!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an audio file first')),
      );
      return;
    }
    if (!_rightsConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirm your rights before uploading this track'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final draft = UploadDraft(
        title: _titleController.text.trim(),
        artistName: _artistController.text.trim(),
        genre: _genreController.text.trim(),
        description: _descriptionController.text.trim(),
        audioFilePath: _audioFilePath!,
        coverImagePath: _coverImagePath,
        allowDownload: _allowDownload,
        rightsConfirmed: _rightsConfirmed,
      );
      final submittedRemotely = await context
          .read<LibraryService>()
          .submitUpload(draft);
      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(submittedRemotely);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
