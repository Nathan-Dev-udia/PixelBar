import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondadeck/core/memory/lifecycle_memory_manager.dart';
import 'package:ondadeck/core/state/library_controller.dart';
import 'package:ondadeck/domain/models/emulator_profile.dart';
import 'package:ondadeck/domain/models/game_item.dart';
import 'package:ondadeck/domain/models/launch_config.dart';
import 'package:ondadeck/domain/models/launcher_settings.dart';
import 'package:ondadeck/domain/models/library_state.dart';
import 'package:ondadeck/domain/models/platform_models.dart';
import 'package:ondadeck/domain/models/theme_manifest.dart';
import 'package:ondadeck/domain/repositories/game_library_repository.dart';
import 'package:ondadeck/domain/repositories/launcher_gateway.dart';
import 'package:ondadeck/main.dart';

class _FakeHibernationParticipant implements HibernationParticipant {
  final List<HibernationLevel> hibernations = [];
  int wakeCount = 0;

  @override
  void onHibernate(HibernationLevel level) => hibernations.add(level);

  @override
  void onWake() => wakeCount++;
}

class _FakeLauncherGateway implements LauncherGateway {
  _FakeLauncherGateway({this.installedApps = const []});

  final List<InstalledApp> installedApps;
  final List<LaunchConfig> launchedConfigs = [];

  @override
  Future<List<InstalledApp>> getInstalledApps({bool gamesOnly = false}) async =>
      gamesOnly ? installedApps.where((a) => a.isGame).toList() : installedApps;

  @override
  Future<Map<String, String>> getAppIcons(
    List<String> packageNames, {
    required int sizePx,
  }) async => const {};

  @override
  Future<bool> isPackageInstalled(String packageName) async =>
      installedApps.any((a) => a.packageName == packageName);

  @override
  Future<void> launch(LaunchConfig config) async {
    launchedConfigs.add(config);
  }

  @override
  Future<SafEntry?> pickDirectory({String? initialUri}) async => null;

  @override
  Future<SafEntry?> pickFile({List<String> mimeTypes = const ['*/*']}) async =>
      null;

  @override
  Future<List<PersistedUri>> getPersistedUris() async => const [];

  @override
  Future<void> releasePersistedUri(String uri) async {}

  @override
  Future<List<SafEntry>> listDirectory(
    String treeUri, {
    bool recursive = false,
    Set<String>? extensions,
    int maxDepth = 6,
    int limit = 20000,
  }) async => const [];

  @override
  Future<String> importArtwork(
    String uri, {
    required int maxWidth,
    required int maxHeight,
  }) async => '';

  @override
  Future<String> readText(String uri) async => '';

  @override
  Future<DeviceProfile> getDeviceProfile() async => const DeviceProfile(
    sdkInt: 34,
    totalRamBytes: 8 * 1024 * 1024 * 1024,
    isLowRamDevice: false,
    memoryClassMb: 512,
    manufacturer: 'OndaTest',
    model: 'DeckSim',
  );
}

class _InMemoryGameLibraryRepository implements GameLibraryRepository {
  final Map<String, GameItem> _games = {};
  LauncherSettings _settings = const LauncherSettings(reduceMotion: true);

  @override
  Future<List<GameItem>> loadAll() async => _games.values.toList();

  @override
  Future<void> upsertAll(List<GameItem> games) async {
    for (final g in games) {
      _games[g.id] = g;
    }
  }

  @override
  Future<void> removeByIds(List<String> ids) async {
    for (final id in ids) {
      _games.remove(id);
    }
  }

  @override
  Future<void> recordLaunch(String id, DateTime at) async {
    final existing = _games[id];
    if (existing != null) {
      _games[id] = existing.copyWith(
        playCount: existing.playCount + 1,
        lastPlayedAt: at,
      );
    }
  }

  @override
  Future<void> setFavorite(String id, {required bool favorite}) async {
    final existing = _games[id];
    if (existing != null) {
      _games[id] = existing.copyWith(favorite: favorite);
    }
  }

  @override
  Future<void> setHidden(String id, {required bool hidden}) async {
    final existing = _games[id];
    if (existing != null) {
      _games[id] = existing.copyWith(hidden: hidden);
    }
  }

  @override
  Future<LauncherSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(LauncherSettings settings) async {
    _settings = settings;
  }
}

void main() {
  tearDown(() {
    LifecycleMemoryManager.instance.debugReset();
    LifecycleMemoryManager.instance.uninstall();
  });

  group('LaunchConfig & EmulatorPresets', () {
    test('substitutes ROM URI tokens and validates cleanly', () {
      expect(EmulatorPresets.dolphin.template.validationError, isNotNull);

      final item = EmulatorPresets.dolphin.createGame(
        romUri:
            'content://com.android.externalstorage.documents/tree/gc/melee.rvz',
        romName: 'Super Smash Bros Melee.rvz',
        platform: 'gc',
        now: DateTime(2026, 1, 1),
      );

      expect(item.title, 'Super Smash Bros Melee');
      expect(item.kind, GameKind.emulated);
      expect(item.platform, 'gc');
      expect(item.launch.validationError, isNull);
      expect(
        item.launch.extras['AutoStartFile'],
        const LaunchExtra.string(
          'content://com.android.externalstorage.documents/tree/gc/melee.rvz',
        ),
      );

      final decoded = LaunchConfig.fromJson(item.launch.toJson());
      expect(decoded, item.launch);
    });
  });

  group('ThemeManifest', () {
    test('parses wireframe_debug theme.json schema', () {
      final raw = File(
        'assets/themes/wireframe_debug/theme.json',
      ).readAsStringSync();
      final manifest = ThemeManifest.parse(
        raw,
        basePath: 'assets/themes/wireframe_debug',
      );

      expect(manifest.id, 'wireframe_debug');
      expect(manifest.engine, 'wireframe_debug');
      expect(manifest.color('accent', 0), 0xFF00E5FF);
      expect(manifest.option<int>('iconSize', 0), 72);
      expect(manifest.audio.enabled, isFalse);
    });
  });

  group('LifecycleMemoryManager', () {
    testWidgets(
      'enforces 60 MB ceiling, soft pause hibernation, and hard launch hibernation',
      (tester) async {
        final manager = LifecycleMemoryManager.instance..install();
        final participant = _FakeHibernationParticipant();
        manager.register(participant);

        expect(
          PaintingBinding.instance.imageCache.maximumSizeBytes,
          LifecycleMemoryManager.maxImageCacheBytes,
        );

        manager.applyDeviceBudget(isLowRamDevice: true, memoryClassMb: 128);
        expect(
          PaintingBinding.instance.imageCache.maximumSizeBytes,
          LifecycleMemoryManager.lowRamImageCacheBytes,
        );

        manager.didChangeAppLifecycleState(AppLifecycleState.paused);
        expect(manager.hibernation.value, HibernationLevel.soft);
        expect(participant.hibernations, [HibernationLevel.soft]);

        manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(manager.hibernation.value, isNull);
        expect(participant.wakeCount, 1);

        final prep = manager.prepareForLaunch();
        await tester.pump();
        await prep;
        expect(manager.hibernation.value, HibernationLevel.hard);
        expect(participant.hibernations.last, HibernationLevel.hard);
      },
    );
  });

  group('WireframeDebugTheme gamepad navigation & launch', () {
    testWidgets(
      'lists installed games, navigates with D-Pad arrows, and launches with GameButtonA',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        LifecycleMemoryManager.instance.install();

        final fakeGateway = _FakeLauncherGateway(
          installedApps: const [
            InstalledApp(
              packageName: 'com.test.alpha',
              label: 'Alpha Game',
              isGame: true,
            ),
            InstalledApp(
              packageName: 'com.test.beta',
              label: 'Beta Port',
              isGame: true,
            ),
            InstalledApp(
              packageName: 'com.test.utility',
              label: 'Utility App',
              isGame: false,
            ),
          ],
        );
        final fakeRepo = _InMemoryGameLibraryRepository();

        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              launcherGatewayProvider.overrideWithValue(fakeGateway),
              gameLibraryRepositoryProvider.overrideWithValue(fakeRepo),
            ],
            child: Consumer(
              builder: (context, ref, child) {
                container = ProviderScope.containerOf(context);
                return const OndaDeckApp();
              },
            ),
          ),
        );

        // Allow initialize() and Isolate.run calls to complete, pumping FakeAsync microtasks each tick.
        for (var i = 0; i < 60; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
          final s = container.read(libraryControllerProvider);
          if (s.status == LibraryStatus.ready &&
              !s.isSyncing &&
              s.categories.isNotEmpty) {
            break;
          }
        }
        await tester.pumpAndSettle();

        expect(find.text('Alpha Game'), findsNWidgets(2));
        expect(find.text('Beta Port'), findsOneWidget);
        expect(find.text('Utility App'), findsNothing);
        expect(
          container.read(libraryControllerProvider).focusedGameId,
          'pkg:com.test.alpha',
        );

        // Navigate right via D-Pad.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(
          container.read(libraryControllerProvider).focusedGameId,
          'pkg:com.test.beta',
        );

        // Launch focused game via Gamepad A button.
        await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
        await tester.pump();
        for (var i = 0; i < 20 && fakeGateway.launchedConfigs.isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }

        expect(fakeGateway.launchedConfigs, [
          const LaunchConfig.package('com.test.beta'),
        ]);
        expect(
          LifecycleMemoryManager.instance.hibernation.value,
          HibernationLevel.hard,
        );
      },
    );
  });
}
