import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'screens/root_shell.dart';
import 'services/audio_player_service.dart';
import 'services/library_service.dart';
import 'services/sleep_timer_service.dart';
import 'theme/crabify_theme.dart';

class CrabifyApp extends StatefulWidget {
  const CrabifyApp({
    super.key,
    required this.libraryService,
    required this.audioPlayerService,
  });

  final LibraryService libraryService;
  final AudioPlayerService audioPlayerService;

  @override
  State<CrabifyApp> createState() => _CrabifyAppState();
}

class _CrabifyAppState extends State<CrabifyApp> {
  bool _libraryInitializationStarted = false;
  bool _backgroundBootstrapStarted = false;
  String? _fatalBootstrapError;
  late final SleepTimerService _sleepTimerService = SleepTimerService(
    audioPlayerService: widget.audioPlayerService,
    libraryService: widget.libraryService,
  );

  @override
  void initState() {
    super.initState();
    if (!_libraryInitializationStarted) {
      _libraryInitializationStarted = true;
      unawaited(_initializeLibrary(widget.libraryService));
    }
    if (!_backgroundBootstrapStarted) {
      _backgroundBootstrapStarted = true;
      unawaited(_initializeBackgroundAudio(widget.audioPlayerService));
    }
  }

  Future<void> _initializeLibrary(LibraryService libraryService) async {
    try {
      debugPrint('[Startup] Library initialization started.');
      await libraryService.initialize();
      debugPrint('[Startup] Library initialization completed.');
    } catch (error, stackTrace) {
      debugPrint('[Startup] Library initialization failed: $error');
      debugPrint('$stackTrace');
      libraryService.markInitializationFailure(
        'Crabify could not finish loading the library. Restart the app and try again.',
      );
    }
  }

  Future<void> _initializeBackgroundAudio(
    AudioPlayerService audioPlayerService,
  ) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    try {
      debugPrint(
        '[Audio] Background bootstrap started on ${Platform.operatingSystem}.',
      );
      if (Platform.isAndroid) {
        await _ensureAndroidNotificationPermission();
      }
      final audioSession = await AudioSession.instance;
      await audioSession.configure(AudioSessionConfiguration.music());
      debugPrint(
        '[Audio] Background audio session ready on ${Platform.operatingSystem}.',
      );
    } catch (error, stackTrace) {
      debugPrint('[Audio] Background bootstrap failed: $error');
      debugPrint('$stackTrace');
      audioPlayerService.reportError(
        'Crabify background playback controls are unavailable right now.',
      );
    }
  }

  Future<void> _ensureAndroidNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) {
      debugPrint('[Audio] Notification permission already granted: $status');
      return;
    }

    final result = await Permission.notification.request();
    debugPrint('[Audio] Notification permission status: $result');
    if (!result.isGranted && !result.isLimited) {
      widget.audioPlayerService.reportError(
        'Enable Android notifications for Crabify to use media controls on the lock screen and in the notification tray.',
      );
    }
  }

  @override
  void dispose() {
    _sleepTimerService.dispose();
    widget.audioPlayerService.dispose();
    widget.libraryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fatalBootstrapError != null) {
      return MaterialApp(
        title: 'Crabify',
        debugShowCheckedModeBanner: false,
        theme: CrabifyTheme.dark(),
        home: CrabifyStartupErrorView(message: _fatalBootstrapError!),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryService>.value(value: widget.libraryService),
        ChangeNotifierProvider<AudioPlayerService>.value(
          value: widget.audioPlayerService,
        ),
        ChangeNotifierProvider<SleepTimerService>.value(
          value: _sleepTimerService,
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

class CrabifyStartupErrorApp extends StatelessWidget {
  const CrabifyStartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crabify',
      debugShowCheckedModeBanner: false,
      theme: CrabifyTheme.dark(),
      home: CrabifyStartupErrorView(message: message),
    );
  }
}

class CrabifyStartupErrorView extends StatelessWidget {
  const CrabifyStartupErrorView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: CrabifyColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: CrabifyColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline_rounded,
                    color: CrabifyColors.accent,
                    size: 42,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Crabify could not start',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
