import '../models/launch_config.dart';
import '../models/platform_models.dart';

/// Domain view of the Android host. Implemented by `NativeLauncherChannel`
/// (lib/platform) and by fakes in tests.
abstract interface class LauncherGateway {
  /// Apps with a launcher (or leanback) activity. [gamesOnly] filters on
  /// `CATEGORY_GAME`; pass `false` to let the user add anything manually.
  Future<List<InstalledApp>> getInstalledApps({bool gamesOnly = false});

  /// Renders app icons to PNG files at [sizePx] (cached natively by package
  /// version) and returns `packageName → absolute file path`.
  Future<Map<String, String>> getAppIcons(
    List<String> packageNames, {
    required int sizePx,
  });

  Future<bool> isPackageInstalled(String packageName);

  /// Throws [LaunchException] on failure.
  Future<void> launch(LaunchConfig config);

  // ---- Storage Access Framework -------------------------------------------------

  /// Opens the system folder picker and persists the grant. Null if cancelled.
  Future<SafEntry?> pickDirectory({String? initialUri});

  /// Opens the system file picker and persists the grant. Null if cancelled.
  Future<SafEntry?> pickFile({List<String> mimeTypes = const ['*/*']});

  Future<List<PersistedUri>> getPersistedUris();
  Future<void> releasePersistedUri(String uri);

  /// Lists a persisted tree (natively, off the main thread).
  Future<List<SafEntry>> listDirectory(
    String treeUri, {
    bool recursive = false,
    Set<String>? extensions,
    int maxDepth = 6,
    int limit = 20000,
  });

  /// Decodes + downsamples an image document to an app-private WebP file and
  /// returns its path. Results are cached by (uri, size).
  Future<String> importArtwork(
    String uri, {
    required int maxWidth,
    required int maxHeight,
  });

  /// Reads a small UTF-8 text document (theme.json, gamelists). Max 2 MB.
  Future<String> readText(String uri);

  /// Copies a SAF document URI (e.g. `.zip` / `.ondatheme`) to an app-private
  /// cache file off the UI thread and returns its absolute file path.
  Future<String> copyDocumentToCache(String uri, {String? preferredName});

  Future<DeviceProfile> getDeviceProfile();
}
