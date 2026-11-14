import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../domain/repositories/launcher_gateway.dart';

typedef UpdateProgressCallback =
    void Function(double progress, int receivedBytes, int? totalBytes);

typedef UpdateCheckOverride = Future<AppUpdateInfo> Function();

typedef UpdateDownloadOverride =
    Future<bool> Function(
      AppUpdateInfo update, {
      UpdateProgressCallback? onProgress,
    });

/// Snapshot of the latest GitHub Release compared against the running APK build.
@immutable
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.latestTag,
    required this.latestBuildNumber,
    required this.releaseName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.assetName,
    required this.assetSizeBytes,
    required this.hasUpdate,
  });

  final String currentVersion;
  final int currentBuildNumber;
  final String latestTag;
  final int? latestBuildNumber;
  final String releaseName;
  final String releaseNotes;
  final String? downloadUrl;
  final String assetName;
  final int? assetSizeBytes;
  final bool hasUpdate;
}

/// Checks GitHub Releases for `Nathan-Dev-udia/PixelBar` and coordinates APK
/// download + native Android `PackageInstaller` handoff.
class AppUpdateService {
  AppUpdateService({
    required LauncherGateway gateway,
    HttpClient Function()? httpClientFactory,
    Future<PackageInfo> Function()? packageInfoLoader,
    UpdateCheckOverride? checkOverride,
    UpdateDownloadOverride? downloadOverride,
    Directory? updatesDirectory,
  }) : _gateway = gateway,
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _packageInfoLoader = packageInfoLoader ?? _defaultPackageInfoLoader,
       _checkOverride = checkOverride,
       _downloadOverride = downloadOverride,
       _updatesDirectory = updatesDirectory;

  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/Nathan-Dev-udia/PixelBar/releases/latest';
  static const String _userAgent = 'OndaDeck-AutoUpdater/1.0';
  static const String _updatesFolderName = 'ondadeck_updates';

  final LauncherGateway _gateway;
  final HttpClient Function() _httpClientFactory;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final UpdateCheckOverride? _checkOverride;
  final UpdateDownloadOverride? _downloadOverride;
  final Directory? _updatesDirectory;

  Directory get _resolvedUpdatesDir =>
      _updatesDirectory ??
      Directory('${Directory.systemTemp.path}/$_updatesFolderName');

  static Future<PackageInfo> _defaultPackageInfoLoader() async {
    try {
      return await PackageInfo.fromPlatform();
    } on MissingPluginException {
      return PackageInfo(
        appName: 'OndaDeck',
        packageName: 'com.ondapixel.ondadeck',
        version: '1.0.0',
        buildNumber: '1',
      );
    }
  }

  /// Extracts the numeric CI build number from tags like `v1.0.14`, `v0.1.3`,
  /// or `1.0.4+4`.
  static int? parseBuildNumberFromTag(String tag) {
    final cleaned = tag.trim();
    if (cleaned.isEmpty) return null;

    if (cleaned.contains('+')) {
      final buildPart = cleaned.split('+').last;
      final digits = buildPart.replaceAll(RegExp(r'[^0-9]'), '');
      final parsed = int.tryParse(digits);
      if (parsed != null) return parsed;
    }

    final withoutPrefix = cleaned.replaceFirst(RegExp(r'^[vV]'), '');
    final segments = withoutPrefix.split('.');
    for (var i = segments.length - 1; i >= 0; i--) {
      final match = RegExp(r'^(\d+)').firstMatch(segments[i].trim());
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!);
        if (parsed != null) return parsed;
      }
    }

    final fallback = RegExp(r'(\d+)').allMatches(cleaned).lastOrNull;
    return fallback == null ? null : int.tryParse(fallback.group(1)!);
  }

  /// Deletes stale temporary APK files downloaded by previous update sessions.
  Future<void> cleanupStaleUpdates({String? exceptPath}) async {
    final dir = _resolvedUpdatesDir;
    try {
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (exceptPath != null && entity.path == exceptPath) continue;
        try {
          entity.deleteSync();
        } catch (_) {
          // Best-effort cache hygiene.
        }
      }
    } catch (_) {
      // Best-effort cache hygiene when directory is transient.
    }
  }

  /// Queries GitHub Releases `/releases/latest` and compares build numbers.
  Future<AppUpdateInfo> checkForUpdate() async {
    if (_checkOverride != null) {
      return _checkOverride();
    }

    final pkg = await _packageInfoLoader();
    final currentBuild = int.tryParse(pkg.buildNumber.trim()) ?? 1;
    final currentVersion = '${pkg.version}+$currentBuild';

    final client = _httpClientFactory();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(Uri.parse(latestReleaseApiUrl))
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );

      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode == HttpStatus.notFound) {
        return AppUpdateInfo(
          currentVersion: currentVersion,
          currentBuildNumber: currentBuild,
          latestTag: '',
          latestBuildNumber: null,
          releaseName: 'Nenhuma release publicada',
          releaseNotes: '',
          downloadUrl: null,
          assetName: 'PixelBar-arm64.apk',
          assetSizeBytes: null,
          hasUpdate: false,
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'GitHub API respondeu com HTTP ${response.statusCode}',
          uri: Uri.parse(latestReleaseApiUrl),
        );
      }

      final rawBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 12));
      final payload = jsonDecode(rawBody);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Resposta inválida da API de releases.');
      }

      final latestTag = (payload['tag_name'] as String? ?? '').trim();
      final releaseName = (payload['name'] as String? ?? latestTag).trim();
      final releaseNotes = (payload['body'] as String? ?? '').trim();
      final latestBuild = parseBuildNumberFromTag(latestTag);

      final asset = _pickApkAsset(payload['assets']);
      final downloadUrl = asset?['browser_download_url'] as String?;
      final assetName = (asset?['name'] as String? ?? 'PixelBar-arm64.apk')
          .trim();
      final assetSize = asset?['size'] is int ? asset!['size'] as int : null;

      final hasUpdate =
          latestBuild != null &&
          latestBuild > currentBuild &&
          downloadUrl != null &&
          downloadUrl.isNotEmpty;

      return AppUpdateInfo(
        currentVersion: currentVersion,
        currentBuildNumber: currentBuild,
        latestTag: latestTag,
        latestBuildNumber: latestBuild,
        releaseName: releaseName.isEmpty ? latestTag : releaseName,
        releaseNotes: releaseNotes,
        downloadUrl: downloadUrl,
        assetName: assetName,
        assetSizeBytes: assetSize,
        hasUpdate: hasUpdate,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Streams the APK into the app's temporary directory, then invokes Android
  /// `installApk(filePath)`.
  Future<bool> downloadAndInstall(
    AppUpdateInfo update, {
    UpdateProgressCallback? onProgress,
  }) async {
    if (_downloadOverride != null) {
      return _downloadOverride(update, onProgress: onProgress);
    }

    final url = update.downloadUrl;
    if (url == null || url.isEmpty) {
      throw StateError('Release não contém link de download de APK.');
    }

    await cleanupStaleUpdates();

    final updatesDir = _resolvedUpdatesDir;
    await updatesDir.create(recursive: true);

    final sanitizedName = update.assetName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .trim();
    final targetName = sanitizedName.toLowerCase().endsWith('.apk')
        ? sanitizedName
        : 'PixelBar-update.apk';
    final partFile = File('${updatesDir.path}/$targetName.part');
    final apkFile = File('${updatesDir.path}/$targetName');
    if (await partFile.exists()) await partFile.delete();
    if (await apkFile.exists()) await apkFile.delete();

    final client = _httpClientFactory();
    client.connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      request.followRedirects = true;
      request.maxRedirects = 6;
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);

      final response = await request.close().timeout(
        const Duration(minutes: 3),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Falha ao baixar APK (HTTP ${response.statusCode})',
          uri: Uri.parse(url),
        );
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : update.assetSizeBytes;

      sink = partFile.openWrite();
      var receivedBytes = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final progress = totalBytes != null && totalBytes > 0
            ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
            : 0.0;
        onProgress?.call(progress, receivedBytes, totalBytes);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (await partFile.length() == 0) {
        throw const FileSystemException('Arquivo APK baixado está vazio.');
      }

      await partFile.rename(apkFile.path);
      onProgress?.call(1.0, receivedBytes, totalBytes ?? receivedBytes);

      final launched = await _gateway.installApk(apkFile.path);
      if (!launched) {
        // User declined unknown-sources permission or cancelled before handover.
        await cleanupStaleUpdates();
      }
      return launched;
    } catch (_) {
      await sink?.close();
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic>? _pickApkAsset(Object? rawAssets) {
    if (rawAssets is! List) return null;
    Map<String, dynamic>? fallbackApk;
    for (final entry in rawAssets) {
      if (entry is! Map) continue;
      final map = entry.cast<String, dynamic>();
      final name = (map['name'] as String? ?? '').toLowerCase();
      final url = map['browser_download_url'] as String? ?? '';
      if (!name.endsWith('.apk') || url.isEmpty) continue;
      if (name.contains('arm64')) {
        return map;
      }
      fallbackApk ??= map;
    }
    return fallbackApk;
  }
}
