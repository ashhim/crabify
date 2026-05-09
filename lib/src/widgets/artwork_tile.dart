import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/crabify_theme.dart';
import 'skeletons.dart';

class ArtworkTile extends StatelessWidget {
  const ArtworkTile({
    super.key,
    required this.seed,
    this.artworkUrl,
    this.artworkPath,
    this.size = 68,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.icon = Icons.graphic_eq_rounded,
  });

  final String seed;
  final String? artworkUrl;
  final String? artworkPath;
  final double size;
  final BorderRadius borderRadius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = artworkPaletteForSeed(seed);
    final imageChild = switch ((artworkPath, artworkUrl)) {
      (String localPath, _) when localPath.isNotEmpty => _ArtworkFrame(
        image: Image.file(
          File(localPath),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        borderRadius: borderRadius,
      ),
      (_, String remoteUrl) when remoteUrl.isNotEmpty => _ArtworkFrame(
        image: Image.network(
          remoteUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        borderRadius: borderRadius,
      ),
      _ => const SizedBox.shrink(),
    };

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: palette,
                ),
              ),
            ),
            imageChild,
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.22),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.all(size * 0.12),
                child: Icon(
                  icon,
                  color: CrabifyColors.accentSoft.withValues(alpha: 0.95),
                  size: size * 0.24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Color> artworkPaletteForSeed(String seed) {
  return _palettes[seed.hashCode.abs() % _palettes.length];
}

ArtworkThemePalette artworkThemePaletteForSeed(String seed) {
  final palette = artworkPaletteForSeed(seed);
  final accent = _liftColor(
    Color.lerp(palette.first, CrabifyColors.accentSoft, 0.22)!,
    minLuminance: 0.34,
  );
  final titleColor = _liftColor(accent, minLuminance: 0.5);
  final subtitleColor = _liftColor(
    Color.lerp(titleColor, CrabifyColors.textSecondary, 0.55)!,
    minLuminance: 0.26,
  );
  return ArtworkThemePalette(
    controlColor: accent,
    titleColor: titleColor,
    subtitleColor: subtitleColor,
  );
}

Future<ArtworkThemePalette> resolveArtworkThemePalette({
  required String seed,
  String? artworkPath,
  String? artworkUrl,
}) {
  final cacheKey = '$seed|${artworkPath ?? ''}|${artworkUrl ?? ''}';
  return _themePaletteCache.putIfAbsent(
    cacheKey,
    () => _resolveArtworkThemePalette(
      seed: seed,
      artworkPath: artworkPath,
      artworkUrl: artworkUrl,
    ),
  );
}

Future<ArtworkThemePalette> _resolveArtworkThemePalette({
  required String seed,
  String? artworkPath,
  String? artworkUrl,
}) async {
  final provider = _imageProviderForArtwork(
    artworkPath: artworkPath,
    artworkUrl: artworkUrl,
  );
  if (provider == null) {
    return artworkThemePaletteForSeed(seed);
  }

  final fallback = artworkThemePaletteForSeed(seed);
  final stream = provider.resolve(const ImageConfiguration());
  final completer = Completer<ArtworkThemePalette>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (imageInfo, _) async {
      stream.removeListener(listener);
      try {
        final byteData = await imageInfo.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (byteData == null) {
          completer.complete(fallback);
          return;
        }
        completer.complete(
          _themePaletteFromRawRgba(byteData.buffer.asUint8List(), fallback),
        );
      } catch (_) {
        completer.complete(fallback);
      }
    },
    onError: (_, __) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete(fallback);
      }
    },
  );
  stream.addListener(listener);

  return completer.future.timeout(
    const Duration(seconds: 4),
    onTimeout: () {
      stream.removeListener(listener);
      return fallback;
    },
  );
}

ImageProvider<Object>? _imageProviderForArtwork({
  String? artworkPath,
  String? artworkUrl,
}) {
  if (artworkPath != null && artworkPath.isNotEmpty) {
    return ResizeImage.resizeIfNeeded(48, 48, FileImage(File(artworkPath)));
  }
  if (artworkUrl != null && artworkUrl.isNotEmpty) {
    return ResizeImage.resizeIfNeeded(48, 48, NetworkImage(artworkUrl));
  }
  return null;
}

ArtworkThemePalette _themePaletteFromRawRgba(
  Uint8List bytes,
  ArtworkThemePalette fallback,
) {
  if (bytes.isEmpty) {
    return fallback;
  }

  final buckets = <int, int>{};
  var weightedRed = 0;
  var weightedGreen = 0;
  var weightedBlue = 0;
  var totalWeight = 0;

  for (var index = 0; index <= bytes.length - 4; index += 4) {
    final red = bytes[index];
    final green = bytes[index + 1];
    final blue = bytes[index + 2];
    final alpha = bytes[index + 3];
    if (alpha < 180) {
      continue;
    }

    final color = Color.fromARGB(alpha, red, green, blue);
    final hsl = HSLColor.fromColor(color);
    if (hsl.saturation < 0.12 || hsl.lightness < 0.1 || hsl.lightness > 0.92) {
      continue;
    }

    final weight = ((hsl.saturation * 3.2) + (1 - (hsl.lightness - 0.52).abs()))
        .clamp(1.0, 4.0)
        .round();
    final bucketKey =
        ((red ~/ 24) << 16) | ((green ~/ 24) << 8) | (blue ~/ 24);
    buckets.update(bucketKey, (value) => value + weight, ifAbsent: () => weight);
    weightedRed += red * weight;
    weightedGreen += green * weight;
    weightedBlue += blue * weight;
    totalWeight += weight;
  }

  if (totalWeight == 0 || buckets.isEmpty) {
    return fallback;
  }

  final dominantBucket = buckets.entries.reduce(
    (best, entry) => entry.value > best.value ? entry : best,
  );
  final averageColor = Color.fromARGB(
    255,
    (weightedRed / totalWeight).round(),
    (weightedGreen / totalWeight).round(),
    (weightedBlue / totalWeight).round(),
  );
  final dominantColor = Color.fromARGB(
    255,
    ((dominantBucket.key >> 16) & 0xFF) * 24,
    ((dominantBucket.key >> 8) & 0xFF) * 24,
    (dominantBucket.key & 0xFF) * 24,
  );
  final blendedAccent = _liftColor(
    Color.lerp(dominantColor, averageColor, 0.35)!,
    minLuminance: 0.34,
  );
  final titleColor = _liftColor(blendedAccent, minLuminance: 0.52);
  final subtitleColor = _liftColor(
    Color.lerp(titleColor, CrabifyColors.textSecondary, 0.58)!,
    minLuminance: 0.26,
  );

  return ArtworkThemePalette(
    controlColor: blendedAccent,
    titleColor: titleColor,
    subtitleColor: subtitleColor,
  );
}

Color _liftColor(Color color, {required double minLuminance}) {
  var hsl = HSLColor.fromColor(color);
  var lifted = color;
  for (var attempt = 0;
      attempt < 6 && lifted.computeLuminance() < minLuminance;
      attempt += 1) {
    hsl = hsl.withLightness((hsl.lightness + 0.08).clamp(0.0, 0.92));
    lifted = hsl.toColor();
  }
  if (lifted.computeLuminance() < minLuminance) {
    lifted = Color.lerp(lifted, Colors.white, 0.12)!;
  }
  return lifted;
}

class ArtworkThemePalette {
  const ArtworkThemePalette({
    required this.controlColor,
    required this.titleColor,
    required this.subtitleColor,
  });

  final Color controlColor;
  final Color titleColor;
  final Color subtitleColor;
}

class _ArtworkFrame extends StatelessWidget {
  const _ArtworkFrame({required this.image, required this.borderRadius});

  final Image image;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: image.image,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        final loaded = wasSynchronouslyLoaded || frame != null;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (!loaded)
              SkeletonShimmer(
                borderRadius: borderRadius,
                child: const SizedBox.expand(),
              ),
            if (loaded) child,
          ],
        );
      },
      errorBuilder: image.errorBuilder,
    );
  }
}

const List<List<Color>> _palettes = <List<Color>>[
  <Color>[Color(0xFF5A3702), Color(0xFF0B0906)],
  <Color>[Color(0xFF8A5A0A), Color(0xFF140F09)],
  <Color>[Color(0xFF3E2A08), Color(0xFF0A0806)],
  <Color>[Color(0xFF6A4208), Color(0xFF110D08)],
  <Color>[Color(0xFF4C3313), Color(0xFF0A0907)],
  <Color>[Color(0xFF7A4E12), Color(0xFF15100A)],
];

final Map<String, Future<ArtworkThemePalette>> _themePaletteCache =
    <String, Future<ArtworkThemePalette>>{};
