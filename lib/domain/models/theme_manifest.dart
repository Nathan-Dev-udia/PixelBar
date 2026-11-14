import 'dart:convert';

import 'package:flutter/foundation.dart';

class ThemeManifestException implements Exception {
  const ThemeManifestException(this.message);
  final String message;
  @override
  String toString() => 'ThemeManifestException: $message';
}

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
    final spec = BackgroundSpec(
      kind: kind,
      color: json['color'] == null ? 0xFF000000 : parseColor(json['color']),
      imagePath: _resolvePath(json['image'] as String?, basePath),
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

  factory AudioTheme.fromJson(Map<String, Object?> json, {String? basePath}) =>
      AudioTheme(
        enabled: json['enabled'] as bool? ?? false,
        volume: ((json['volume'] as num?) ?? 0.6).toDouble().clamp(0.0, 1.0),
        backgroundMusic: _resolvePath(json['bgm'] as String?, basePath),
        navigateSfx: _resolvePath(json['navigate'] as String?, basePath),
        selectSfx: _resolvePath(json['select'] as String?, basePath),
        backSfx: _resolvePath(json['back'] as String?, basePath),
        launchSfx: _resolvePath(json['launch'] as String?, basePath),
      );

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

/// Declarative description of a theme (`theme.json`).
///
/// [engine] selects which registered Dart renderer draws it (`wireframe_debug`,
/// `xmb`, `ps5`, …). A JSON-only custom theme reuses an engine and only swaps
/// colours, background, audio and [options].
@immutable
class ThemeManifest {
  const ThemeManifest({
    required this.id,
    required this.name,
    required this.engine,
    this.schemaVersion = currentSchemaVersion,
    this.author = 'Unknown',
    this.version = '0.0.0',
    this.colors = const {},
    this.background = const BackgroundSpec(),
    this.audio = AudioTheme.silent,
    this.options = const {},
    this.basePath,
  });

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
  final String engine;

  /// Named ARGB colours (`background`, `foreground`, `accent`, …).
  final Map<String, int> colors;
  final BackgroundSpec background;
  final AudioTheme audio;

  /// Free-form, engine-specific layout knobs (tile sizes, wave speed, …).
  final Map<String, Object?> options;

  /// Directory the manifest was loaded from; relative asset paths resolve here.
  final String? basePath;

  int color(String key, int fallback) => colors[key] ?? fallback;

  T option<T>(String key, T fallback) {
    final v = options[key];
    if (v is T) return v;
    if (fallback is double && v is num) return v.toDouble() as T;
    return fallback;
  }

  /// Pure & synchronous: call it inside `Isolate.run`.
  static ThemeManifest parse(String source, {String? basePath}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw ThemeManifestException('Invalid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const ThemeManifestException('Root must be a JSON object.');
    }
    return ThemeManifest.fromJson(decoded, basePath: basePath);
  }

  factory ThemeManifest.fromJson(
    Map<String, Object?> json, {
    String? basePath,
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
      return v;
    }

    return ThemeManifest(
      schemaVersion: schema,
      id: required('id'),
      name: required('name'),
      engine: required('engine'),
      author: json['author'] as String? ?? 'Unknown',
      version: json['version'] as String? ?? '0.0.0',
      colors: Map.unmodifiable({
        for (final e in ((json['colors'] as Map?) ?? const {}).entries)
          '${e.key}': parseColor(e.value),
      }),
      background: json['background'] == null
          ? const BackgroundSpec()
          : BackgroundSpec.fromJson(
              (json['background'] as Map).cast<String, Object?>(),
              basePath: basePath,
            ),
      audio: json['audio'] == null
          ? AudioTheme.silent
          : AudioTheme.fromJson(
              (json['audio'] as Map).cast<String, Object?>(),
              basePath: basePath,
            ),
      options: Map.unmodifiable(
        (json['options'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      basePath: basePath,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeManifest &&
      other.schemaVersion == schemaVersion &&
      other.id == id &&
      other.name == name &&
      other.author == author &&
      other.version == version &&
      other.engine == engine &&
      mapEquals(other.colors, colors) &&
      other.background == background &&
      other.audio == audio &&
      mapEquals(other.options, options) &&
      other.basePath == basePath;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    id,
    name,
    author,
    version,
    engine,
    background,
    audio,
    basePath,
  );
}

/// Parses `#RRGGBB`, `#AARRGGBB` or an int into ARGB.
int parseColor(Object? raw) {
  if (raw is int) return raw;
  if (raw is String) {
    final hex = raw.startsWith('#') ? raw.substring(1) : raw;
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
