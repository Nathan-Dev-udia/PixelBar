import 'package:flutter/foundation.dart';

import 'launch_config.dart';

/// Local, already pre-processed (downsampled) media files for a game.
///
/// All paths point to app-private files produced by the native bridge
/// (`getAppIcons`, `importArtwork`), never to raw SAF URIs: themes must be able
/// to decode them cheaply with `cacheWidth`/`cacheHeight`.
@immutable
class MediaAssets {
  const MediaAssets({
    this.iconPath,
    this.coverPath,
    this.bannerPath,
    this.backgroundPath,
    this.logoPath,
    this.videoPath,
  });

  static const empty = MediaAssets();

  final String? iconPath;
  final String? coverPath;
  final String? bannerPath;
  final String? backgroundPath;
  final String? logoPath;
  final String? videoPath;

  MediaAssets copyWith({
    String? iconPath,
    String? coverPath,
    String? bannerPath,
    String? backgroundPath,
    String? logoPath,
    String? videoPath,
  }) => MediaAssets(
    iconPath: iconPath ?? this.iconPath,
    coverPath: coverPath ?? this.coverPath,
    bannerPath: bannerPath ?? this.bannerPath,
    backgroundPath: backgroundPath ?? this.backgroundPath,
    logoPath: logoPath ?? this.logoPath,
    videoPath: videoPath ?? this.videoPath,
  );

  factory MediaAssets.fromJson(Map<String, Object?> json) => MediaAssets(
    iconPath: json['icon'] as String?,
    coverPath: json['cover'] as String?,
    bannerPath: json['banner'] as String?,
    backgroundPath: json['background'] as String?,
    logoPath: json['logo'] as String?,
    videoPath: json['video'] as String?,
  );

  Map<String, Object?> toJson() => {
    if (iconPath != null) 'icon': iconPath,
    if (coverPath != null) 'cover': coverPath,
    if (bannerPath != null) 'banner': bannerPath,
    if (backgroundPath != null) 'background': backgroundPath,
    if (logoPath != null) 'logo': logoPath,
    if (videoPath != null) 'video': videoPath,
  };

  @override
  bool operator ==(Object other) =>
      other is MediaAssets &&
      other.iconPath == iconPath &&
      other.coverPath == coverPath &&
      other.bannerPath == bannerPath &&
      other.backgroundPath == backgroundPath &&
      other.logoPath == logoPath &&
      other.videoPath == videoPath;

  @override
  int get hashCode => Object.hash(
    iconPath,
    coverPath,
    bannerPath,
    backgroundPath,
    logoPath,
    videoPath,
  );
}

enum GameKind {
  /// Regular Android game installed from a store / APK.
  androidNative,

  /// Static recompilation port shipped as its own APK (e.g. SM64/Zelda recomp).
  recompPort,

  /// ROM opened through an external emulator.
  emulated,
}

enum GameSource {
  /// Discovered automatically by scanning installed packages / folders.
  scanned,

  /// Added explicitly by the user — never removed automatically.
  manual,
}

@immutable
class GameItem {
  const GameItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.source,
    required this.launch,
    required this.addedAt,
    this.platform = 'android',
    this.media = MediaAssets.empty,
    this.categoryOverride,
    this.favorite = false,
    this.hidden = false,
    this.playCount = 0,
    this.lastPlayedAt,
  });

  /// Stable id for an installed APK.
  static String idForPackage(String packageName) => 'pkg:$packageName';

  /// Stable id for a ROM/document opened via an emulator profile.
  static String idForDocument(String profileId, String documentUri) =>
      'doc:$profileId:$documentUri';

  final String id;
  final String title;
  final GameKind kind;
  final GameSource source;
  final LaunchConfig launch;
  final DateTime addedAt;

  /// Platform key (`android`, `n64`, `gc`, `ps2`, …) used for grouping.
  final String platform;
  final MediaAssets media;

  /// User-chosen category id; overrides automatic categorisation.
  final String? categoryOverride;
  final bool favorite;
  final bool hidden;
  final int playCount;
  final DateTime? lastPlayedAt;

  String get sortTitle {
    final t = title.trim().toLowerCase();
    return t.startsWith('the ') ? t.substring(4) : t;
  }

  GameItem copyWith({
    String? title,
    GameKind? kind,
    GameSource? source,
    LaunchConfig? launch,
    String? platform,
    MediaAssets? media,
    String? categoryOverride,
    bool clearCategoryOverride = false,
    bool? favorite,
    bool? hidden,
    int? playCount,
    DateTime? lastPlayedAt,
  }) => GameItem(
    id: id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    source: source ?? this.source,
    launch: launch ?? this.launch,
    addedAt: addedAt,
    platform: platform ?? this.platform,
    media: media ?? this.media,
    categoryOverride: clearCategoryOverride
        ? null
        : (categoryOverride ?? this.categoryOverride),
    favorite: favorite ?? this.favorite,
    hidden: hidden ?? this.hidden,
    playCount: playCount ?? this.playCount,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is GameItem &&
      other.id == id &&
      other.title == title &&
      other.kind == kind &&
      other.source == source &&
      other.launch == launch &&
      other.addedAt == addedAt &&
      other.platform == platform &&
      other.media == media &&
      other.categoryOverride == categoryOverride &&
      other.favorite == favorite &&
      other.hidden == hidden &&
      other.playCount == playCount &&
      other.lastPlayedAt == lastPlayedAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    kind,
    source,
    launch,
    addedAt,
    platform,
    media, //
    categoryOverride,
    favorite,
    hidden,
    playCount,
    lastPlayedAt,
  );

  @override
  String toString() => 'GameItem($id, "$title", ${kind.name})';
}
