import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio_player_service.dart';
import 'library_service.dart';

class SleepTimerService extends ChangeNotifier with WidgetsBindingObserver {
  SleepTimerService({
    required AudioPlayerService audioPlayerService,
    required LibraryService libraryService,
  }) : _audioPlayerService = audioPlayerService,
       _libraryService = libraryService {
    WidgetsBinding.instance.addObserver(this);
  }

  final AudioPlayerService _audioPlayerService;
  final LibraryService _libraryService;

  Timer? _ticker;
  DateTime? _targetTime;
  Duration _remaining = Duration.zero;
  bool _expiring = false;

  bool get isActive => _targetTime != null;
  DateTime? get targetTime => _targetTime;
  Duration get remaining => _remaining;

  String get countdownLabel {
    if (!isActive) {
      return '';
    }

    final hours = _remaining.inHours.toString().padLeft(2, '0');
    final minutes = _remaining.inMinutes.remainder(60).toString().padLeft(
      2,
      '0',
    );
    final seconds = _remaining.inSeconds.remainder(60).toString().padLeft(
      2,
      '0',
    );
    return 'Sleep in $hours:$minutes:$seconds';
  }

  Future<void> setSleepTime(TimeOfDay selectedTime) async {
    final now = DateTime.now();
    var nextTarget = DateTime(
      now.year,
      now.month,
      now.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    if (!nextTarget.isAfter(now)) {
      nextTarget = nextTarget.add(const Duration(days: 1));
    }

    _targetTime = nextTarget;
    _expiring = false;
    _startTicker();
    _tick(notify: false);
    notifyListeners();
  }

  Future<void> cancel() async {
    _ticker?.cancel();
    _ticker = null;
    _targetTime = null;
    _remaining = Duration.zero;
    _expiring = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _tick();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick({bool notify = true}) {
    final targetTime = _targetTime;
    if (targetTime == null || _expiring) {
      return;
    }

    final secondsLeft = targetTime
        .difference(DateTime.now())
        .inSeconds;
    if (secondsLeft <= 0) {
      _remaining = Duration.zero;
      if (notify) {
        notifyListeners();
      }
      unawaited(_expire());
      return;
    }

    final nextRemaining = Duration(seconds: secondsLeft);
    if (nextRemaining == _remaining) {
      return;
    }
    _remaining = nextRemaining;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _expire() async {
    if (_expiring) {
      return;
    }
    _expiring = true;
    _ticker?.cancel();
    _ticker = null;

    try {
      await _audioPlayerService.stop();
      await _libraryService.persistPlayerSessionNow();
    } catch (error, stackTrace) {
      debugPrint('[SleepTimer] Failed while expiring timer: $error');
      debugPrint('$stackTrace');
    } finally {
      _targetTime = null;
      _remaining = Duration.zero;
      notifyListeners();
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (kIsWeb) {
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      await SystemNavigator.pop();
      return;
    }

    exit(0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }
}
