import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'theme_layout.dart';

export 'theme_layout.dart'
    show
        ThemeLayoutNode,
        ThemeManifestException,
        ThemeNodeType,
        validateSafeRelativeAssetPath;

enum BackgroundKind { solid, image, shader }

/// Background description. `shader` backgrounds reference a GLSL fragment
/// program declared in pubspec (`shaders:`); `image` backgrounds must be
/// pre-blurred/pre-processed files — live `BackdropFilter` is forbidden.
@immutable
class BackgroundSpec {
  const BackgroundSpec({
    this.kind = BackgroundKind.solid,
    this.color = 0xFF000000,
    this.imagePath,
    this.shaderAsset,
    this.uniforms = const {},
  });

  final BackgroundKind kind;
  final int color;
  final String? imagePath;
  final String? shaderAsset;
  final Map<String, double> uniforms;

  factory BackgroundSpec.fromJson(
    Map<String, Object?> json, {
    String? basePath,
  }) {
    final kind = BackgroundKind.values.asNameMap()[json['type'] ?? 'solid'];
    if (kind == null) {
      throw ThemeManifestException('Unknown background type: ${json['type']}');
    }
    final rawImage = json['image'] as String?;
    if (rawImage != null) {
      validateSafeRelativeAssetPath(rawImage, context: 'background.image');
    }
    final spec = BackgroundSpec(
      kind: kind,
      color: json['color'] == null ? 0xFF000000 : parseColor(json['color']),
      imagePath: _resolvePath(rawImage, basePath),
      shaderAsset: json['shader'] as String?,
      uniforms: {
        for (final e in ((json['uniforms'] as Map?) ?? const {}).entries)
          '${e.key}': (e.value as num).toDouble(),
      },
    );
    if (kind == BackgroundKind.image && spec.imagePath == null) {
      throw const ThemeManifestException(
        'Background "image" requires "image".',
      );
    }
    if (kind == BackgroundKind.shader && spec.shaderAsset == null) {
      throw const ThemeManifestException(
        'Background "shader" requires "shader".',
      );
    }
    return spec;
  }

  @override
  bool operator ==(Object other) =>
      other is BackgroundSpec &&
      other.kind == kind &&
      other.color == color &&
      other.imagePath == imagePath &&
      other.shaderAsset == shaderAsset &&
      mapEquals(other.uniforms, uniforms);

  @override
  int get hashCode => Object.hash(
    kind,
    color,
    imagePath,
    shaderAsset,
    Object.hashAllUnordered(
      uniforms.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// Sound set of a theme. Paths are local files/assets; playback is owned by an
/// audio service that registers as a hibernation participant.
@immutable
class AudioTheme {
  const AudioTheme({
    this.enabled = false,
    this.volume = 0.6,
    this.backgroundMusic,
    this.navigateSfx,
    this.selectSfx,
    this.backSfx,
    this.launchSfx,
  });

  static const silent = AudioTheme();

  final bool enabled;
  final double volume;
  final String? backgroundMusic;
  final String? navigateSfx;
  final String? selectSfx;
  final String? backSfx;
  final String? launchSfx;

  List<String> get relativeOrResolvedPaths => [
    ?backgroundMusic,
    ?navigateSfx,
    ?selectSfx,
    ?backSfx,
    ?launchSfx,
  ];

  factory AudioTheme.fromJson(Map<String, Object?> json, {String? basePath}) {
    String? readPath(List<String> keys) {
      for (final key in keys) {
        final v = json[key];
        if (v is String && v.isNotEmpty) {
          validateSafeRelativeAssetPath(v, context: 'sounds.$key');
          return _resolvePath(v, basePath);
        }
      }
      return null;
    }

    final bgm = readPath(['bgm']);
    final move = readPath(['navigate', 'move']);
    final select = readPath(['select']);
    final back = readPath(['back']);
    final launch = readPath(['launch']);
    final hasAny =
        bgm != null ||
        move != null ||
        select != null ||
        back != null ||
        launch != null;

    return AudioTheme(
      enabled: json['enabled'] as bool? ?? hasAny,
      volume: ((json['volume'] as num?) ?? 0.6).toDouble().clamp(0.0, 1.0),
      backgroundMusic: bgm,
      navigateSfx: move,
      selectSfx: select,
      backSfx: back,
      launchSfx: launch,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AudioTheme &&
      other.enabled == enabled &&
      other.volume == volume &&
      other.backgroundMusic == backgroundMusic &&
      other.navigateSfx == navigateSfx &&
      other.selectSfx == selectSfx &&
      other.backSfx == backSfx &&
      other.launchSfx == launchSfx;

  @override
  int get hashCode => Object.hash(
    enabled,
    volume,
    backgroundMusic,
    navigateSfx,
    selectSfx,
    backSfx,
    launchSfx,
  );
}

/// Declarative description of a theme (`manifest.json` or legacy `theme.json`).
///
/// [engine] defaults to `'data_driven'` (`DataDrivenThemeEngine`), or may select
/// a registered custom engine (`wireframe_debug`, etc.).
@immutable
class ThemeManifest {
  const ThemeManifest({
    required this.id,
    required this.name,
    this.engine = 'data_driven',
    this.schemaVersion = currentSchemaVersion,
    this.author = 'Unknown',
    this.version = '0.0.0',
    this.description = '',
    this.previewImage,
    this.colors = const {},
    Map<String, int>? defaultColors,
    this.background = const BackgroundSpec(),
    this.audio = AudioTheme.silent,
    this.options = const {},
    this.fonts = const {},
    this.layout,
    this.isBuiltIn = true,
    this.basePath,
  }) : _defaultColors = defaultColors;

  static const currentSchemaVersion = 1;

  /// Used before any manifest is loaded and as a last-resort fallback.
  static const fallback = ThemeManifest(
    id: 'fallback',
    name: 'Fallback',
    engine: 'wireframe_debug',
  );

  final int schemaVersion;
  final String id;
  final String name;
  final String author;
  final String version;
  final String description;
  final String? previewImage;
  final String engine;

  /// Active ARGB colours (`primary`, `accent`, `background`, `textPrimary`, …).
  final Map<String, int> colors;
  final Map<String, int>? _defaultColors;
  final BackgroundSpec background;
  final AudioTheme audio;

  /// Free-form, engine-specific layout knobs.
  final Map<String, Object?> options;

  /// Font family name -> resolved `.ttf` path inside the theme package.
  final Map<String, String> fonts;

  /// Declarative widget tree loaded from `layout.json`.
  final ThemeLayoutNode? layout;

  final bool isBuiltIn;

  /// Directory or asset prefix the manifest was loaded from.
  final String? basePath;

  Map<String, int> get defaultColors => _defaultColors ?? colors;

  bool get hasColorOverrides => !mapEquals(colors, defaultColors);

  int color(String key, int fallback) => colors[key] ?? fallback;

  T option<T>(String key, T fallback) {
    final v = options[key];
    if (v is T) return v;
    if (fallback is double && v is num) return v.toDouble() as T;
    return fallback;
  }

  ThemeManifest copyWith({
    Map<String, int>? colors,
    Map<String, int>? defaultColors,
    Map<String, String>? fonts,
    ThemeLayoutNode? layout,
    bool? isBuiltIn,
    String? basePath,
    String? previewImage,
  }) => ThemeManifest(
    schemaVersion: schemaVersion,
    id: id,
    name: name,
    author: author,
    version: version,
    description: description,
    previewImage: previewImage ?? this.previewImage,
    engine: engine,
    colors: Map.unmodifiable(colors ?? this.colors),
    defaultColors: Map.unmodifiable(defaultColors ?? this.defaultColors),
    background: background,
    audio: audio,
    options: options,
    fonts: Map.unmodifiable(fonts ?? this.fonts),
    layout: layout ?? this.layout,
    isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    basePath: basePath ?? this.basePath,
  );

  /// Returns a copy with user color customizations overlaid onto [defaultColors].
  ThemeManifest applyColorOverrides(Map<String, int> overrides) {
    if (overrides.isEmpty) {
      return copyWith(colors: defaultColors);
    }
    final merged = Map<String, int>.of(defaultColors);
    for (final entry in overrides.entries) {
      if (merged.containsKey(entry.key)) {
        merged[entry.key] = entry.value;
      }
    }
    return copyWith(colors: merged);
  }

  /// Pure & synchronous: call it inside `Isolate.run`.
  static ThemeManifest parse(
    String source, {
    String? basePath,
    bool isBuiltIn = true,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw ThemeManifestException('Invalid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const ThemeManifestException('Root must be a JSON object.');
    }
    return ThemeManifest.fromJson(
      decoded,
      basePath: basePath,
      isBuiltIn: isBuiltIn,
    );
  }

  factory ThemeManifest.fromJson(
    Map<String, Object?> json, {
    String? basePath,
    bool isBuiltIn = true,
  }) {
    final schema = json['schemaVersion'] as int? ?? 1;
    if (schema > currentSchemaVersion) {
      throw ThemeManifestException(
        'Unsupported schemaVersion $schema (max $currentSchemaVersion).',
      );
    }
    String required(String key) {
      final v = json[key];
      if (v is! String || v.trim().isEmpty) {
        throw ThemeManifestException('Missing required "$key".');
      }
      return v.trim();
    }

    final rawPreview = json['previewImage'] as String?;
    if (rawPreview != null && rawPreview.isNotEmpty) {
      validateSafeRelativeAssetPath(rawPreview, context: 'previewImage');
    }

    final parsedColors = Map<String, int>.unmodifiable({
      for (final e in ((json['colors'] as Map?) ?? const {}).entries)
        '${e.key}': parseColor(e.value),
    });

    final rawAudio = json['sounds'] ?? json['audio'];
    final parsedFonts = <String, String>{};
    if (json['fonts'] case final Map rawFonts) {
      for (final e in rawFonts.entries) {
        final path = e.value;
        if (path is String && path.isNotEmpty) {
          validateSafeRelativeAssetPath(path, context: 'fonts.${e.key}');
          parsedFonts['${e.key}'] = _resolvePath(path, basePath) ?? path;
        }
      }
    }

    final rawEngine = (json['engine'] as String?)?.trim();
    final engine = (rawEngine != null && rawEngine.isNotEmpty)
        ? rawEngine
        : 'data_driven';

    return ThemeManifest(
      schemaVersion: schema,
      id: required('id'),
      name: required('name'),
      engine: engine,
      author: (json['author'] as String?)?.trim().isNotEmpty == true
          ? (json['author']! as String).trim()
          : 'Unknown',
      version: (json['version'] as String?)?.trim().isNotEmpty == true
          ? (json['version']! as String).trim()
          : '0.0.0',
      description: json['description'] as String? ?? '',
      previewImage: rawPreview == null || rawPreview.isEmpty
          ? null
          : _resolvePath(rawPreview, basePath),
      colors: parsedColors,
      defaultColors: parsedColors,
      background: json['background'] == null
          ? const BackgroundSpec()
          : BackgroundSpec.fromJson(
              (json['background'] as Map).cast<String, Object?>(),
              basePath: basePath,
            ),
      audio: rawAudio == null
          ? AudioTheme.silent
          : AudioTheme.fromJson(
              (rawAudio as Map).cast<String, Object?>(),
              basePath: basePath,
            ),
      options: Map.unmodifiable(
        (json['options'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      fonts: Map.unmodifiable(parsedFonts),
      isBuiltIn: isBuiltIn,
      basePath: basePath,
    );
  }

  static String formatColorHex(int argb, {bool includeAlpha = false}) {
    final alpha = (argb >> 24) & 0xFF;
    if (includeAlpha || alpha != 0xFF) {
      return '#${argb.toUnsigned(32).toRadixString(16).padLeft(8, '0').toUpperCase()}';
    }
    final rgb = argb & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeManifest &&
      other.schemaVersion == schemaVersion &&
      other.id == id &&
      other.name == name &&
      other.author == author &&
      other.version == version &&
      other.description == description &&
      other.previewImage == previewImage &&
      other.engine == engine &&
      mapEquals(other.colors, colors) &&
      mapEquals(other.defaultColors, defaultColors) &&
      other.background == background &&
      other.audio == audio &&
      mapEquals(other.options, options) &&
      mapEquals(other.fonts, fonts) &&
      other.layout == layout &&
      other.isBuiltIn == isBuiltIn &&
      other.basePath == basePath;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    id,
    name,
    author,
    version,
    description,
    previewImage,
    engine,
    background,
    audio,
    layout,
    isBuiltIn,
    basePath,
  );
}

/// Parses `#RRGGBB`, `#AARRGGBB` or an int into ARGB.
int parseColor(Object? raw) {
  if (raw is int) return raw;
  if (raw is String) {
    final hex = raw.trim().startsWith('#')
        ? raw.trim().substring(1)
        : raw.trim();
    final value = int.tryParse(hex, radix: 16);
    if (value != null && hex.length == 6) return 0xFF000000 | value;
    if (value != null && hex.length == 8) return value;
  }
  throw ThemeManifestException('Invalid color: $raw');
}

String? _resolvePath(String? path, String? basePath) {
  if (path == null ||
      basePath == null ||
      path.startsWith('/') ||
      path.contains('://')) {
    return path;
  }
  return '$basePath/$path';
}
