import 'package:flutter/foundation.dart';

import '../models/game_item.dart';
import '../models/launch_config.dart';
import '../models/platform_models.dart';

@immutable
class MergeResult {
  const MergeResult({
    required this.library,
    required this.upserts,
    required this.removedIds,
  });

  /// Full library after the merge.
  final List<GameItem> library;

  /// Items that must be written to the DB.
  final List<GameItem> upserts;

  /// Ids that must be deleted from the DB.
  final List<String> removedIds;
}

/// Reconciles the persisted library with the packages currently installed.
/// Pure & synchronous (runs inside `Isolate.run`).
///
/// Rules:
/// - scanned APK entries whose package disappeared are removed;
/// - manual entries are never removed automatically;
/// - new apps flagged as games are imported when [autoImportGames] is on;
/// - labels of scanned entries follow the installed app label.
abstract final class LibraryMerger {
  static MergeResult mergeInstalledApps({
    required List<GameItem> existing,
    required List<InstalledApp> installed,
    required bool autoImportGames,
    required DateTime now,
  }) {
    final installedByPkg = {for (final a in installed) a.packageName: a};
    final knownPackages = <String>{};
    final library = <GameItem>[];
    final upserts = <GameItem>[];
    final removed = <String>[];

    for (final g in existing) {
      final pkg = g.launch.type == LaunchType.package
          ? g.launch.packageName
          : null;
      if (pkg == null) {
        library.add(g);
        continue;
      }
      knownPackages.add(pkg);
      final app = installedByPkg[pkg];
      if (app == null) {
        if (g.source == GameSource.scanned) {
          removed.add(g.id);
        } else {
          library.add(g);
        }
        continue;
      }
      if (g.source == GameSource.scanned &&
          !g.titleCustomized &&
          g.title != app.label) {
        final updated = g.copyWith(title: app.label);
        library.add(updated);
        upserts.add(updated);
      } else {
        library.add(g);
      }
    }

    if (autoImportGames) {
      for (final app in installed) {
        if (!app.isGame || knownPackages.contains(app.packageName)) continue;
        final item = GameItem(
          id: GameItem.idForPackage(app.packageName),
          title: app.label,
          kind: GameKind.androidNative,
          source: GameSource.scanned,
          launch: LaunchConfig.package(app.packageName),
          addedAt: now,
        );
        library.add(item);
        upserts.add(item);
      }
    }

    return MergeResult(library: library, upserts: upserts, removedIds: removed);
  }
}
