import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How deep the launcher sleeps.
enum HibernationLevel {
  /// App not interactive (notification shade, Home, recent apps): caches are
  /// purged and media paused, but the widget tree stays mounted.
  soft,

  /// A game is being launched: the theme subtree is unmounted (dropping every
  /// `ui.Image`/shader/controller it owns) before the intent fires.
  hard,
}

/// Anything holding memory or CPU that must yield to a running game
/// (audio players, video controllers, temp buffers, timers…).
abstract interface class HibernationParticipant {
  FutureOr<void> onHibernate(HibernationLevel level);
  FutureOr<void> onWake();
}

/// Global guardian that keeps the launcher from competing with the game for
/// RAM/CPU/GPU. Install once in `main()` after `ensureInitialized()`.
///
/// Why "hard" hibernation unmounts the tree: `imageCache.clear()` only drops
/// cache bookkeeping — on-screen `Image` widgets still hold their decoded
/// `ui.Image`. Memory is really released only once those widgets dispose.
/// That swap needs a frame, and Flutter stops producing frames once the app
/// is `hidden`/`paused`, so it must happen *before* the launch intent fires
/// (see [prepareForLaunch]).
final class LifecycleMemoryManager with WidgetsBindingObserver {
  LifecycleMemoryManager._();

  static final LifecycleMemoryManager instance = LifecycleMemoryManager._();

  /// Hard ceiling for decoded textures (requirement: ≤ 60 MB).
  static const int maxImageCacheBytes = 60 * 1024 * 1024;

  /// Budget for low-RAM devices (`ActivityManager.isLowRamDevice`).
  static const int lowRamImageCacheBytes = 32 * 1024 * 1024;
  static const int maxImageCacheEntries = 300;

  final Set<HibernationParticipant> _participants = {};
  final ValueNotifier<HibernationLevel?> _level = ValueNotifier(null);
  bool _installed = false;
  bool _launchPending = false;

  /// `null` while awake. The app shell listens to this to unmount the theme.
  ValueListenable<HibernationLevel?> get hibernation => _level;

  bool get isHibernating => _level.value != null;

  void install({int maxBytes = maxImageCacheBytes}) {
    if (_installed) return;
    _installed = true;
    _applyBudget(maxBytes);
    WidgetsBinding.instance.addObserver(this);
  }

  void uninstall() {
    if (!_installed) return;
    WidgetsBinding.instance.removeObserver(this);
    _installed = false;
  }

  /// Shrinks the budget on constrained hardware. Never raises it above 60 MB.
  void applyDeviceBudget({
    required bool isLowRamDevice,
    required int memoryClassMb,
  }) {
    final constrained =
        isLowRamDevice || (memoryClassMb > 0 && memoryClassMb <= 192);
    _applyBudget(constrained ? lowRamImageCacheBytes : maxImageCacheBytes);
  }

  void _applyBudget(int bytes) {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = bytes.clamp(8 * 1024 * 1024, maxImageCacheBytes);
    cache.maximumSize = maxImageCacheEntries;
  }

  void register(HibernationParticipant participant) =>
      _participants.add(participant);

  void unregister(HibernationParticipant participant) =>
      _participants.remove(participant);

  /// Call right before firing a launch intent. Unmounts the theme (via
  /// [hibernation]), waits for that frame, purges caches and pauses media.
  Future<void> prepareForLaunch() async {
    _launchPending = true;
    _enter(HibernationLevel.hard);
    // Let the shell rebuild without the theme so its images get disposed.
    await WidgetsBinding.instance.endOfFrame;
    purgeImageCache();
  }

  /// The launch failed: come back if we are still in the foreground.
  void cancelLaunch() {
    _launchPending = false;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _wake();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _launchPending = false;
        _wake();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _enter(_launchPending ? HibernationLevel.hard : HibernationLevel.soft);
    }
  }

  @override
  void didHaveMemoryPressure() => purgeImageCache();

  /// Drops every cached and live decoded image.
  void purgeImageCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }

  void _enter(HibernationLevel level) {
    final current = _level.value;
    if (current == HibernationLevel.hard || current == level) return;
    _level.value = level;
    purgeImageCache();
    for (final p in _participants.toList()) {
      _guard(() => p.onHibernate(level));
    }
  }

  void _wake() {
    if (_level.value == null) return;
    _level.value = null;
    for (final p in _participants.toList()) {
      _guard(p.onWake);
    }
  }

  void _guard(FutureOr<void> Function() body) {
    try {
      final r = body();
      if (r is Future<void>) {
        r.catchError((Object e, StackTrace s) => _report(e, s));
      }
    } catch (e, s) {
      _report(e, s);
    }
  }

  void _report(Object e, StackTrace s) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: e,
      stack: s,
      library: 'LifecycleMemoryManager',
    ),
  );

  @visibleForTesting
  void debugReset() {
    _participants.clear();
    _level.value = null;
    _launchPending = false;
  }
}
