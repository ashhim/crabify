import 'dart:io';

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
    final palette = _palettes[seed.hashCode.abs() % _palettes.length];
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
