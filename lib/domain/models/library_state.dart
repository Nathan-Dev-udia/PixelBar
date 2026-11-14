import 'package:flutter/foundation.dart';

import 'game_item.dart';
import 'launcher_settings.dart';
import 'theme_manifest.dart';

enum CategoryKind { recent, favorites, recomp, android, emulated, custom }

@immutable
class GameCategory {
  GameCategory({
    required this.id,
    required this.title,
    required this.kind,
    required List<GameItem> games,
  }) : games = List.unmodifiable(games);

  final String id;
  final String title;
  final CategoryKind kind;
  final List<GameItem> games;

  @override
  bool operator ==(Object other) =>
      other is GameCategory &&
      other.id == id &&
      other.title == title &&
      other.kind == kind &&
      listEquals(other.games, games);

  @override
  int get hashCode => Object.hash(id, title, kind, Object.hashAll(games));
}

enum LibraryStatus { loading, ready, error }

/// The single immutable snapshot every theme renders. Themes never reach into
/// repositories/platform: everything they may show lives here.
@immutable
class LibraryState {
  LibraryState({
    required this.status,
    required List<GameCategory> categories,
    required this.theme,
    required this.settings,
    this.focusedGameId,
    this.isLaunching = false,
    this.isSyncing = false,
    this.errorMessage,
    this.lastSyncAt,
  }) : categories = List.unmodifiable(categories);

  factory LibraryState.initial() => LibraryState(
    status: LibraryStatus.loading,
    categories: const [],
    theme: ThemeManifest.fallback,
    settings: const LauncherSettings(),
  );

  final LibraryStatus status;
  final List<GameCategory> categories;
  final ThemeManifest theme;
  final LauncherSettings settings;

  /// Game that should receive focus when a theme (re)mounts — e.g. after
  /// returning from a launched game.
  final String? focusedGameId;
  final bool isLaunching;
  final bool isSyncing;
  final String? errorMessage;
  final DateTime? lastSyncAt;

  AudioTheme get audio => theme.audio;

  int get totalGames =>
      {for (final c in categories) ...c.games.map((g) => g.id)}.length;

  GameItem? findGame(String id) {
    for (final c in categories) {
      for (final g in c.games) {
        if (g.id == id) return g;
      }
    }
    return null;
  }

  LibraryState copyWith({
    LibraryStatus? status,
    List<GameCategory>? categories,
    ThemeManifest? theme,
    LauncherSettings? settings,
    String? focusedGameId,
    bool? isLaunching,
    bool? isSyncing,
    String? errorMessage,
    bool clearError = false,
    DateTime? lastSyncAt,
  }) => LibraryState(
    status: status ?? this.status,
    categories: categories ?? this.categories,
    theme: theme ?? this.theme,
    settings: settings ?? this.settings,
    focusedGameId: focusedGameId ?? this.focusedGameId,
    isLaunching: isLaunching ?? this.isLaunching,
    isSyncing: isSyncing ?? this.isSyncing,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
  );

  @override
  bool operator ==(Object other) =>
      other is LibraryState &&
      other.status == status &&
      listEquals(other.categories, categories) &&
      other.theme == theme &&
      other.settings == settings &&
      other.focusedGameId == focusedGameId &&
      other.isLaunching == isLaunching &&
      other.isSyncing == isSyncing &&
      other.errorMessage == errorMessage &&
      other.lastSyncAt == lastSyncAt;

  @override
  int get hashCode => Object.hash(
    status,
    Object.hashAll(categories),
    theme,
    settings,
    focusedGameId, //
    isLaunching,
    isSyncing,
    errorMessage,
    lastSyncAt,
  );
}
