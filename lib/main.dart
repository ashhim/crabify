import 'dart:io';

import 'package:audio_session/audio_session.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    final audioSession = await AudioSession.instance;
    await audioSession.configure(AudioSessionConfiguration.music());
    debugPrint(
      '[Audio] Audio session configured on ${Platform.operatingSystem}.',
    );
  }

  final localStorageService = await LocalStorageService.create();
  final audiusApiService = AudiusApiService();
  final audioPlayerService = AudioPlayerService(
    audiusApiService: audiusApiService,
  );
  final downloadService = DownloadService(storageService: localStorageService);
  final deviceMediaScannerService = DeviceMediaScannerService();
  final libraryService = LibraryService(
    audiusApiService: audiusApiService,
    localStorageService: localStorageService,
    downloadService: downloadService,
    audioPlayerService: audioPlayerService,
    deviceMediaScannerService: deviceMediaScannerService,
  );
  await libraryService.initialize();

  runApp(
    CrabifyApp(
      libraryService: libraryService,
      audioPlayerService: audioPlayerService,
    ),
  );
}
