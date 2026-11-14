import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/theme_manifest.dart';
import '../../domain/repositories/launcher_gateway.dart';

/// Loads `theme.json` manifests. Reading is async I/O; JSON parsing and
/// validation always run in a background isolate.
class ThemeManifestLoader {
  ThemeManifestLoader({AssetBundle? bundle, LauncherGateway? gateway})
    : _bundle = bundle ?? rootBundle,
      _gateway = gateway;

  final AssetBundle _bundle;
  final LauncherGateway? _gateway;

  /// Built-in theme bundled under `assets/themes/<id>/theme.json`.
  Future<ThemeManifest> loadAsset(String assetPath) async {
    final raw = await _bundle.loadString(assetPath, cache: false);
    return parseInBackground(raw, basePath: p.dirname(assetPath));
  }

  /// User theme picked through SAF (document URI of the theme.json).
  Future<ThemeManifest> loadDocument(String documentUri) async {
    final gateway = _gateway;
    if (gateway == null) {
      throw StateError('No LauncherGateway configured for SAF themes.');
    }
    final raw = await gateway.readText(documentUri);
    return parseInBackground(raw);
  }

  static Future<ThemeManifest> parseInBackground(
    String raw, {
    String? basePath,
  }) => Isolate.run(
    () => ThemeManifest.parse(raw, basePath: basePath),
    debugName: 'parseThemeManifest',
  );
}
