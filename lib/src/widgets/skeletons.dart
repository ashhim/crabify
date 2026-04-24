import 'package:flutter/material.dart';

import '../theme/crabify_theme.dart';

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.radius = 18,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: CrabifyColors.surfaceRaised,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class PlaylistSkeletonCarousel extends StatelessWidget {
  const PlaylistSkeletonCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder:
            (_, __) => const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonBox(height: 136, width: 144, radius: 18),
                SizedBox(height: 12),
                SkeletonBox(height: 14, width: 120, radius: 8),
                SizedBox(height: 8),
                SkeletonBox(height: 12, width: 84, radius: 8),
              ],
            ),
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemCount: 5,
      ),
    );
  }
}

class TrackListSkeleton extends StatelessWidget {
  const TrackListSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(count, (index) {
        return const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Row(
            children: <Widget>[
              SkeletonBox(height: 56, width: 56, radius: 14),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SkeletonBox(height: 14, radius: 8),
                    SizedBox(height: 8),
                    SkeletonBox(height: 12, width: 120, radius: 8),
                  ],
                ),
              ),
              SizedBox(width: 12),
              SkeletonBox(height: 16, width: 16, radius: 8),
            ],
          ),
        );
      }),
    );
  }
}
