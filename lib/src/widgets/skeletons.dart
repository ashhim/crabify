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
    return SkeletonShimmer(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: width, height: height),
    );
  }
}

class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final alignment = Alignment(-1.2 + (_controller.value * 2.4), 0);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: alignment,
              end: Alignment(alignment.x + 1.2, 0),
              colors: const <Color>[
                CrabifyColors.surface,
                CrabifyColors.surfaceRaised,
                CrabifyColors.surface,
              ],
            ),
          ),
          child: child,
        );
      },
      child: ClipRRect(borderRadius: widget.borderRadius, child: widget.child),
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
