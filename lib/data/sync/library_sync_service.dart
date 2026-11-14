import 'dart:isolate';

import '../../domain/models/game_item.dart';
import '../../domain/models/launch_config.dart';
import '../../domain/models/platform_models.dart';
import '../../domain/repositories/game_library_repository.dart';
import '../../domain/repositories/launcher_gateway.dart';
import '../../domain/services/library_merger.dart';

/// Reconciles installed packages with the persisted library and attaches
/// pre-rendered icon files.
class LibrarySyncService {
  LibrarySyncService(this._gateway, this._repository);

  /// Icons are rendered natively at this size (covers ~96dp @ xxhdpi).
  static const int iconSizePx = 192;

  final LauncherGateway _gateway;
  final GameLibraryRepository _repository;

  Future<List<GameItem>> syncInstalledApps({
    required bool autoImportGames,
  }) async {
    final installed = await _gateway.getInstalledApps(gamesOnly: false);
    final existing = await _repository.loadAll();
    final merge = await _merge(
      existing,
      installed,
      autoImportGames,
      DateTime.now(),
    );

    final upserts = {for (final g in merge.upserts) g.id: g};
    var library = merge.library;

    final packages = [
      for (final g in library)
        if (g.launch.type == LaunchType.package && g.launch.packageName != null)
          g.launch.packageName!,
    ];
    if (packages.isNotEmpty) {
      final icons = await _gateway.getAppIcons(packages, sizePx: iconSizePx);
      library = [
        for (final g in library)
          switch (icons[g.launch.packageName]) {
            final path?
                when (g.media.iconPath == null || g.media.iconPath!.isEmpty) &&
                    path != g.media.iconPath =>
              upserts[g.id] = g.copyWith(
                media: g.media.copyWith(iconPath: path),
              ),
            _ => g,
          },
      ];
    }

    await _repository.removeByIds(merge.removedIds);
    await _repository.upsertAll(upserts.values.toList());
    return library;
  }

  /// Adds any launchable app chosen by the user (kept even if not a "game").
  Future<GameItem> addManualApp(
    InstalledApp app, {
    GameKind kind = GameKind.androidNative,
  }) async {
    final icons = await _gateway.getAppIcons([
      app.packageName,
    ], sizePx: iconSizePx);
    final item = GameItem(
      id: GameItem.idForPackage(app.packageName),
      title: app.label,
      kind: kind,
      source: GameSource.manual,
      launch: LaunchConfig.package(app.packageName),
      media: MediaAssets(iconPath: icons[app.packageName]),
      addedAt: DateTime.now(),
    );
    await _repository.upsertAll([item]);
    return item;
  }

  static Future<MergeResult> _merge(
    List<GameItem> existing,
    List<InstalledApp> installed,
    bool autoImportGames,
    DateTime now,
  ) => Isolate.run(
    () => LibraryMerger.mergeInstalledApps(
      existing: existing,
      installed: installed,
      autoImportGames: autoImportGames,
      now: now,
    ),
    debugName: 'mergeInstalledApps',
  );
}
