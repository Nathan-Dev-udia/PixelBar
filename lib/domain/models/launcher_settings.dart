import 'package:flutter/foundation.dart';

enum LibrarySortMode { alphabetical, recentlyPlayed, mostPlayed }

@immutable
class LauncherSettings {
  const LauncherSettings({
    this.activeThemeId = 'wireframe_debug',
    this.showHidden = false,
    this.autoImportGames = true,
    this.sfxEnabled = true,
    this.reduceMotion = false,
    this.sortMode = LibrarySortMode.alphabetical,
  });

  final String activeThemeId;
  final bool showHidden;

  /// Automatically add installed apps flagged as games (`CATEGORY_GAME`).
  final bool autoImportGames;
  final bool sfxEnabled;
  final bool reduceMotion;
  final LibrarySortMode sortMode;

  LauncherSettings copyWith({
    String? activeThemeId,
    bool? showHidden,
    bool? autoImportGames,
    bool? sfxEnabled,
    bool? reduceMotion,
    LibrarySortMode? sortMode,
  }) => LauncherSettings(
    activeThemeId: activeThemeId ?? this.activeThemeId,
    showHidden: showHidden ?? this.showHidden,
    autoImportGames: autoImportGames ?? this.autoImportGames,
    sfxEnabled: sfxEnabled ?? this.sfxEnabled,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    sortMode: sortMode ?? this.sortMode,
  );

  factory LauncherSettings.fromJson(Map<String, Object?> json) =>
      LauncherSettings(
        activeThemeId: json['activeThemeId'] as String? ?? 'wireframe_debug',
        showHidden: json['showHidden'] as bool? ?? false,
        autoImportGames: json['autoImportGames'] as bool? ?? true,
        sfxEnabled: json['sfxEnabled'] as bool? ?? true,
        reduceMotion: json['reduceMotion'] as bool? ?? false,
        sortMode:
            LibrarySortMode.values.asNameMap()[json['sortMode']] ??
            LibrarySortMode.alphabetical,
      );

  Map<String, Object?> toJson() => {
    'activeThemeId': activeThemeId,
    'showHidden': showHidden,
    'autoImportGames': autoImportGames,
    'sfxEnabled': sfxEnabled,
    'reduceMotion': reduceMotion,
    'sortMode': sortMode.name,
  };

  @override
  bool operator ==(Object other) =>
      other is LauncherSettings &&
      other.activeThemeId == activeThemeId &&
      other.showHidden == showHidden &&
      other.autoImportGames == autoImportGames &&
      other.sfxEnabled == sfxEnabled &&
      other.reduceMotion == reduceMotion &&
      other.sortMode == sortMode;

  @override
  int get hashCode => Object.hash(
    activeThemeId,
    showHidden,
    autoImportGames,
    sfxEnabled,
    reduceMotion,
    sortMode,
  );
}
