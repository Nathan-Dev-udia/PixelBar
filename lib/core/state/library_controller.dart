import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/sqflite_game_library_repository.dart';
import '../../data/sync/library_sync_service.dart';
import '../../data/theme/theme_manifest_loader.dart';
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
      return await _themeLoader.loadAsset('assets/themes/$themeId/theme.json');
    } on Object {
      return ThemeManifest.fallback;
    }
  }

  Future<void> refreshInstalledApps() async {
    if (!ref.mounted || state.isSyncing) return;
    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final synced = await _syncService.syncInstalledApps(
        autoImportGames: state.settings.autoImportGames,
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
        errorMessage: 'Falha ao sincronizar aplicativos: $e',
      );
    }
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
