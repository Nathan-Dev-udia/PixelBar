import 'package:flutter/foundation.dart';

/// An app with a launcher activity, as reported by `PackageManager`.
@immutable
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    required this.isGame,
    this.isSystem = false,
    this.isLeanback = false,
    this.versionName,
    this.firstInstallTime,
    this.lastUpdateTime,
  });

  final String packageName;
  final String label;

  /// `ApplicationInfo.CATEGORY_GAME` (or legacy `FLAG_IS_GAME`).
  final bool isGame;
  final bool isSystem;
  final bool isLeanback;
  final String? versionName;
  final DateTime? firstInstallTime;
  final DateTime? lastUpdateTime;

  factory InstalledApp.fromMap(Map<Object?, Object?> map) => InstalledApp(
    packageName: map['packageName']! as String,
    label: (map['label'] as String?) ?? map['packageName']! as String,
    isGame: map['isGame'] as bool? ?? false,
    isSystem: map['isSystem'] as bool? ?? false,
    isLeanback: map['isLeanback'] as bool? ?? false,
    versionName: map['versionName'] as String?,
    firstInstallTime: _millis(map['firstInstallTime']),
    lastUpdateTime: _millis(map['lastUpdateTime']),
  );

  @override
  bool operator ==(Object other) =>
      other is InstalledApp &&
      other.packageName == packageName &&
      other.label == label &&
      other.isGame == isGame &&
      other.isSystem == isSystem &&
      other.isLeanback == isLeanback &&
      other.versionName == versionName &&
      other.firstInstallTime == firstInstallTime &&
      other.lastUpdateTime == lastUpdateTime;

  @override
  int get hashCode => Object.hash(
    packageName,
    label,
    isGame,
    isSystem,
    isLeanback,
    versionName,
    firstInstallTime,
    lastUpdateTime,
  );
}

/// A Storage Access Framework document or tree.
@immutable
class SafEntry {
  const SafEntry({
    required this.uri,
    required this.name,
    required this.isDirectory,
    this.mimeType,
    this.size,
    this.lastModified,
    this.persisted = false,
    this.apkPackageName,
    this.apkLabel,
    this.apkIconPath,
    this.apkInstalled = false,
  });

  final String uri;
  final String name;
  final bool isDirectory;
  final String? mimeType;
  final int? size;
  final DateTime? lastModified;

  /// Whether `takePersistableUriPermission` succeeded (survives reboots).
  final bool persisted;

  /// Metadata extracted natively when the entry is an `.apk` archive.
  final String? apkPackageName;
  final String? apkLabel;
  final String? apkIconPath;
  final bool apkInstalled;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  factory SafEntry.fromMap(Map<Object?, Object?> map) => SafEntry(
    uri: map['uri']! as String,
    name: (map['name'] as String?) ?? '',
    isDirectory: map['isDirectory'] as bool? ?? false,
    mimeType: map['mimeType'] as String?,
    size: (map['size'] as num?)?.toInt(),
    lastModified: _millis(map['lastModified']),
    persisted: map['persisted'] as bool? ?? false,
    apkPackageName: map['apkPackageName'] as String?,
    apkLabel: map['apkLabel'] as String?,
    apkIconPath: map['apkIconPath'] as String?,
    apkInstalled: map['apkInstalled'] as bool? ?? false,
  );
}

@immutable
class PersistedUri {
  const PersistedUri({
    required this.uri,
    required this.read,
    required this.write,
    this.persistedAt,
  });

  final String uri;
  final bool read;
  final bool write;
  final DateTime? persistedAt;

  factory PersistedUri.fromMap(Map<Object?, Object?> map) => PersistedUri(
    uri: map['uri']! as String,
    read: map['read'] as bool? ?? false,
    write: map['write'] as bool? ?? false,
    persistedAt: _millis(map['persistedTime']),
  );
}

/// Hardware facts used to adapt memory budgets.
@immutable
class DeviceProfile {
  const DeviceProfile({
    required this.sdkInt,
    required this.totalRamBytes,
    required this.isLowRamDevice,
    required this.memoryClassMb,
    this.manufacturer = '',
    this.model = '',
    this.abis = const [],
    this.isTelevision = false,
  });

  final int sdkInt;
  final int totalRamBytes;
  final bool isLowRamDevice;
  final int memoryClassMb;
  final String manufacturer;
  final String model;
  final List<String> abis;
  final bool isTelevision;

  factory DeviceProfile.fromMap(Map<Object?, Object?> map) => DeviceProfile(
    sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
    totalRamBytes: (map['totalRamBytes'] as num?)?.toInt() ?? 0,
    isLowRamDevice: map['isLowRamDevice'] as bool? ?? false,
    memoryClassMb: (map['memoryClassMb'] as num?)?.toInt() ?? 0,
    manufacturer: map['manufacturer'] as String? ?? '',
    model: map['model'] as String? ?? '',
    abis: List.unmodifiable((map['abis'] as List?)?.cast<String>() ?? const []),
    isTelevision: map['isTelevision'] as bool? ?? false,
  );
}

enum LaunchErrorCode {
  notInstalled,
  activityNotFound,
  invalidConfig,
  security,
  unknown,
}

class LaunchException implements Exception {
  const LaunchException(this.code, this.message);
  final LaunchErrorCode code;
  final String message;
  @override
  String toString() => 'LaunchException(${code.name}): $message';
}

DateTime? _millis(Object? v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
