import 'package:flutter/foundation.dart';

/// How the native bridge should start a target.
enum LaunchType {
  /// Start the default launcher activity of an installed APK (native games,
  /// recomp ports, emulator front pages).
  package,

  /// Fire an arbitrary intent (typically `ACTION_VIEW` + data URI + extras)
  /// at an external emulator.
  intent,
}

/// Explicit type of an intent extra. Android emulators are picky about extra
/// types (`Int` vs `Long`, `String` vs `Uri`), so we never rely on inference
/// when serialising to the platform channel.
enum LaunchExtraType {
  string,
  int,
  long,
  float,
  double,
  bool,
  stringList,
  stringArray,
  uri,
}

/// Intent flags understood by the native side (mapped to `Intent.FLAG_ACTIVITY_*`).
abstract final class LaunchFlags {
  static const newTask = 'NEW_TASK';
  static const clearTask = 'CLEAR_TASK';
  static const clearTop = 'CLEAR_TOP';
  static const singleTop = 'SINGLE_TOP';
  static const noHistory = 'NO_HISTORY';
  static const resetTaskIfNeeded = 'RESET_TASK_IF_NEEDED';
  static const noAnimation = 'NO_ANIMATION';
  static const excludeFromRecents = 'EXCLUDE_FROM_RECENTS';
  static const multipleTask = 'MULTIPLE_TASK';

  static const all = {
    newTask, clearTask, clearTop, singleTop, noHistory, resetTaskIfNeeded, //
    noAnimation, excludeFromRecents, multipleTask,
  };
}

final _tokenPattern = RegExp(r'\{(\w+)\}');

/// Replaces `{token}` placeholders (e.g. `{rom_uri}`) using [vars]. Unknown
/// tokens are kept verbatim so validation can flag them later.
String substituteTokens(String input, Map<String, String> vars) =>
    input.replaceAllMapped(_tokenPattern, (m) => vars[m[1]] ?? m[0]!);

@immutable
class LaunchExtra {
  const LaunchExtra._(this.type, this.value);

  const LaunchExtra.string(String value)
    : this._(LaunchExtraType.string, value);
  const LaunchExtra.int(int value) : this._(LaunchExtraType.int, value);
  const LaunchExtra.long(int value) : this._(LaunchExtraType.long, value);
  const LaunchExtra.float(double value) : this._(LaunchExtraType.float, value);
  const LaunchExtra.double(double value)
    : this._(LaunchExtraType.double, value);
  const LaunchExtra.bool(bool value) : this._(LaunchExtraType.bool, value);
  const LaunchExtra.stringList(List<String> value)
    : this._(LaunchExtraType.stringList, value);
  const LaunchExtra.stringArray(List<String> value)
    : this._(LaunchExtraType.stringArray, value);
  const LaunchExtra.uri(String value) : this._(LaunchExtraType.uri, value);

  final LaunchExtraType type;
  final Object value;

  /// Accepts either a typed object `{"type": "long", "value": 3}` or a raw
  /// JSON primitive (type inferred: string/int/double/bool/string list).
  factory LaunchExtra.fromJson(Object? json) {
    if (json is Map) {
      final typeName = json['type'];
      final type = LaunchExtraType.values.asNameMap()[typeName];
      if (type == null) throw FormatException('Unknown extra type: $typeName');
      return LaunchExtra._(type, _coerce(type, json['value']));
    }
    return switch (json) {
      final String v => LaunchExtra.string(v),
      final bool v => LaunchExtra.bool(v),
      final int v => LaunchExtra.int(v),
      final double v => LaunchExtra.double(v),
      final List<Object?> v => LaunchExtra.stringList([
        for (final e in v) '$e',
      ]),
      _ => throw FormatException('Unsupported extra value: $json'),
    };
  }

  static Object _coerce(LaunchExtraType type, Object? raw) {
    Never bad() => throw FormatException(
      'Invalid value "$raw" for extra type ${type.name}',
    );
    return switch (type) {
      LaunchExtraType.string ||
      LaunchExtraType.uri => raw is String ? raw : bad(),
      LaunchExtraType.int ||
      LaunchExtraType.long => raw is num ? raw.toInt() : bad(),
      LaunchExtraType.float ||
      LaunchExtraType.double => raw is num ? raw.toDouble() : bad(),
      LaunchExtraType.bool => raw is bool ? raw : bad(),
      LaunchExtraType.stringList || LaunchExtraType.stringArray =>
        raw is List ? List<String>.unmodifiable(raw.map((e) => '$e')) : bad(),
    };
  }

  Map<String, Object?> toJson() => {'type': type.name, 'value': value};

  LaunchExtra resolve(Map<String, String> vars) => switch (type) {
    LaunchExtraType.string => LaunchExtra.string(
      substituteTokens(value as String, vars),
    ),
    LaunchExtraType.uri => LaunchExtra.uri(
      substituteTokens(value as String, vars),
    ),
    LaunchExtraType.stringList => LaunchExtra.stringList([
      for (final s in value as List<String>) substituteTokens(s, vars),
    ]),
    LaunchExtraType.stringArray => LaunchExtra.stringArray([
      for (final s in value as List<String>) substituteTokens(s, vars),
    ]),
    _ => this,
  };

  @override
  bool operator ==(Object other) =>
      other is LaunchExtra &&
      other.type == type &&
      (value is List
          ? listEquals(
              value as List,
              other.value is List ? other.value as List : null,
            )
          : other.value == value);

  @override
  int get hashCode =>
      Object.hash(type, value is List ? Object.hashAll(value as List) : value);

  @override
  String toString() => 'LaunchExtra(${type.name}: $value)';
}

/// Everything the native bridge needs to start a game. Pure data: serialisable
/// to JSON (persisted in the DB) and to the platform channel.
@immutable
class LaunchConfig {
  const LaunchConfig({
    required this.type,
    this.packageName,
    this.activityName,
    this.action,
    this.dataUri,
    this.mimeType,
    this.categories = const [],
    this.extras = const {},
    this.flags = const [LaunchFlags.newTask],
    this.grantUriRead = true,
    this.grantUriWrite = false,
  });

  /// Opens an installed APK (native game / recomp port) by package name.
  const LaunchConfig.package(String packageName, {String? activityName})
    : this(
        type: LaunchType.package,
        packageName: packageName,
        activityName: activityName,
      );

  /// Fires an intent at an external app, e.g. an emulator with a ROM URI.
  const LaunchConfig.intent({
    String? packageName,
    String? activityName,
    String action = actionView,
    String? dataUri,
    String? mimeType,
    List<String> categories = const [],
    Map<String, LaunchExtra> extras = const {},
    List<String> flags = const [LaunchFlags.newTask],
    bool grantUriRead = true,
    bool grantUriWrite = false,
  }) : this(
         type: LaunchType.intent,
         packageName: packageName,
         activityName: activityName,
         action: action,
         dataUri: dataUri,
         mimeType: mimeType,
         categories: categories,
         extras: extras,
         flags: flags,
         grantUriRead: grantUriRead,
         grantUriWrite: grantUriWrite,
       );

  static const actionView = 'android.intent.action.VIEW';
  static const actionMain = 'android.intent.action.MAIN';

  final LaunchType type;
  final String? packageName;

  /// Fully qualified class name, or relative to [packageName] when it starts
  /// with a dot (".EmulationActivity").
  final String? activityName;
  final String? action;
  final String? dataUri;
  final String? mimeType;
  final List<String> categories;
  final Map<String, LaunchExtra> extras;
  final List<String> flags;

  /// Adds `FLAG_GRANT_READ_URI_PERMISSION` (+ ClipData) when [dataUri] is a
  /// `content://` SAF URI, so the emulator can read the ROM we hold access to.
  final bool grantUriRead;
  final bool grantUriWrite;

  /// Returns a copy with `{token}` placeholders in [dataUri] / string extras
  /// replaced (e.g. `{rom_uri}`, `{rom_path}`, `{rom_name}`).
  LaunchConfig resolve(Map<String, String> vars) => LaunchConfig(
    type: type,
    packageName: packageName,
    activityName: activityName,
    action: action,
    dataUri: dataUri == null ? null : substituteTokens(dataUri!, vars),
    mimeType: mimeType,
    categories: categories,
    extras: {for (final e in extras.entries) e.key: e.value.resolve(vars)},
    flags: flags,
    grantUriRead: grantUriRead,
    grantUriWrite: grantUriWrite,
  );

  /// Null when valid, otherwise a human-readable reason.
  String? get validationError {
    if (type == LaunchType.package &&
        (packageName == null || packageName!.isEmpty)) {
      return 'Launch type "package" requires packageName.';
    }
    if (type == LaunchType.intent && packageName == null && dataUri == null) {
      return 'Launch type "intent" requires packageName or dataUri.';
    }
    if (activityName != null && packageName == null) {
      return 'activityName requires packageName.';
    }
    final unknownFlags = flags.where((f) => !LaunchFlags.all.contains(f));
    if (unknownFlags.isNotEmpty) {
      return 'Unknown flags: ${unknownFlags.join(', ')}';
    }
    final unresolved = [
      ?dataUri,
      for (final e in extras.values)
        if (e.value is String) e.value as String,
    ].where(_tokenPattern.hasMatch);
    if (unresolved.isNotEmpty) {
      return 'Unresolved tokens in: ${unresolved.join(', ')}';
    }
    return null;
  }

  factory LaunchConfig.fromJson(Map<String, Object?> json) {
    final type = LaunchType.values.asNameMap()[json['type']];
    if (type == null) {
      throw FormatException('Unknown launch type: ${json['type']}');
    }
    final rawExtras = (json['extras'] as Map?) ?? const {};
    return LaunchConfig(
      type: type,
      packageName: json['packageName'] as String?,
      activityName: json['activityName'] as String?,
      action: json['action'] as String?,
      dataUri: json['dataUri'] as String?,
      mimeType: json['mimeType'] as String?,
      categories: List.unmodifiable(
        (json['categories'] as List?)?.cast<String>() ?? const [],
      ),
      extras: Map.unmodifiable({
        for (final e in rawExtras.entries)
          '${e.key}': LaunchExtra.fromJson(e.value),
      }),
      flags: List.unmodifiable(
        (json['flags'] as List?)?.cast<String>() ?? const [LaunchFlags.newTask],
      ),
      grantUriRead: json['grantUriRead'] as bool? ?? true,
      grantUriWrite: json['grantUriWrite'] as bool? ?? false,
    );
  }

  /// Also the exact payload sent through the `launchTarget` method channel.
  Map<String, Object?> toJson() => {
    'type': type.name,
    if (packageName != null) 'packageName': packageName,
    if (activityName != null) 'activityName': activityName,
    if (action != null) 'action': action,
    if (dataUri != null) 'dataUri': dataUri,
    if (mimeType != null) 'mimeType': mimeType,
    if (categories.isNotEmpty) 'categories': categories,
    if (extras.isNotEmpty)
      'extras': {for (final e in extras.entries) e.key: e.value.toJson()},
    'flags': flags,
    'grantUriRead': grantUriRead,
    'grantUriWrite': grantUriWrite,
  };

  @override
  bool operator ==(Object other) =>
      other is LaunchConfig &&
      other.type == type &&
      other.packageName == packageName &&
      other.activityName == activityName &&
      other.action == action &&
      other.dataUri == dataUri &&
      other.mimeType == mimeType &&
      listEquals(other.categories, categories) &&
      mapEquals(other.extras, extras) &&
      listEquals(other.flags, flags) &&
      other.grantUriRead == grantUriRead &&
      other.grantUriWrite == grantUriWrite;

  @override
  int get hashCode => Object.hash(
    type,
    packageName,
    activityName,
    action,
    dataUri,
    mimeType, //
    Object.hashAll(categories),
    Object.hashAllUnordered(
      extras.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAll(flags),
    grantUriRead,
    grantUriWrite,
  );

  @override
  String toString() => switch (type) {
    LaunchType.package =>
      'LaunchConfig.package($packageName${activityName == null ? '' : '/$activityName'})',
    LaunchType.intent =>
      'LaunchConfig.intent($action → ${packageName ?? '*'}${activityName == null ? '' : '/$activityName'}, data: $dataUri, extras: ${extras.keys.toList()})',
  };
}
