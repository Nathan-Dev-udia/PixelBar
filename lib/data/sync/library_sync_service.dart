import 'dart:isolate';

import '../../domain/models/game_item.dart';
import '../../domain/models/launch_config.dart';
import '../../domain/models/platform_models.dart';
import '../../domain/repositories/game_library_repository.dart';
import '../../domain/repositories/launcher_gateway.dart';
import '../../domain/services/library_merger.dart';

/// Reconciles the persisted library with either a user-selected SAF folder of
/// APKs/ROMs or (when explicitly opted in) installed game packages, and attaches
/// pre-rendered icon files.
class LibrarySyncService {
  LibrarySyncService(this._gateway, this._repository);

  /// Icons are rendered natively at this size (covers ~96dp @ xxhdpi).
  static const int iconSizePx = 192;

  /// Supported game file extensions when scanning a user-selected SAF folder.
  static const Set<String> supportedFolderExtensions = {
    'apk',
    'iso',
    'cso',
    'pbp',
    'chd',
    'rvz',
    'gcm',
    'ciso',
    'gcz',
    'wbfs',
    'z64',
    'n64',
    'v64',
    'nes',
    'sfc',
    'smc',
    'gb',
    'gbc',
    'gba',
    'md',
    'gen',
    'sms',
    'nds',
    'cue',
    'elf',
    'dol',
  };

  final LauncherGateway _gateway;
  final GameLibraryRepository _repository;

  Future<List<GameItem>> syncInstalledApps({
    required bool autoImportGames,
    String? gamesFolderUri,
  }) async {
    final installed = await _gateway.getInstalledApps(gamesOnly: false);
    final existing = await _repository.loadAll();

    if (gamesFolderUri != null && gamesFolderUri.isNotEmpty) {
      return _syncFromFolder(
        folderUri: gamesFolderUri,
        existing: existing,
        installed: installed,
      );
    }

    final merge = await _merge(
      existing,
      installed,
      autoImportGames,
      DateTime.now(),
    );

    final upserts = {for (final g in merge.upserts) g.id: g};
    var library = merge.library;
    final removedIds = [...merge.removedIds];

    if (!autoImportGames) {
      // Purge any previously auto-scanned phone packages when auto-import is off.
      final purged = <String>[];
      final kept = <GameItem>[];
      for (final g in library) {
        if (g.source == GameSource.scanned) {
          purged.add(g.id);
          upserts.remove(g.id);
        } else {
          kept.add(g);
        }
      }
      library = kept;
      removedIds.addAll(purged);
    }

    library = await _attachMissingAppIcons(library, upserts);

    await _repository.removeByIds(removedIds);
    await _repository.upsertAll(upserts.values.toList());
    return library;
  }

  Future<List<GameItem>> _syncFromFolder({
    required String folderUri,
    required List<GameItem> existing,
    required List<InstalledApp> installed,
  }) async {
    final entries = await _gateway.listDirectory(
      folderUri,
      recursive: true,
      extensions: supportedFolderExtensions,
    );
    final existingById = {for (final g in existing) g.id: g};
    final installedByPkg = {for (final a in installed) a.packageName: a};
    final installedByLowerPkg = {
      for (final a in installed) a.packageName.trim().toLowerCase(): a,
    };
    final installedByLowerLabel = {
      for (final a in installed) a.label.trim().toLowerCase(): a,
    };

    final now = DateTime.now();
    final nextById = <String, GameItem>{};
    final upserts = <String, GameItem>{};

    // Preserve explicit manual entries regardless of folder contents.
    for (final g in existing) {
      if (g.source == GameSource.manual) {
        nextById[g.id] = g;
      }
    }

    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final ext = entry.extension;
      final dot = entry.name.lastIndexOf('.');
      final stem = dot > 0 ? entry.name.substring(0, dot) : entry.name;

      final GameItem built;
      if (ext == 'apk') {
        final matched =
            (entry.apkPackageName != null
                ? installedByPkg[entry.apkPackageName!]
                : null) ??
            installedByLowerPkg[stem.trim().toLowerCase()] ??
            installedByLowerLabel[stem.trim().toLowerCase()] ??
            (entry.apkLabel != null
                ? installedByLowerLabel[entry.apkLabel!.trim().toLowerCase()]
                : null);
        final rawPkg = (entry.apkPackageName?.trim().isNotEmpty ?? false)
            ? entry.apkPackageName!.trim()
            : matched?.packageName;
        final pkg = (rawPkg != null && rawPkg.isNotEmpty) ? rawPkg : null;
        final id = pkg != null
            ? GameItem.idForPackage(pkg)
            : GameItem.idForDocument('apk', entry.uri);

        final isInstalled =
            pkg != null &&
            (installedByPkg.containsKey(pkg) || entry.apkInstalled);
        final launch = isInstalled
            ? LaunchConfig.package(pkg)
            : LaunchConfig.intent(
                action: LaunchConfig.actionView,
                dataUri: entry.uri,
                mimeType: 'application/vnd.android.package-archive',
                packageName: pkg,
              );
        final rawTitle = (entry.apkLabel?.trim().isNotEmpty ?? false)
            ? entry.apkLabel!.trim()
            : (matched?.label ?? stem);

        final prev = existingById[id];
        if (prev != null) {
          final mergedMedia =
              (prev.media.iconPath == null || prev.media.iconPath!.isEmpty) &&
                  (entry.apkIconPath?.isNotEmpty ?? false)
              ? prev.media.copyWith(iconPath: entry.apkIconPath)
              : prev.media;
          built = prev.copyWith(
            title: prev.titleCustomized ? prev.title : rawTitle,
            launch: launch,
            platform: 'android',
            media: mergedMedia,
          );
        } else {
          built = GameItem(
            id: id,
            title: rawTitle,
            kind: GameKind.androidNative,
            source: GameSource.scanned,
            platform: 'android',
            launch: launch,
            media: MediaAssets(iconPath: entry.apkIconPath),
            addedAt: now,
          );
        }
      } else {
        final platform = _platformForExtension(ext);
        final id = GameItem.idForDocument('folder', entry.uri);
        final launch = LaunchConfig.intent(
          action: LaunchConfig.actionView,
          dataUri: entry.uri,
        );
        final prev = existingById[id];
        if (prev != null) {
          built = prev.copyWith(
            title: prev.titleCustomized ? prev.title : stem,
            platform: platform,
            launch: launch,
          );
        } else {
          built = GameItem(
            id: id,
            title: stem,
            kind: GameKind.emulated,
            source: GameSource.scanned,
            platform: platform,
            launch: launch,
            addedAt: now,
          );
        }
      }

      // Do not overwrite manual items if same id exists, unless refreshing launch/icon.
      nextById[built.id] = built;
      if (existingById[built.id] != built) {
        upserts[built.id] = built;
      }
    }

    final removedIds = [
      for (final g in existing)
        if (g.source == GameSource.scanned && !nextById.containsKey(g.id)) g.id,
    ];

    final library = await _attachMissingAppIcons(
      nextById.values.toList(),
      upserts,
    );

    await _repository.removeByIds(removedIds);
    await _repository.upsertAll(upserts.values.toList());
    return library;
  }

  Future<List<GameItem>> _attachMissingAppIcons(
    List<GameItem> library,
    Map<String, GameItem> upserts,
  ) async {
    final packages = [
      for (final g in library)
        if (g.launch.type == LaunchType.package &&
            g.launch.packageName != null &&
            (g.media.iconPath == null || g.media.iconPath!.isEmpty))
          g.launch.packageName!,
    ];
    if (packages.isEmpty) return library;

    final icons = await _gateway.getAppIcons(packages, sizePx: iconSizePx);
    return [
      for (final g in library)
        switch (icons[g.launch.packageName]) {
          final path?
              when (g.media.iconPath == null || g.media.iconPath!.isEmpty) &&
                  path.isNotEmpty &&
                  path != g.media.iconPath =>
            upserts[g.id] = g.copyWith(media: g.media.copyWith(iconPath: path)),
          _ => g,
        },
    ];
  }

  static String _platformForExtension(String ext) => switch (ext) {
    'iso' || 'cso' || 'pbp' => 'psp',
    'rvz' || 'gcm' || 'ciso' || 'gcz' || 'wbfs' || 'dol' || 'elf' => 'gc',
    'chd' => 'ps2',
    'cue' => 'psx',
    'z64' || 'n64' || 'v64' => 'n64',
    'gba' => 'gba',
    'gb' || 'gbc' => 'gb',
    'sfc' || 'smc' => 'snes',
    'nes' => 'nes',
    'md' || 'gen' || 'sms' => 'genesis',
    'nds' => 'nds',
    _ => ext.isEmpty ? 'rom' : ext,
  };

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
