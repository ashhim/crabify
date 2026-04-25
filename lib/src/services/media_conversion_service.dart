import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_minimal/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_minimal/return_code.dart';
import 'package:flutter/foundation.dart';

class MediaConversionService {
  Future<String> convertMp4ToMp3({
    required String sourcePath,
    required String targetPath,
    void Function(double progress)? onProgress,
  }) async {
    if (!await File(sourcePath).exists()) {
      throw FileSystemException(
        'Source video for conversion could not be found.',
        sourcePath,
      );
    }

    final targetFile = File(targetPath);
    final tempTargetPath = '$targetPath.part.mp3';
    final tempTargetFile = File(tempTargetPath);

    if (await tempTargetFile.exists()) {
      await tempTargetFile.delete();
    }
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final completer = Completer<void>();
    debugPrint(
      '[Import] Starting mp4->mp3 conversion'
      ' | source=$sourcePath'
      ' | target=$targetPath',
    );

    await FFmpegKit.executeAsync(
      '-y -i "${_escapePath(sourcePath)}" -vn -acodec libmp3lame -q:a 2 "${_escapePath(tempTargetPath)}"',
      (session) async {
        try {
          final returnCode = await session.getReturnCode();
          if (!ReturnCode.isSuccess(returnCode)) {
            final logs = await session.getAllLogsAsString();
            completer.completeError(
              StateError(
                'Crabify could not convert this MP4 file to MP3.'
                ' FFmpeg exited with ${returnCode?.getValue() ?? 'unknown'}.'
                ' $logs',
              ),
            );
            return;
          }

          if (!await tempTargetFile.exists()) {
            completer.completeError(
              const FileSystemException('Converted MP3 file was not created.'),
            );
            return;
          }

          await tempTargetFile.rename(targetPath);
          onProgress?.call(1);
          completer.complete();
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      null,
      (statistics) {
        final timeMs = statistics.getTime();
        if (timeMs <= 0) {
          onProgress?.call(0);
          return;
        }
        final progress = (timeMs / 180000).clamp(0, 0.98).toDouble();
        onProgress?.call(progress);
      },
    );

    await completer.future;
    debugPrint(
      '[Import] Completed mp4->mp3 conversion'
      ' | source=$sourcePath'
      ' | target=$targetPath',
    );
    return targetPath;
  }

  String _escapePath(String value) {
    return value.replaceAll('"', r'\"');
  }
}
