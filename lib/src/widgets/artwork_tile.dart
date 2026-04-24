import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/crabify_theme.dart';

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
      (String localPath, _) when localPath.isNotEmpty => Image.file(
        File(localPath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      (_, String remoteUrl) when remoteUrl.isNotEmpty => Image.network(
        remoteUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return const SizedBox.shrink();
        },
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
                  color: CrabifyColors.textPrimary.withValues(alpha: 0.9),
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

const List<List<Color>> _palettes = <List<Color>>[
  <Color>[Color(0xFF2A3D66), Color(0xFF121212)],
  <Color>[Color(0xFF5F0F40), Color(0xFF0F0B14)],
  <Color>[Color(0xFF0A9396), Color(0xFF14213D)],
  <Color>[Color(0xFF9A3412), Color(0xFF1F2937)],
  <Color>[Color(0xFF115E59), Color(0xFF111827)],
  <Color>[Color(0xFF334155), Color(0xFF0F172A)],
];
