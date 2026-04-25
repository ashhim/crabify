import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/device_audio_candidate.dart';

class DeviceMediaScannerService {
  static const MethodChannel _channel = MethodChannel('crabify/device_media');

  Future<List<DeviceAudioCandidate>> scanDeviceSongs() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const <DeviceAudioCandidate>[];
    }

    final hasPermission = await _ensureAndroidMediaPermission();
    if (!hasPermission) {
      throw StateError(
        'Crabify needs audio library access to scan device songs.',
      );
    }

    final rawResults = await _channel.invokeMethod<List<dynamic>>('scanSongs');
    final candidates =
        (rawResults ?? const <dynamic>[])
            .whereType<Map<Object?, Object?>>()
            .map(DeviceAudioCandidate.fromJson)
            .where(
              (candidate) =>
                  candidate.path.trim().isNotEmpty &&
                  candidate.path.toLowerCase().endsWith('.mp3'),
            )
            .toList();

    debugPrint('[Import] Device scan returned ${candidates.length} items.');
    return candidates;
  }

  Future<bool> _ensureAndroidMediaPermission() async {
    final permissions = <Permission>[
      Permission.audio,
      Permission.storage,
    ];

    final current = await permissions.request();
    final audioGranted = current[Permission.audio]?.isGranted ?? false;
    final storageGranted = current[Permission.storage]?.isGranted ?? false;

    return audioGranted || storageGranted;
  }
}
