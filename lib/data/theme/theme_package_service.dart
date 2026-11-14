import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/theme_manifest.dart';
import 'zip_archive_extractor.dart';

/// Manages built-in and community-imported theme packages (`.zip`/`.ondatheme`),
/// user color overrides (`user_overrides.json`), and dynamic `.ttf` font loading.
class ThemePackageService {
  ThemePackageService({
    AssetBundle? bundle,
    Future<String> Function()? themesDirProvider,
  }) : _bundle = bundle ?? rootBundle,
       _themesDirProvider = themesDirProvider ?? _defaultThemesDir;

  static const String builtInDefaultId = 'wireframe_debug';
  static const String builtInPspXmbId = 'psp_xmb';
  static const List<String> builtInThemeIds = [
    builtInDefaultId,
    builtInPspXmbId,
  ];
  static const String overridesFileName = 'user_overrides.json';
  static final RegExp _safeThemeId = RegExp(r'^[a-zA-Z0-9_-]+$');

  final AssetBundle _bundle;
  final Future<String> Function() _themesDirProvider;
  final Set<String> _loadedFonts = {};

  static Future<String> _defaultThemesDir() async {
    try {
      final dbDir = await getDatabasesPath();
      return p.normalize(p.join(dbDir, '..', 'app_flutter', 'themes'));
    } on Object {
      return p.join(Directory.systemTemp.path, 'ondadeck_themes');
    }
  }

  Future<String> getThemesRootDir() async {
    final path = await _themesDirProvider();
    await Directory(path).create(recursive: true);
    return path;
  }

  Future<List<ThemeManifest>> listInstalledThemes() async {
    final themesDir = await getThemesRootDir();
    final builtIns = <ThemeManifest>[];
    for (final id in builtInThemeIds) {
      final theme = await _loadBuiltInTheme(id, themesDir);
      await _registerFonts(theme);
      builtIns.add(theme);
    }
    final imported = await Isolate.run(
      () => _scanImportedThemesSync(themesDir),
      debugName: 'scanImportedThemes',
    );
    return [...builtIns, ...imported];
  }

  Future<ThemeManifest> loadTheme(String themeId) async {
    final themesDir = await getThemesRootDir();
    final resolvedId = themeId == 'ps3_xmb' ? builtInPspXmbId : themeId;
    if (builtInThemeIds.contains(resolvedId)) {
      final builtIn = await _loadBuiltInTheme(resolvedId, themesDir);
      await _registerFonts(builtIn);
      return builtIn;
    }

    final imported = await Isolate.run(
      () => _loadThemeFromDirSync(p.join(themesDir, resolvedId)),
      debugName: 'loadImportedTheme',
    );
    if (imported != null) {
      await _registerFonts(imported);
      return imported;
    }

    final fallback = await _loadBuiltInTheme(builtInDefaultId, themesDir);
    await _registerFonts(fallback);
    return fallback;
  }

  /// Extracts, validates, and installs a `.zip` / `.ondatheme` archive inside
  /// `Isolate.run()`.
  Future<ThemeManifest> importThemePackage(String archiveFilePath) async {
    final themesDir = await getThemesRootDir();
    final manifest = await Isolate.run(
      () => _importPackageSync(archiveFilePath, themesDir),
      debugName: 'importThemePackage',
    );
    await _registerFonts(manifest);
    return manifest;
  }

  Future<ThemeManifest> saveColorOverrides(
    String themeId,
    Map<String, int> overrides,
  ) async {
    if (!_safeThemeId.hasMatch(themeId)) {
      throw ThemeManifestException('ID de tema inválido: "$themeId".');
    }
    final themesDir = await getThemesRootDir();
    await Isolate.run(
      () => _writeOverridesSync(p.join(themesDir, themeId), overrides),
      debugName: 'saveColorOverrides',
    );
    return loadTheme(themeId);
  }

  Future<ThemeManifest> resetColorOverrides(String themeId) async {
    if (!_safeThemeId.hasMatch(themeId)) {
      throw ThemeManifestException('ID de tema inválido: "$themeId".');
    }
    final themesDir = await getThemesRootDir();
    await Isolate.run(() {
      final file = File(p.join(themesDir, themeId, overridesFileName));
      if (file.existsSync()) {
        file.deleteSync();
      }
    }, debugName: 'resetColorOverrides');
    return loadTheme(themeId);
  }

  Future<void> deleteImportedTheme(String themeId) async {
    if (builtInThemeIds.contains(themeId)) {
      throw const ThemeManifestException(
        'Temas embutidos (built-in) não podem ser excluídos.',
      );
    }
    if (!_safeThemeId.hasMatch(themeId)) {
      throw ThemeManifestException('ID de tema inválido: "$themeId".');
    }
    final themesDir = await getThemesRootDir();
    await Isolate.run(() {
      final dir = Directory(p.join(themesDir, themeId));
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    }, debugName: 'deleteImportedTheme');
  }

  Future<ThemeManifest> _loadBuiltInTheme(
    String themeId,
    String themesDir,
  ) async {
    final baseAsset = 'assets/themes/$themeId';
    final manifestRaw = await _bundle.loadString(
      '$baseAsset/manifest.json',
      cache: false,
    );
    final layoutRaw = await _bundle.loadString(
      '$baseAsset/layout.json',
      cache: false,
    );
    final overridesDir = p.join(themesDir, themeId);

    return Isolate.run(() {
      final manifest = ThemeManifest.parse(
        manifestRaw,
        basePath: baseAsset,
        isBuiltIn: true,
      );
      final layout = ThemeLayoutNode.parse(layoutRaw);
      final overrides = _readOverridesSync(overridesDir);
      return manifest.copyWith(layout: layout).applyColorOverrides(overrides);
    }, debugName: 'loadBuiltInTheme_$themeId');
  }

  Future<void> _registerFonts(ThemeManifest manifest) async {
    for (final entry in manifest.fonts.entries) {
      final path = entry.value;
      if (path.startsWith('assets/')) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      final cacheKey =
          '${entry.key}@$path@${file.lastModifiedSync().millisecondsSinceEpoch}';
      if (_loadedFonts.contains(cacheKey)) continue;

      final bytes = await file.readAsBytes();
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loadedFonts.add(cacheKey);
    }
  }

  // ---- Isolate-safe static helpers ------------------------------------------

  static List<ThemeManifest> _scanImportedThemesSync(String themesDir) {
    final root = Directory(themesDir);
    if (!root.existsSync()) return const [];
    final out = <ThemeManifest>[];
    for (final entity in root.listSync()) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (builtInThemeIds.contains(name) || name.startsWith('.')) continue;
      final loaded = _loadThemeFromDirSync(entity.path);
      if (loaded != null) {
        out.add(loaded);
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static ThemeManifest? _loadThemeFromDirSync(String themeDir) {
    final manifestFile = File(p.join(themeDir, 'manifest.json'));
    final layoutFile = File(p.join(themeDir, 'layout.json'));
    if (!manifestFile.existsSync() || !layoutFile.existsSync()) return null;

    try {
      final manifest = ThemeManifest.parse(
        manifestFile.readAsStringSync(),
        basePath: themeDir,
        isBuiltIn: false,
      );
      final layout = ThemeLayoutNode.parse(layoutFile.readAsStringSync());
      final discoveredFonts = _discoverFontsSync(themeDir, manifest.fonts);
      final overrides = _readOverridesSync(themeDir);
      return manifest
          .copyWith(layout: layout, fonts: discoveredFonts)
          .applyColorOverrides(overrides);
    } on Object {
      return null;
    }
  }

  static ThemeManifest _importPackageSync(
    String archiveFilePath,
    String themesDir,
  ) {
    final archiveFile = File(archiveFilePath);
    if (!archiveFile.existsSync()) {
      throw ThemeManifestException(
        'Arquivo de tema não encontrado: $archiveFilePath',
      );
    }

    final stagingRoot = p.join(
      themesDir,
      '.staging_${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      final bytes = archiveFile.readAsBytesSync();
      ZipArchiveExtractor.extractZipBytes(bytes, stagingRoot);

      final packageRoot = _resolveExtractedRoot(stagingRoot);
      final manifestFile = File(p.join(packageRoot, 'manifest.json'));
      final layoutFile = File(p.join(packageRoot, 'layout.json'));
      if (!manifestFile.existsSync()) {
        throw const ThemeManifestException(
          'Pacote inválido: arquivo "manifest.json" obrigatório não encontrado.',
        );
      }
      if (!layoutFile.existsSync()) {
        throw const ThemeManifestException(
          'Pacote inválido: arquivo "layout.json" obrigatório não encontrado.',
        );
      }

      final relativeManifest = ThemeManifest.parse(
        manifestFile.readAsStringSync(),
        basePath: null,
        isBuiltIn: false,
      );
      if (!_safeThemeId.hasMatch(relativeManifest.id)) {
        throw ThemeManifestException(
          'ID de tema inválido "${relativeManifest.id}". Use apenas letras, números, "-" ou "_".',
        );
      }
      if (builtInThemeIds.contains(relativeManifest.id)) {
        throw ThemeManifestException(
          'O ID "${relativeManifest.id}" é reservado a um tema built-in.',
        );
      }

      final layout = ThemeLayoutNode.parse(layoutFile.readAsStringSync());

      // Verify every referenced file exists inside the extracted package.
      final requiredPaths = <String>{
        if (relativeManifest.previewImage != null)
          relativeManifest.previewImage!,
        if (relativeManifest.background.kind == BackgroundKind.image &&
            relativeManifest.background.imagePath != null)
          relativeManifest.background.imagePath!,
        ...relativeManifest.audio.relativeOrResolvedPaths,
        ...relativeManifest.fonts.values,
        ...layout.collectReferencedAssets(),
      };

      final normalizedPkgRoot = p.normalize(p.absolute(packageRoot));
      for (final rel in requiredPaths) {
        if (rel.startsWith('assets/shaders/') ||
            rel.startsWith('assets/themes/') ||
            rel.contains('://')) {
          continue;
        }
        validateSafeRelativeAssetPath(rel, context: 'package_asset');
        final target = p.normalize(p.join(normalizedPkgRoot, rel));
        if (!p.isWithin(normalizedPkgRoot, target) ||
            !File(target).existsSync()) {
          throw ThemeManifestException(
            'Asset referenciado não encontrado no pacote: "$rel".',
          );
        }
      }

      final destDir = p.join(themesDir, relativeManifest.id);
      final dest = Directory(destDir);
      if (dest.existsSync()) {
        dest.deleteSync(recursive: true);
      }
      _copyDirectorySync(Directory(packageRoot), dest);

      final resolvedManifest = ThemeManifest.parse(
        File(p.join(destDir, 'manifest.json')).readAsStringSync(),
        basePath: destDir,
        isBuiltIn: false,
      );
      final discoveredFonts = _discoverFontsSync(
        destDir,
        resolvedManifest.fonts,
      );
      return resolvedManifest.copyWith(layout: layout, fonts: discoveredFonts);
    } finally {
      final staging = Directory(stagingRoot);
      if (staging.existsSync()) {
        staging.deleteSync(recursive: true);
      }
    }
  }

  static String _resolveExtractedRoot(String stagingRoot) {
    if (File(p.join(stagingRoot, 'manifest.json')).existsSync()) {
      return stagingRoot;
    }
    final children = Directory(stagingRoot).listSync().where((e) {
      final name = p.basename(e.path);
      return !name.startsWith('.') && name != '__MACOSX';
    }).toList();
    if (children.length == 1 && children.first is Directory) {
      return children.first.path;
    }
    return stagingRoot;
  }

  static Map<String, String> _discoverFontsSync(
    String themeDir,
    Map<String, String> declared,
  ) {
    final out = Map<String, String>.of(declared);
    final fontsDir = Directory(p.join(themeDir, 'fonts'));
    if (fontsDir.existsSync()) {
      for (final entity in fontsDir.listSync()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.ttf')) {
          final family = p.basenameWithoutExtension(entity.path);
          out.putIfAbsent(family, () => entity.path);
        }
      }
    }
    return Map.unmodifiable(out);
  }

  static Map<String, int> _readOverridesSync(String themeDir) {
    final file = File(p.join(themeDir, overridesFileName));
    if (!file.existsSync()) return const {};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return const {};
      final out = <String, int>{};
      for (final e in decoded.entries) {
        try {
          out['${e.key}'] = parseColor(e.value);
        } on Object {
          // Ignore malformed override entry.
        }
      }
      return out;
    } on Object {
      return const {};
    }
  }

  static void _writeOverridesSync(String themeDir, Map<String, int> overrides) {
    Directory(themeDir).createSync(recursive: true);
    final file = File(p.join(themeDir, overridesFileName));
    final payload = {
      for (final e in overrides.entries)
        e.key: ThemeManifest.formatColorHex(e.value, includeAlpha: true),
    };
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
  }

  static void _copyDirectorySync(Directory source, Directory destination) {
    destination.createSync(recursive: true);
    for (final entity in source.listSync(recursive: false)) {
      final name = p.basename(entity.path);
      final targetPath = p.join(destination.path, name);
      if (entity is Directory) {
        _copyDirectorySync(entity, Directory(targetPath));
      } else if (entity is File) {
        entity.copySync(targetPath);
      }
    }
  }
}
