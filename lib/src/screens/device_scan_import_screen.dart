import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../models/device_audio_candidate.dart';
import '../services/library_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/surface_card.dart';

class DeviceScanImportScreen extends StatefulWidget {
  const DeviceScanImportScreen({super.key});

  @override
  State<DeviceScanImportScreen> createState() => _DeviceScanImportScreenState();
}

class _DeviceScanImportScreenState extends State<DeviceScanImportScreen> {
  bool _loading = true;
  String? _error;
  List<DeviceAudioCandidate> _candidates = const <DeviceAudioCandidate>[];
  final Set<String> _selectedPaths = <String>{};

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: CrabifyColors.topBar,
        title: const Text('Auto detect songs'),
        actions: <Widget>[
          if (_candidates.isNotEmpty)
            IconButton(
              onPressed:
                  _selectedPaths.length == _candidates.length
                      ? _clearAll
                      : _selectAll,
              icon: Icon(
                _selectedPaths.length == _candidates.length
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (library.importOperationInProgress)
              LinearProgressIndicator(value: library.importProgressValue),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_error != null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    );
                  }
                  if (_candidates.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Crabify did not find any importable songs in device storage.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: _candidates.length,
                    itemBuilder: (context, index) {
                      final candidate = _candidates[index];
                      final alreadyImported = context
                          .read<LibraryService>()
                          .isImportedSourcePath(candidate.path);
                      final selected = _selectedPaths.contains(candidate.path);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SurfaceCard(
                          padding: EdgeInsets.zero,
                          child: CheckboxListTile(
                            value: alreadyImported ? true : selected,
                            onChanged:
                                alreadyImported
                                    ? null
                                    : (_) => _togglePath(candidate.path),
                            title: Text(candidate.title),
                            subtitle: Text(
                              [
                                candidate.artistName,
                                if ((candidate.albumTitle ?? '').isNotEmpty)
                                  candidate.albumTitle!,
                                if (candidate.durationSeconds != null)
                                  _formatDuration(candidate.durationSeconds!),
                                if (candidate.requiresConversion) 'MP4 -> MP3',
                                if (alreadyImported) 'Already imported',
                                path.basename(candidate.path),
                              ].join(' - '),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: FilledButton.icon(
                onPressed:
                    library.importOperationInProgress || _selectedPaths.isEmpty
                        ? null
                        : _importSelected,
                icon:
                    library.importOperationInProgress
                        ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.library_music_rounded),
                label: Text(
                  library.importOperationInProgress
                      ? (library.importStatusMessage ?? 'Importing...')
                      : 'Import selected songs',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadCandidates() async {
    try {
      final candidates = await context.read<LibraryService>().scanDeviceSongs();
      if (!mounted) {
        return;
      }
      setState(() {
        _candidates = candidates;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _togglePath(String pathValue) {
    setState(() {
      if (_selectedPaths.contains(pathValue)) {
        _selectedPaths.remove(pathValue);
      } else {
        _selectedPaths.add(pathValue);
      }
    });
  }

  void _selectAll() {
    final library = context.read<LibraryService>();
    setState(() {
      _selectedPaths
        ..clear()
        ..addAll(
          _candidates
              .where(
                (candidate) => !library.isImportedSourcePath(candidate.path),
              )
              .map((candidate) => candidate.path),
        );
    });
  }

  void _clearAll() {
    setState(() => _selectedPaths.clear());
  }

  Future<void> _importSelected() async {
    final selectedCandidates =
        _candidates
            .where((candidate) => _selectedPaths.contains(candidate.path))
            .toList();
    final importedCount = await context
        .read<LibraryService>()
        .importDetectedSongs(selectedCandidates);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          importedCount == 1
              ? '1 detected song imported'
              : '$importedCount detected songs imported',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }
}
