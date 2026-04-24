import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../models/upload_draft.dart';
import '../services/audio_player_service.dart';
import '../theme/crabify_theme.dart';
import '../widgets/mini_player.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'liked_songs_screen.dart';
import 'now_playing_screen.dart';
import 'search_screen.dart';
import 'upload_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(onOpenUpload: _openUpload),
      const SearchScreen(),
      LibraryScreen(onOpenUpload: _openUpload),
      const LikedSongsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: Consumer<AudioPlayerService>(
        builder: (context, audio, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MiniPlayer(
                audioPlayerService: audio,
                onOpenPlayer: _openNowPlaying,
              ),
              Container(
                color: CrabifyColors.topBar,
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                child: SafeArea(
                  top: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: <Widget>[
                      _NavItem(
                        icon: FontAwesomeIcons.house,
                        label: 'Home',
                        active: _currentIndex == 0,
                        onTap: () => setState(() => _currentIndex = 0),
                      ),
                      _NavItem(
                        icon: FontAwesomeIcons.magnifyingGlass,
                        label: 'Search',
                        active: _currentIndex == 1,
                        onTap: () => setState(() => _currentIndex = 1),
                      ),
                      _NavItem(
                        icon: FontAwesomeIcons.bookOpen,
                        label: 'Library',
                        active: _currentIndex == 2,
                        onTap: () => setState(() => _currentIndex = 2),
                      ),
                      _NavItem(
                        icon: FontAwesomeIcons.solidHeart,
                        label: 'Liked',
                        active: _currentIndex == 3,
                        onTap: () => setState(() => _currentIndex = 3),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openUpload() async {
    final result = await Navigator.of(context).push<UploadSubmissionResult>(
      MaterialPageRoute<UploadSubmissionResult>(
        builder: (_) => const UploadScreen(),
        fullscreenDialog: true,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _openNowPlaying() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const NowPlayingScreen()),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? CrabifyColors.textPrimary : CrabifyColors.textMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FaIcon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
