import '../models/game_item.dart';
import '../models/launcher_settings.dart';
import '../models/library_state.dart';

/// Builds the category rows shown by themes. Pure & synchronous so it can run
/// inside `Isolate.run` (it sorts/group the whole library).
abstract final class LibraryIndexer {
  static const recentLimit = 12;

  static const platformTitles = {
    'n64': 'Nintendo 64',
    'gc': 'GameCube',
    'wii': 'Wii',
    'ps2': 'PlayStation 2',
    'psx': 'PlayStation',
    'snes': 'Super Nintendo',
    'nes': 'NES',
    'gba': 'Game Boy Advance',
    'gb': 'Game Boy',
    'genesis': 'Mega Drive',
  };

  static List<GameCategory> build(
    List<GameItem> games,
    LauncherSettings settings,
  ) {
    final visible = [
      for (final g in games)
        if (settings.showHidden || !g.hidden) g,
    ]..sort(_comparator(settings.sortMode));

    final byCustom = <String, List<GameItem>>{};
    final recomp = <GameItem>[];
    final byPlatform = <String, List<GameItem>>{};
    for (final g in visible) {
      if (g.categoryOverride case final custom?) {
        (byCustom[custom] ??= []).add(g);
        continue;
      }
      switch (g.kind) {
        case GameKind.recompPort:
          recomp.add(g);
        case GameKind.androidNative:
          break;
        case GameKind.emulated:
          (byPlatform[g.platform] ??= []).add(g);
      }
    }

    final platformKeys = byPlatform.keys.toList()..sort();
    final customKeys = byCustom.keys.toList()..sort();
    return [
      if (visible.isNotEmpty)
        GameCategory(
          id: 'games',
          title: 'Jogos',
          kind: CategoryKind.recomp,
          games: visible,
        ),
      if (visible.any((g) => g.favorite))
        GameCategory(
          id: 'favorites',
          title: 'Favoritos',
          kind: CategoryKind.favorites,
          games: [
            for (final g in visible)
              if (g.favorite) g,
          ],
        ),
      if (recomp.isNotEmpty)
        GameCategory(
          id: 'recomp',
          title: 'Ports (Recomp)',
          kind: CategoryKind.recomp,
          games: recomp,
        ),
      for (final p in platformKeys)
        GameCategory(
          id: 'platform:$p',
          title: platformTitles[p] ?? p.toUpperCase(),
          kind: CategoryKind.emulated,
          games: byPlatform[p]!,
        ),
      for (final c in customKeys)
        GameCategory(
          id: 'custom:$c',
          title: c,
          kind: CategoryKind.custom,
          games: byCustom[c]!,
        ),
    ];
  }

  static int Function(GameItem, GameItem) _comparator(LibrarySortMode mode) =>
      switch (mode) {
        LibrarySortMode.alphabetical => (a, b) => a.sortTitle.compareTo(
          b.sortTitle,
        ),
        LibrarySortMode.recentlyPlayed => (a, b) {
          final c = (b.lastPlayedAt?.millisecondsSinceEpoch ?? 0).compareTo(
            a.lastPlayedAt?.millisecondsSinceEpoch ?? 0,
          );
          return c != 0 ? c : a.sortTitle.compareTo(b.sortTitle);
        },
        LibrarySortMode.mostPlayed => (a, b) {
          final c = b.playCount.compareTo(a.playCount);
          return c != 0 ? c : a.sortTitle.compareTo(b.sortTitle);
        },
      };
}
