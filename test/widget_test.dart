import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondadeck/core/memory/lifecycle_memory_manager.dart';
import 'package:ondadeck/core/state/library_controller.dart';
import 'package:ondadeck/data/theme/theme_package_service.dart';
import 'package:ondadeck/data/theme/zip_archive_extractor.dart';
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
import 'package:ondadeck/themes/data_driven/data_driven_theme_engine.dart';
import 'package:ondadeck/themes/manager/theme_manager_screen.dart';
import 'package:path/path.dart' as p;

class _FakeHibernationParticipant implements HibernationParticipant {
  final List<HibernationLevel> hibernations = [];
  int wakeCount = 0;

  @override
  void onHibernate(HibernationLevel level) => hibernations.add(level);

  @override
  void onWake() => wakeCount++;
}

class _FakeLauncherGateway implements LauncherGateway {
  _FakeLauncherGateway({this.installedApps = const [], this.pickedFile});

  final List<InstalledApp> installedApps;
  final SafEntry? pickedFile;
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
      pickedFile;

  @override
  Future<String> copyDocumentToCache(
    String uri, {
    String? preferredName,
  }) async => uri;

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
        final tempThemesDir = Directory.systemTemp.createTempSync(
          'ondadeck_widget_themes_',
        );
        addTearDown(() {
          if (tempThemesDir.existsSync()) {
            tempThemesDir.deleteSync(recursive: true);
          }
        });
        final packageService = ThemePackageService(
          themesDirProvider: () async => tempThemesDir.path,
        );

        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              launcherGatewayProvider.overrideWithValue(fakeGateway),
              gameLibraryRepositoryProvider.overrideWithValue(fakeRepo),
              themePackageServiceProvider.overrideWithValue(packageService),
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

  group('ThemeLayoutNode & DataDrivenThemeEngine bindings', () {
    test('parses built-in wireframe_debug layout.json and manifest.json', () {
      final manifestRaw = File(
        'assets/themes/wireframe_debug/manifest.json',
      ).readAsStringSync();
      final layoutRaw = File(
        'assets/themes/wireframe_debug/layout.json',
      ).readAsStringSync();

      final manifest = ThemeManifest.parse(
        manifestRaw,
        basePath: 'assets/themes/wireframe_debug',
        isBuiltIn: true,
      ).copyWith(layout: ThemeLayoutNode.parse(layoutRaw));

      expect(manifest.id, 'wireframe_debug');
      expect(manifest.engine, 'data_driven');
      expect(manifest.isBuiltIn, isTrue);
      expect(manifest.layout, isNotNull);
      expect(manifest.layout!.type, ThemeNodeType.stack);
      expect(manifest.colors['accent'], 0xFF00E5FF);
    });

    test('evaluates {{selectedGame.*}} and {{theme.*}} tokens', () {
      final game = GameItem(
        id: 'pkg:com.test.zelda',
        title: 'Zelda Recomp',
        kind: GameKind.recompPort,
        source: GameSource.manual,
        platform: 'n64',
        launch: const LaunchConfig.package('com.test.zelda'),
        media: const MediaAssets(
          iconPath: '/tmp/icon.png',
          coverPath: '/tmp/cover.png',
          logoPath: '/tmp/logo.png',
          bannerPath: '/tmp/banner.png',
        ),
        playCount: 3,
        lastPlayedAt: DateTime(2026, 3, 10, 14, 30),
        addedAt: DateTime(2026, 1, 1),
      );
      final category = GameCategory(
        id: 'all',
        title: 'Todos',
        kind: CategoryKind.recomp,
        games: [game],
      );
      final state = LibraryState(
        status: LibraryStatus.ready,
        categories: [category],
        focusedGameId: game.id,
        settings: const LauncherSettings(),
        theme: const ThemeManifest(
          id: 'custom',
          name: 'Custom Theme',
          author: 'Onda Pixel',
          version: '1.0.0',
          engine: 'data_driven',
          basePath: '/tmp',
          defaultColors: {'accent': 0xFFFF5370},
          colors: {'accent': 0xFFFF5370},
        ),
      );

      expect(
        DataDrivenThemeEngine.resolveBindings(
          '{{selectedGame.title}} [{{selectedGame.platform}}] ({{selectedGame.playCount}}x) {{theme.accent}}',
          state: state,
          category: category,
          game: game,
        ),
        'Zelda Recomp [N64] (3x) #FF5370',
      );
      expect(
        DataDrivenThemeEngine.resolveBindings(
          '{{selectedGame.clearLogo}}|{{selectedGame.heroBanner}}|{{selectedGame.cover}}|{{library.totalGames}}',
          state: state,
          category: category,
          game: game,
        ),
        '/tmp/logo.png|/tmp/banner.png|/tmp/cover.png|1',
      );
    });
  });

  group('ZipArchiveExtractor & ThemePackageService', () {
    test(
      'imports valid .ondatheme archive, manages overrides & protects built-in',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'ondadeck_pkg_test_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final service = ThemePackageService(
          themesDirProvider: () async => p.join(tempDir.path, 'themes'),
        );

        final manifestJson = jsonEncode({
          'id': 'neon_arcade',
          'name': 'Neon Arcade',
          'author': 'Comunidade',
          'version': '1.0.0',
          'description': 'Tema de teste comunitário',
          'previewImage': 'assets/preview.png',
          'colors': {
            'primary': '#101420',
            'accent': '#00E5FF',
            'background': '#05070B',
            'textPrimary': '#FFFFFF',
            'textSecondary': '#9AA4B2',
            'focusGlow': '#00E5FF',
          },
        });
        final layoutJson = jsonEncode({
          'type': 'Stack',
          'children': [
            {
              'type': 'DynamicBackground',
              'image': 'assets/bg.png',
              'color': '{{theme.background}}',
            },
            {
              'type': 'MediaCarousel',
              'direction': 'horizontal',
              'itemAsset': 'cover',
            },
          ],
        });

        final validZipBytes = ZipArchiveExtractor.createZipBytes({
          'manifest.json': Uint8List.fromList(utf8.encode(manifestJson)),
          'layout.json': Uint8List.fromList(utf8.encode(layoutJson)),
          'assets/preview.png': Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
          'assets/bg.png': Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
        });
        final archivePath = p.join(tempDir.path, 'neon_arcade.ondatheme');
        File(archivePath).writeAsBytesSync(validZipBytes);

        final imported = await service.importThemePackage(archivePath);
        expect(imported.id, 'neon_arcade');
        expect(imported.isBuiltIn, isFalse);
        expect(imported.colors['accent'], 0xFF00E5FF);
        expect(imported.layout, isNotNull);

        final installed = await service.listInstalledThemes();
        expect(
          installed.map((t) => t.id),
          containsAll(['wireframe_debug', 'ps3_xmb', 'neon_arcade']),
        );

        final overridden = await service.saveColorOverrides('neon_arcade', {
          'accent': 0xFFFF5370,
        });
        expect(overridden.colors['accent'], 0xFFFF5370);
        expect(overridden.defaultColors['accent'], 0xFF00E5FF);

        final reset = await service.resetColorOverrides('neon_arcade');
        expect(reset.colors['accent'], 0xFF00E5FF);

        await expectLater(
          service.deleteImportedTheme('wireframe_debug'),
          throwsA(isA<ThemeManifestException>()),
        );
        await expectLater(
          service.deleteImportedTheme('ps3_xmb'),
          throwsA(isA<ThemeManifestException>()),
        );

        await service.deleteImportedTheme('neon_arcade');
        final afterDelete = await service.listInstalledThemes();
        expect(afterDelete.any((t) => t.id == 'neon_arcade'), isFalse);
      },
    );

    test('rejects path traversal and missing referenced assets', () async {
      final tempDir = Directory.systemTemp.createTempSync('ondadeck_sec_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final service = ThemePackageService(
        themesDirProvider: () async => p.join(tempDir.path, 'themes'),
      );

      final traversalBytes = ZipArchiveExtractor.createZipBytes({
        '../evil.txt': Uint8List.fromList(utf8.encode('pwned')),
        'manifest.json': Uint8List.fromList(utf8.encode('{}')),
      });
      final traversalPath = p.join(tempDir.path, 'evil.zip');
      File(traversalPath).writeAsBytesSync(traversalBytes);

      await expectLater(
        service.importThemePackage(traversalPath),
        throwsA(isA<ThemeManifestException>()),
      );

      final missingAssetManifest = jsonEncode({
        'id': 'broken_theme',
        'name': 'Broken Theme',
        'author': 'Test',
        'version': '1.0.0',
        'previewImage': 'assets/does_not_exist.png',
        'colors': {'accent': '#00E5FF'},
      });
      final missingAssetLayout = jsonEncode({'type': 'Stack', 'children': []});
      final missingAssetZip = ZipArchiveExtractor.createZipBytes({
        'manifest.json': Uint8List.fromList(utf8.encode(missingAssetManifest)),
        'layout.json': Uint8List.fromList(utf8.encode(missingAssetLayout)),
      });
      final missingPath = p.join(tempDir.path, 'broken.ondatheme');
      File(missingPath).writeAsBytesSync(missingAssetZip);

      await expectLater(
        service.importThemePackage(missingPath),
        throwsA(isA<ThemeManifestException>()),
      );
    });
  });

  group('ThemeManagerDialog & SAF import integration', () {
    testWidgets('imports theme via SAF, activates it, and edits/resets colors', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      LifecycleMemoryManager.instance.install();

      final tempDir = Directory.systemTemp.createTempSync('ondadeck_mgr_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final manifestJson = jsonEncode({
        'id': 'retro_deck',
        'name': 'Retro Deck',
        'author': 'Onda Community',
        'version': '1.1.0',
        'description': 'Layout horizontal retrô',
        'colors': {
          'primary': '#1E1B2E',
          'accent': '#FFC400',
          'background': '#0D0B14',
          'surface': '#171426',
          'textPrimary': '#FFFFFF',
          'textSecondary': '#A6A1C0',
          'focusGlow': '#FFC400',
        },
      });
      final layoutJson = jsonEncode({
        'type': 'Stack',
        'children': [
          {'type': 'DynamicBackground', 'color': '{{theme.background}}'},
          {
            'type': 'MediaCarousel',
            'direction': 'horizontal',
            'itemAsset': 'cover',
          },
        ],
      });
      final zipBytes = ZipArchiveExtractor.createZipBytes({
        'manifest.json': Uint8List.fromList(utf8.encode(manifestJson)),
        'layout.json': Uint8List.fromList(utf8.encode(layoutJson)),
      });
      final archiveFile = File(p.join(tempDir.path, 'retro_deck.ondatheme'))
        ..writeAsBytesSync(zipBytes);

      final fakeGateway = _FakeLauncherGateway(
        installedApps: const [
          InstalledApp(
            packageName: 'com.test.sonic',
            label: 'Sonic Mania',
            isGame: true,
          ),
        ],
        pickedFile: SafEntry(
          uri: archiveFile.path,
          name: 'retro_deck.ondatheme',
          isDirectory: false,
          size: zipBytes.length,
        ),
      );
      final fakeRepo = _InMemoryGameLibraryRepository();
      final packageService = ThemePackageService(
        themesDirProvider: () async => p.join(tempDir.path, 'themes'),
      );

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            launcherGatewayProvider.overrideWithValue(fakeGateway),
            gameLibraryRepositoryProvider.overrideWithValue(fakeRepo),
            themePackageServiceProvider.overrideWithValue(packageService),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                container = ProviderScope.containerOf(context);
                final state = ref.watch(libraryControllerProvider);
                return Scaffold(
                  body: state.status == LibraryStatus.ready
                      ? const ThemeManagerDialog()
                      : const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      );

      await tester.runAsync(
        () => container.read(libraryControllerProvider.notifier).initialize(),
      );
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        final s = container.read(libraryControllerProvider);
        if (s.status == LibraryStatus.ready &&
            !s.isSyncing &&
            find.text('Onda Default (Wireframe)').evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();

      expect(find.text('TEMAS & EDITOR DE CORES'), findsOneWidget);
      expect(find.text('Onda Default (Wireframe)'), findsOneWidget);

      // Trigger SAF import via button tap.
      await tester.tap(find.text('Importar Tema (.zip / .ondatheme)'));
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (container.read(libraryControllerProvider).theme.id ==
                'retro_deck' &&
            find.text('Retro Deck').evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();

      expect(container.read(libraryControllerProvider).theme.id, 'retro_deck');
      expect(find.text('Retro Deck'), findsWidgets);

      // Switch to Color Editor tab and test HSV/Hex edit + Save + Restore Default.
      await tester.tap(find.text('[R1] Editor de Cores'));
      await tester.pumpAndSettle();
      expect(find.text('Matiz (H)'), findsOneWidget);
      expect(find.text('Salvar Cores'), findsOneWidget);
      expect(find.text('Restaurar Padrão'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '#FF5370');
      await tester.tap(find.text('Aplicar Hex'));
      await tester.pump();

      await tester.tap(find.text('Salvar Cores'));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (container.read(libraryControllerProvider).theme.colors['primary'] ==
            0xFFFF5370) {
          break;
        }
      }
      expect(
        container.read(libraryControllerProvider).theme.colors['primary'],
        0xFFFF5370,
      );

      await tester.tap(find.text('Restaurar Padrão'));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (container.read(libraryControllerProvider).theme.colors['primary'] ==
            0xFF1E1B2E) {
          break;
        }
      }
      expect(
        container.read(libraryControllerProvider).theme.colors['primary'],
        0xFF1E1B2E,
      );
    });
  });

  group('Built-in PS3 XMB layout & XrossMediaBar navigation', () {
    testWidgets(
      'appears in theme manager menu, activates cleanly, and navigates via D-Pad',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        LifecycleMemoryManager.instance.install();

        final tempThemesDir = Directory.systemTemp.createTempSync(
          'ondadeck_ps3_xmb_test_',
        );
        addTearDown(() {
          if (tempThemesDir.existsSync()) {
            tempThemesDir.deleteSync(recursive: true);
          }
        });

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
          ],
        );
        final fakeRepo = _InMemoryGameLibraryRepository();
        final packageService = ThemePackageService(
          themesDirProvider: () async => tempThemesDir.path,
        );

        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              launcherGatewayProvider.overrideWithValue(fakeGateway),
              gameLibraryRepositoryProvider.overrideWithValue(fakeRepo),
              themePackageServiceProvider.overrideWithValue(packageService),
            ],
            child: Consumer(
              builder: (context, ref, child) {
                container = ProviderScope.containerOf(context);
                return const OndaDeckApp();
              },
            ),
          ),
        );

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

        // Open Theme Manager directly from HUD button and verify PS3 XMB is built-in.
        await tester.tap(find.text('Layouts & Cores'));
        for (var i = 0; i < 60; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
          if (find.text('PS3 XMB (XrossMediaBar)').evaluate().isNotEmpty) {
            break;
          }
        }
        await tester.pumpAndSettle();

        expect(find.text('PS3 XMB (XrossMediaBar)'), findsOneWidget);
        expect(find.text('Ativar'), findsOneWidget);

        // Activate PS3 XMB from the menu.
        await tester.tap(find.text('Ativar'));
        for (var i = 0; i < 60; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
          if (container.read(libraryControllerProvider).theme.id == 'ps3_xmb') {
            break;
          }
        }
        await tester.pumpAndSettle();

        expect(container.read(libraryControllerProvider).theme.id, 'ps3_xmb');

        // Close manager dialog to view the active PS3 XMB screen.
        await tester.tap(find.text('Fechar [B]'));
        await tester.pumpAndSettle();

        expect(find.textContaining('PS3™ XMB  //'), findsOneWidget);
        expect(find.text('Alpha Game'), findsWidgets);
        expect(find.text('Beta Port'), findsOneWidget);
        expect(
          container.read(libraryControllerProvider).focusedGameId,
          'pkg:com.test.alpha',
        );

        // Navigate vertically down along the XMB spine via D-Pad.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(
          container.read(libraryControllerProvider).focusedGameId,
          'pkg:com.test.beta',
        );
      },
    );
  });
}
