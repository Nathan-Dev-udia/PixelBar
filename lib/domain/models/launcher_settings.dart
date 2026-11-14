import 'package:flutter/foundation.dart';

enum LibrarySortMode { alphabetical, recentlyPlayed, mostPlayed }

@immutable
class LauncherSettings {
  const LauncherSettings({
    this.activeThemeId = 'wireframe_debug',
    this.showHidden = false,
    this.autoImportGames = false,
    this.sfxEnabled = true,
    this.reduceMotion = false,
    this.sortMode = LibrarySortMode.alphabetical,
    this.steamGridDbApiKey = '',
    this.gamesFolderUri,
    this.gamesFolderName,
  });

  final String activeThemeId;
  final bool showHidden;

  /// Automatically add installed apps flagged as games (`CATEGORY_GAME`).
  /// Disabled by default so OndaDeck only shows games from the user's folder.
  final bool autoImportGames;
  final bool sfxEnabled;
  final bool reduceMotion;
  final LibrarySortMode sortMode;
  final String steamGridDbApiKey;
  final String? gamesFolderUri;
  final String? gamesFolderName;

  LauncherSettings copyWith({
    String? activeThemeId,
    bool? showHidden,
    bool? autoImportGames,
    bool? sfxEnabled,
    bool? reduceMotion,
    LibrarySortMode? sortMode,
    String? steamGridDbApiKey,
    String? gamesFolderUri,
    String? gamesFolderName,
    bool clearGamesFolder = false,
  }) => LauncherSettings(
    activeThemeId: activeThemeId ?? this.activeThemeId,
    showHidden: showHidden ?? this.showHidden,
    autoImportGames: autoImportGames ?? this.autoImportGames,
    sfxEnabled: sfxEnabled ?? this.sfxEnabled,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    sortMode: sortMode ?? this.sortMode,
    steamGridDbApiKey: steamGridDbApiKey ?? this.steamGridDbApiKey,
    gamesFolderUri: clearGamesFolder
        ? null
        : (gamesFolderUri ?? this.gamesFolderUri),
    gamesFolderName: clearGamesFolder
        ? null
        : (gamesFolderName ?? this.gamesFolderName),
  );

  factory LauncherSettings.fromJson(Map<String, Object?> json) =>
      LauncherSettings(
        activeThemeId: json['activeThemeId'] as String? ?? 'wireframe_debug',
        showHidden: json['showHidden'] as bool? ?? false,
        autoImportGames: json['autoImportGames'] as bool? ?? false,
        sfxEnabled: json['sfxEnabled'] as bool? ?? true,
        reduceMotion: json['reduceMotion'] as bool? ?? false,
        sortMode:
            LibrarySortMode.values.asNameMap()[json['sortMode']] ??
            LibrarySortMode.alphabetical,
        steamGridDbApiKey: json['steamGridDbApiKey'] as String? ?? '',
        gamesFolderUri: json['gamesFolderUri'] as String?,
        gamesFolderName: json['gamesFolderName'] as String?,
      );

  Map<String, Object?> toJson() => {
    'activeThemeId': activeThemeId,
    'showHidden': showHidden,
    'autoImportGames': autoImportGames,
    'sfxEnabled': sfxEnabled,
    'reduceMotion': reduceMotion,
    'sortMode': sortMode.name,
    if (steamGridDbApiKey.isNotEmpty) 'steamGridDbApiKey': steamGridDbApiKey,
    if (gamesFolderUri != null) 'gamesFolderUri': gamesFolderUri,
    if (gamesFolderName != null) 'gamesFolderName': gamesFolderName,
  };

  @override
  bool operator ==(Object other) =>
      other is LauncherSettings &&
      other.activeThemeId == activeThemeId &&
      other.showHidden == showHidden &&
      other.autoImportGames == autoImportGames &&
      other.sfxEnabled == sfxEnabled &&
      other.reduceMotion == reduceMotion &&
      other.sortMode == sortMode &&
      other.steamGridDbApiKey == steamGridDbApiKey &&
      other.gamesFolderUri == gamesFolderUri &&
      other.gamesFolderName == gamesFolderName;

  @override
  int get hashCode => Object.hash(
    activeThemeId,
    showHidden,
    autoImportGames,
    sfxEnabled,
    reduceMotion,
    sortMode,
    steamGridDbApiKey,
    gamesFolderUri,
    gamesFolderName,
  );
}
