import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../theme/crabify_theme.dart';

abstract final class NotificationArtworkService {
  static Uri? _cachedFallbackArtworkUri;

  static Uri? get cachedFallbackArtworkUri => _cachedFallbackArtworkUri;

  static Future<Uri?> ensureFallbackArtworkReady() async {
    final existing = _cachedFallbackArtworkUri;
    if (existing != null) {
      return existing;
    }

    final tempDirectory = await getTemporaryDirectory();
    final targetFile = File(
      path.join(tempDirectory.path, 'crabify_notification_fallback.png'),
    );
    if (!await targetFile.exists()) {
      const width = 512;
      const height = 512;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      canvas.drawRect(bounds, Paint()..color = CrabifyColors.background);

      final splitStart = width * 0.65;
      final goldRect = Rect.fromLTWH(
        splitStart,
        0,
        width - splitStart,
        height.toDouble(),
      );
      canvas.drawRect(
        goldRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(splitStart, 0),
            Offset(width.toDouble(), height.toDouble()),
            const <Color>[
              CrabifyColors.goldSecondary,
              CrabifyColors.goldPrimary,
            ],
          ),
      );
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            Offset(width.toDouble(), height.toDouble()),
            <Color>[
              Colors.transparent,
              CrabifyColors.goldGlow,
              Colors.transparent,
            ],
          ),
      );

      final image = await recorder.endRecording().toImage(width, height);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        await targetFile.writeAsBytes(
          byteData.buffer.asUint8List(),
          flush: true,
        );
      }
    }

    _cachedFallbackArtworkUri = Uri.file(targetFile.path);
    return _cachedFallbackArtworkUri;
  }
}
