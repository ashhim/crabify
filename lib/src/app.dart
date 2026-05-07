import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'screens/root_shell.dart';
import 'services/audio_player_service.dart';
import 'services/audius_api_service.dart';
import 'services/device_media_scanner_service.dart';
import 'services/download_service.dart';
import 'services/library_service.dart';
import 'services/local_storage_service.dart';
import 'theme/crabify_theme.dart';

class CrabifyApp extends StatefulWidget {
  const CrabifyApp({super.key});

  @override
  State<CrabifyApp> createState() => _CrabifyAppState();
}

class _CrabifyAppState extends State<CrabifyApp> {
  bool _bootstrapStarted = false;
  bool _backgroundBootstrapComplete = !(Platform.isAndroid || Platform.isIOS);
  LibraryService? _libraryService;
  AudioPlayerService? _audioPlayerService;
  String? _fatalBootstrapError;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_bootstrapStarted) {
      return;
    }
    _bootstrapStarted = true;

    try {
      debugPrint('[Startup] Creating Crabify services.');
      final localStorageService = await LocalStorageService.create();
      final audiusApiService = AudiusApiService();
      final audioPlayerService = AudioPlayerService(
        audiusApiService: audiusApiService,
      );
      final downloadService = DownloadService(
        storageService: localStorageService,
      );
      final deviceMediaScannerService = DeviceMediaScannerService();
      final libraryService = LibraryService(
        audiusApiService: audiusApiService,
        localStorageService: localStorageService,
        downloadService: downloadService,
        audioPlayerService: audioPlayerService,
        deviceMediaScannerService: deviceMediaScannerService,
      );

      if (!mounted) {
        audioPlayerService.dispose();
        libraryService.dispose();
        return;
      }

      setState(() {
        _audioPlayerService = audioPlayerService;
        _libraryService = libraryService;
      });

      debugPrint('[Startup] Crabify root shell is ready to render.');
      unawaited(_initializeLibrary(libraryService));
      unawaited(_initializeBackgroundAudio(audioPlayerService));
    } catch (error, stackTrace) {
      debugPrint('[Startup] Service bootstrap failed: $error');
      debugPrint('$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _fatalBootstrapError = error.toString();
      });
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
      if (mounted) {
        setState(() {
          _backgroundBootstrapComplete = true;
        });
      }
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
    } finally {
      if (mounted) {
        setState(() {
          _backgroundBootstrapComplete = true;
        });
      }
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
      _audioPlayerService?.reportError(
        'Enable Android notifications for Crabify to use media controls on the lock screen and in the notification tray.',
      );
    }
  }

  @override
  void dispose() {
    _audioPlayerService?.dispose();
    _libraryService?.dispose();
    super.dispose();
  }

  Widget _buildHome() {
    if (_fatalBootstrapError != null) {
      return CrabifyStartupErrorView(message: _fatalBootstrapError!);
    }

    final libraryService = _libraryService;
    final audioPlayerService = _audioPlayerService;
    if (libraryService == null ||
        audioPlayerService == null ||
        !_backgroundBootstrapComplete) {
      return MaterialApp(
        title: 'Crabify',
        debugShowCheckedModeBanner: false,
        theme: CrabifyTheme.dark(),
        home: const CrabifyBootstrapView(),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryService>.value(value: libraryService),
        ChangeNotifierProvider<AudioPlayerService>.value(value: audioPlayerService),
      ],
      child: MaterialApp(
        title: 'Crabify',
        debugShowCheckedModeBanner: false,
        theme: CrabifyTheme.dark(),
        home: const RootShell(),
      ),
    );
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

    return _buildHome();
  }
}

class CrabifyBootstrapView extends StatelessWidget {
  const CrabifyBootstrapView({super.key});

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
                  const CircularProgressIndicator(),
                  const SizedBox(height: 18),
                  Text(
                    'Starting Crabify',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Loading your library, player, and background services.',
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
