import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/metadata/game_metadata_service.dart';
import '../../data/repositories/sqflite_game_library_repository.dart';
import '../../data/sync/library_sync_service.dart';
import '../../data/theme/theme_manifest_loader.dart';
import '../../data/theme/theme_package_service.dart';
import '../../data/update/app_update_service.dart';
import '../../domain/models/game_item.dart';
import '../../domain/models/launcher_settings.dart';
import '../../domain/models/library_state.dart';
import '../../domain/models/platform_models.dart';
import '../../domain/models/theme_manifest.dart';
import '../../domain/repositories/game_library_repository.dart';
import '../../domain/repositories/launcher_gateway.dart';
import '../../domain/services/library_indexer.dart';
import '../../platform/native_launcher_channel.dart';
import '../memory/lifecycle_memory_manager.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final launcherGatewayProvider = Provider<LauncherGateway>(
  (ref) => NativeLauncherChannel(),
);

final gameLibraryRepositoryProvider = Provider<GameLibraryRepository>(
  (ref) => SqfliteGameLibraryRepository(ref.watch(appDatabaseProvider)),
);

final librarySyncServiceProvider = Provider<LibrarySyncService>(
  (ref) => LibrarySyncService(
    ref.watch(launcherGatewayProvider),
    ref.watch(gameLibraryRepositoryProvider),
  ),
);

final themeManifestLoaderProvider = Provider<ThemeManifestLoader>(
  (ref) => ThemeManifestLoader(gateway: ref.watch(launcherGatewayProvider)),
);

final themePackageServiceProvider = Provider<ThemePackageService>(
  (ref) => ThemePackageService(),
);

final gameMetadataServiceProvider = Provider<GameMetadataService>(
  (ref) => GameMetadataService(),
);

final appUpdateServiceProvider = Provider<AppUpdateService>(
  (ref) => AppUpdateService(gateway: ref.watch(launcherGatewayProvider)),
);

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);

class LibraryController extends Notifier<LibraryState> {
  List<GameItem> _allGames = const [];
  bool _initialized = false;

  LauncherGateway get _gateway => ref.read(launcherGatewayProvider);
  GameLibraryRepository get _repository =>
      ref.read(gameLibraryRepositoryProvider);
  LibrarySyncService get _syncService => ref.read(librarySyncServiceProvider);
  ThemeManifestLoader get _themeLoader => ref.read(themeManifestLoaderProvider);
  ThemePackageService get _themePackageService =>
      ref.read(themePackageServiceProvider);
  GameMetadataService get metadataService =>
      ref.read(gameMetadataServiceProvider);

  @override
  LibraryState build() {
    if (!_initialized) {
      _initialized = true;
      Future.microtask(initialize);
    }
    return LibraryState.initial();
  }

  Future<void> initialize() async {
    try {
      final profile = await _gateway.getDeviceProfile();
      if (!ref.mounted) return;
      LifecycleMemoryManager.instance.applyDeviceBudget(
        isLowRamDevice: profile.isLowRamDevice,
        memoryClassMb: profile.memoryClassMb,
      );
    } on Object {
      // Non-Android / test hosts fall back to the default 60 MB ceiling.
    }

    try {
      final settings = await _repository.loadSettings();
      if (!ref.mounted) return;

      final theme = await _loadThemeManifest(settings.activeThemeId);
      if (!ref.mounted) return;

      _allGames = await _repository.loadAll();
      if (!ref.mounted) return;

      final categories = await _buildCategories(_allGames, settings);
      if (!ref.mounted) return;

      state = state.copyWith(
        status: LibraryStatus.ready,
        categories: categories,
        theme: theme,
        settings: settings,
        focusedGameId: _firstGameId(categories, preferred: state.focusedGameId),
        clearError: true,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: LibraryStatus.error,
        errorMessage: 'Erro ao carregar biblioteca: $e',
      );
      return;
    }

    await refreshInstalledApps();
  }

  Future<ThemeManifest> _loadThemeManifest(String themeId) async {
    try {
      return await _themePackageService.loadTheme(themeId);
    } on Object {
      try {
        return await _themeLoader.loadAsset(
          'assets/themes/$themeId/theme.json',
        );
      } on Object {
        return ThemeManifest.fallback;
      }
    }
  }

  Future<List<ThemeManifest>> listThemes() =>
      _themePackageService.listInstalledThemes();

  Future<void> activateTheme(String themeId) async {
    await updateSettings(state.settings.copyWith(activeThemeId: themeId));
  }

  Future<ThemeManifest?> importThemeFromSaf() async {
    final picked = await _gateway.pickFile(
      mimeTypes: const ['application/zip', 'application/octet-stream', '*/*'],
    );
    if (picked == null) return null;

    final cachedArchive = await _gateway.copyDocumentToCache(
      picked.uri,
      preferredName: picked.name,
    );
    final imported = await _themePackageService.importThemePackage(
      cachedArchive,
    );
    if (!ref.mounted) return imported;

    final nextSettings = state.settings.copyWith(activeThemeId: imported.id);
    await _repository.saveSettings(nextSettings);
    if (!ref.mounted) return imported;

    state = state.copyWith(settings: nextSettings, theme: imported);
    return imported;
  }

  Future<void> saveThemeColorOverrides(
    String themeId,
    Map<String, int> overrides,
  ) async {
    final updated = await _themePackageService.saveColorOverrides(
      themeId,
      overrides,
    );
    if (!ref.mounted) return;
    if (state.theme.id == themeId) {
      state = state.copyWith(theme: updated);
    }
  }

  Future<void> resetThemeColorOverrides(String themeId) async {
    final reset = await _themePackageService.resetColorOverrides(themeId);
    if (!ref.mounted) return;
    if (state.theme.id == themeId) {
      state = state.copyWith(theme: reset);
    }
  }

  Future<void> deleteTheme(String themeId) async {
    await _themePackageService.deleteImportedTheme(themeId);
    if (!ref.mounted) return;
    if (state.settings.activeThemeId == themeId) {
      await activateTheme(ThemePackageService.builtInDefaultId);
    }
  }

  Future<void> refreshInstalledApps() async {
    if (!ref.mounted || state.isSyncing) return;
    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final synced = await _syncService.syncInstalledApps(
        autoImportGames: state.settings.autoImportGames,
        gamesFolderUri: state.settings.gamesFolderUri,
      );
      if (!ref.mounted) return;

      _allGames = synced;
      final categories = await _buildCategories(_allGames, state.settings);
      if (!ref.mounted) return;

      state = state.copyWith(
        status: LibraryStatus.ready,
        categories: categories,
        focusedGameId: _firstGameId(categories, preferred: state.focusedGameId),
        isSyncing: false,
        lastSyncAt: DateTime.now(),
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isSyncing: false,
        errorMessage: 'Falha ao sincronizar jogos da pasta: $e',
      );
    }
  }

  /// Returns all launchable apps & games currently installed on the device.
  Future<List<InstalledApp>> loadInstalledApps() =>
      _gateway.getInstalledApps(gamesOnly: false);

  /// Extracts icons for [packageNames] so the picker UI can show app icons.
  Future<Map<String, String>> loadAppIcons(List<String> packageNames) {
    if (packageNames.isEmpty) return Future.value(const {});
    return _gateway.getAppIcons(
      packageNames,
      sizePx: LibrarySyncService.iconSizePx,
    );
  }

  /// Opens the native Android SAF folder picker and scans APKs/ROMs from the
  /// chosen directory only.
  Future<SafEntry?> pickAndSyncGamesFolder() async {
    final picked = await _gateway.pickDirectory(
      initialUri: state.settings.gamesFolderUri,
    );
    if (picked == null || !ref.mounted) return null;

    final nextSettings = state.settings.copyWith(
      gamesFolderUri: picked.uri,
      gamesFolderName: picked.name.isEmpty ? picked.uri : picked.name,
    );
    await updateSettings(nextSettings);
    if (!ref.mounted) return picked;

    await refreshInstalledApps();
    return picked;
  }

  void selectGame(GameItem game) {
    if (state.focusedGameId == game.id) return;
    state = state.copyWith(focusedGameId: game.id);
  }

  Future<void> launchGame(GameItem game) async {
    if (state.isLaunching) return;
    state = state.copyWith(
      isLaunching: true,
      focusedGameId: game.id,
      clearError: true,
    );

    try {
      await LifecycleMemoryManager.instance.prepareForLaunch();
      await _gateway.launch(game.launch);

      final now = DateTime.now();
      await _repository.recordLaunch(game.id, now);
      if (!ref.mounted) return;

      _allGames = [
        for (final g in _allGames)
          if (g.id == game.id)
            g.copyWith(playCount: g.playCount + 1, lastPlayedAt: now)
          else
            g,
      ];
      final categories = await _buildCategories(_allGames, state.settings);
      if (!ref.mounted) return;

      state = state.copyWith(categories: categories, isLaunching: false);
    } on Object catch (e) {
      LifecycleMemoryManager.instance.cancelLaunch();
      if (!ref.mounted) return;
      state = state.copyWith(isLaunching: false, errorMessage: e.toString());
    }
  }

  Future<void> addManualApp(
    InstalledApp app, {
    GameKind kind = GameKind.androidNative,
  }) async {
    try {
      final added = await _syncService.addManualApp(app, kind: kind);
      if (!ref.mounted) return;

      _allGames = [
        for (final g in _allGames)
          if (g.id != added.id) g,
        added,
      ];
      final categories = await _buildCategories(_allGames, state.settings);
      if (!ref.mounted) return;

      state = state.copyWith(
        status: LibraryStatus.ready,
        categories: categories,
        focusedGameId: added.id,
        clearError: true,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(errorMessage: 'Erro ao adicionar aplicativo: $e');
    }
  }

  Future<void> removeGame(GameItem game) async {
    try {
      if (game.source == GameSource.manual) {
        await _repository.removeByIds([game.id]);
        if (!ref.mounted) return;
        _allGames = [
          for (final g in _allGames)
            if (g.id != game.id) g,
        ];
      } else {
        await _repository.setHidden(game.id, hidden: true);
        if (!ref.mounted) return;
        _allGames = [
          for (final g in _allGames)
            if (g.id == game.id) g.copyWith(hidden: true) else g,
        ];
      }
      final categories = await _buildCategories(_allGames, state.settings);
      if (!ref.mounted) return;

      state = state.copyWith(
        status: LibraryStatus.ready,
        categories: categories,
        focusedGameId: _firstGameId(categories, preferred: state.focusedGameId),
        clearError: true,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(errorMessage: 'Erro ao retirar aplicativo: $e');
    }
  }

  Future<void> toggleFavorite(GameItem game) async {
    final nextFav = !game.favorite;
    await _repository.setFavorite(game.id, favorite: nextFav);
    if (!ref.mounted) return;

    _allGames = [
      for (final g in _allGames)
        if (g.id == game.id) g.copyWith(favorite: nextFav) else g,
    ];
    final categories = await _buildCategories(_allGames, state.settings);
    if (!ref.mounted) return;

    state = state.copyWith(categories: categories, focusedGameId: game.id);
  }

  Future<void> updateGame(GameItem updated) async {
    await _repository.upsertAll([updated]);
    if (!ref.mounted) return;

    var found = false;
    final nextGames = <GameItem>[];
    for (final g in _allGames) {
      if (g.id == updated.id) {
        nextGames.add(updated);
        found = true;
      } else {
        nextGames.add(g);
      }
    }
    if (!found) {
      nextGames.add(updated);
    }
    _allGames = nextGames;
    final categories = await _buildCategories(_allGames, state.settings);
    if (!ref.mounted) return;

    state = state.copyWith(
      categories: categories,
      focusedGameId: updated.id,
      clearError: true,
    );
  }

  Future<GameItem> downloadMetadataForGame(
    GameItem game,
    MetadataCandidate candidate, {
    bool applyText = true,
    bool downloadIcon = true,
    bool downloadLogo = true,
    bool downloadCover = true,
    bool downloadBanner = true,
    bool downloadBackground = true,
  }) async {
    final updated = await metadataService.downloadAndApply(
      game: game,
      candidate: candidate,
      steamGridDbApiKey: state.settings.steamGridDbApiKey,
      applyText: applyText,
      downloadIcon: downloadIcon,
      downloadLogo: downloadLogo,
      downloadCover: downloadCover,
      downloadBanner: downloadBanner,
      downloadBackground: downloadBackground,
    );
    await updateGame(updated);
    return updated;
  }

  Future<void> updateSettings(LauncherSettings newSettings) async {
    await _repository.saveSettings(newSettings);
    if (!ref.mounted) return;

    final theme = newSettings.activeThemeId != state.settings.activeThemeId
        ? await _loadThemeManifest(newSettings.activeThemeId)
        : state.theme;
    if (!ref.mounted) return;

    final categories = await _buildCategories(_allGames, newSettings);
    if (!ref.mounted) return;

    state = state.copyWith(
      settings: newSettings,
      theme: theme,
      categories: categories,
      focusedGameId: _firstGameId(categories, preferred: state.focusedGameId),
    );
  }

  static Future<List<GameCategory>> _buildCategories(
    List<GameItem> games,
    LauncherSettings settings,
  ) {
    final snapshot = List<GameItem>.unmodifiable(games);
    return Isolate.run(
      () => LibraryIndexer.build(snapshot, settings),
      debugName: 'LibraryIndexer.build',
    );
  }

  static String? _firstGameId(
    List<GameCategory> categories, {
    String? preferred,
  }) {
    if (preferred != null) {
      for (final c in categories) {
        if (c.games.any((g) => g.id == preferred)) return preferred;
      }
    }
    for (final c in categories) {
      if (c.games.isNotEmpty) return c.games.first.id;
    }
    return null;
  }
}
