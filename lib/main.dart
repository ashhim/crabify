import 'dart:async';
import 'dart:ui';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'src/app.dart';
import 'src/services/audio_player_service.dart';
import 'src/services/audius_api_service.dart';
import 'src/services/device_media_scanner_service.dart';
import 'src/services/download_service.dart';
import 'src/services/library_service.dart';
import 'src/services/local_storage_service.dart';
import 'src/services/notification_artwork_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[Startup] FlutterError: ${details.exception}');
    debugPrint('${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    debugPrint('[Startup] PlatformDispatcher error: $error');
    debugPrint('$stackTrace');
    return true;
  };
  ErrorWidget.builder = (details) {
    debugPrint('[Startup] ErrorWidget: ${details.exception}');
    debugPrint('${details.stack}');
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF050505),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFF8B740),
                  size: 40,
                ),
                SizedBox(height: 16),
                Text(
                  'Crabify hit a screen error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  if (!kIsWeb && Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
    debugPrint('[Audio] JustAudioMediaKit initialized for Windows.');
  }

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.crabify.audio',
      androidNotificationChannelName: 'Crabify Playback',
      androidNotificationOngoing: true,
    );
    debugPrint(
      '[Audio] JustAudioBackground initialized on ${Platform.operatingSystem}.',
    );
  }

  if (!kIsWeb) {
    try {
      await NotificationArtworkService.ensureFallbackArtworkReady();
    } catch (error, stackTrace) {
      debugPrint('[Audio] Failed to prepare notification artwork: $error');
      debugPrint('$stackTrace');
    }
  }

  try {
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

    runZonedGuarded(
      () {
        runApp(
          CrabifyApp(
            libraryService: libraryService,
            audioPlayerService: audioPlayerService,
          ),
        );
      },
      (error, stackTrace) {
        debugPrint('[Startup] Uncaught zone error: $error');
        debugPrint('$stackTrace');
      },
    );
  } catch (error, stackTrace) {
    debugPrint('[Startup] Fatal bootstrap error: $error');
    debugPrint('$stackTrace');
    runApp(CrabifyStartupErrorApp(message: error.toString()));
  }
}
