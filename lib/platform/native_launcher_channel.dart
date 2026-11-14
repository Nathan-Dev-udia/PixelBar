import 'package:flutter/services.dart';

import '../domain/models/launch_config.dart';
import '../domain/models/platform_models.dart';
import '../domain/repositories/launcher_gateway.dart';

/// Dart wrapper over the Android `MethodChannel` bridge (`com.ondapixel.ondadeck/launcher`).
class NativeLauncherChannel implements LauncherGateway {
  NativeLauncherChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.ondapixel.ondadeck/launcher';

  final MethodChannel _channel;

  @override
  Future<List<InstalledApp>> getInstalledApps({bool gamesOnly = false}) async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'getInstalledApps',
        {'gamesOnly': gamesOnly},
      );
      if (raw == null) return const [];
      return [
        for (final entry in raw)
          if (entry is Map) InstalledApp.fromMap(entry),
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<Map<String, String>> getAppIcons(
    List<String> packageNames, {
    required int sizePx,
  }) async {
    if (packageNames.isEmpty) return const {};
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getAppIcons',
        {'packages': packageNames, 'sizePx': sizePx},
      );
      if (raw == null) return const {};
      return {
        for (final e in raw.entries)
          if (e.key is String && e.value is String)
            e.key! as String: e.value! as String,
      };
    } on MissingPluginException {
      return const {};
    }
  }

  @override
  Future<bool> isPackageInstalled(String packageName) async {
    try {
      return (await _channel.invokeMethod<bool>('isPackageInstalled', {
            'packageName': packageName,
          })) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> launch(LaunchConfig config) async {
    final err = config.validationError;
    if (err != null) {
      throw LaunchException(LaunchErrorCode.invalidConfig, err);
    }
    try {
      await _channel.invokeMethod<void>('launchTarget', config.toJson());
    } on PlatformException catch (e) {
      throw LaunchException(
        _mapErrorCode(e.code),
        e.message ?? 'Failed to launch target.',
      );
    } on MissingPluginException {
      throw const LaunchException(
        LaunchErrorCode.unknown,
        'Launcher native channel is unavailable on this platform.',
      );
    }
  }

  @override
  Future<SafEntry?> pickDirectory({String? initialUri}) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'pickDirectory',
        {'initialUri': ?initialUri},
      );
      return raw == null ? null : SafEntry.fromMap(raw);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<SafEntry?> pickFile({List<String> mimeTypes = const ['*/*']}) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'pickFile',
        {'mimeTypes': mimeTypes},
      );
      return raw == null ? null : SafEntry.fromMap(raw);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<List<PersistedUri>> getPersistedUris() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'getPersistedUris',
      );
      if (raw == null) return const [];
      return [
        for (final entry in raw)
          if (entry is Map) PersistedUri.fromMap(entry),
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> releasePersistedUri(String uri) async {
    try {
      await _channel.invokeMethod<void>('releasePersistedUri', {'uri': uri});
    } on MissingPluginException {
      // No-op on non-Android hosts.
    }
  }

  @override
  Future<List<SafEntry>> listDirectory(
    String treeUri, {
    bool recursive = false,
    Set<String>? extensions,
    int maxDepth = 6,
    int limit = 20000,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('listDirectory', {
        'treeUri': treeUri,
        'recursive': recursive,
        if (extensions != null) 'extensions': extensions.toList(),
        'maxDepth': maxDepth,
        'limit': limit,
      });
      if (raw == null) return const [];
      return [
        for (final entry in raw)
          if (entry is Map) SafEntry.fromMap(entry),
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<String> importArtwork(
    String uri, {
    required int maxWidth,
    required int maxHeight,
  }) async {
    final result = await _channel.invokeMethod<String>('importArtwork', {
      'uri': uri,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
    });
    if (result == null || result.isEmpty) {
      throw PlatformException(
        code: 'ARTWORK_IMPORT_FAILED',
        message: 'Empty path returned for $uri',
      );
    }
    return result;
  }

  @override
  Future<String> readText(String uri) async {
    final result = await _channel.invokeMethod<String>('readText', {
      'uri': uri,
    });
    if (result == null) {
      throw PlatformException(
        code: 'READ_TEXT_FAILED',
        message: 'Unable to read text from $uri',
      );
    }
    return result;
  }

  @override
  Future<DeviceProfile> getDeviceProfile() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getDeviceProfile',
      );
      if (raw == null) {
        return const DeviceProfile(
          sdkInt: 0,
          totalRamBytes: 0,
          isLowRamDevice: false,
          memoryClassMb: 0,
        );
      }
      return DeviceProfile.fromMap(raw);
    } on MissingPluginException {
      return const DeviceProfile(
        sdkInt: 0,
        totalRamBytes: 0,
        isLowRamDevice: false,
        memoryClassMb: 0,
      );
    }
  }

  static LaunchErrorCode _mapErrorCode(String code) => switch (code) {
    'NOT_INSTALLED' => LaunchErrorCode.notInstalled,
    'ACTIVITY_NOT_FOUND' => LaunchErrorCode.activityNotFound,
    'INVALID_CONFIG' => LaunchErrorCode.invalidConfig,
    'SECURITY' => LaunchErrorCode.security,
    _ => LaunchErrorCode.unknown,
  };
}
