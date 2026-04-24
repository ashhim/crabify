import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/root_shell.dart';
import 'services/audio_player_service.dart';
import 'services/library_service.dart';
import 'theme/crabify_theme.dart';

class CrabifyApp extends StatelessWidget {
  const CrabifyApp({
    super.key,
    required this.libraryService,
    required this.audioPlayerService,
  });

  final LibraryService libraryService;
  final AudioPlayerService audioPlayerService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryService>.value(value: libraryService),
        ChangeNotifierProvider<AudioPlayerService>.value(
          value: audioPlayerService,
        ),
      ],
      child: MaterialApp(
        title: 'Crabify',
        debugShowCheckedModeBanner: false,
        theme: CrabifyTheme.dark(),
        home: const RootShell(),
      ),
    );
  }
}
