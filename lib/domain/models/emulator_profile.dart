import 'package:flutter/foundation.dart';

import 'game_item.dart';
import 'launch_config.dart';

/// Template that turns a ROM document into a launchable [GameItem].
///
/// Supported tokens in `template.dataUri` and string extras:
/// - `{rom_uri}`  → SAF `content://` URI (preferred; works on Android 13+)
/// - `{rom_path}` → raw filesystem path (only for emulators that require it)
/// - `{rom_name}` → file name without extension
@immutable
class EmulatorProfile {
  const EmulatorProfile({
    required this.id,
    required this.name,
    required this.platforms,
    required this.extensions,
    required this.template,
    this.notes,
  });

  final String id;
  final String name;
  final List<String> platforms;
  final List<String> extensions;
  final LaunchConfig template;
  final String? notes;

  String? get packageName => template.packageName;

  GameItem createGame({
    required String romUri,
    required String romName,
    required String platform,
    required DateTime now,
    String? romPath,
  }) {
    final dot = romName.lastIndexOf('.');
    final baseName = dot > 0 ? romName.substring(0, dot) : romName;
    return GameItem(
      id: GameItem.idForDocument(id, romUri),
      title: baseName,
      kind: GameKind.emulated,
      source: GameSource.manual,
      platform: platform,
      addedAt: now,
      launch: template.resolve({
        'rom_uri': romUri,
        'rom_name': baseName,
        'rom_path': ?romPath,
      }),
    );
  }
}

/// Starting presets, modelled after the public ES-DE Android launch rules.
/// Emulator intent contracts change between releases: always verify on device.
abstract final class EmulatorPresets {
  static const retroArch = EmulatorProfile(
    id: 'retroarch',
    name: 'RetroArch',
    platforms: ['nes', 'snes', 'gb', 'gba', 'genesis', 'psx', 'n64'],
    extensions: [
      'zip',
      '7z',
      'nes',
      'sfc',
      'smc',
      'gb',
      'gbc',
      'gba',
      'md',
      'bin',
      'cue',
      'chd',
      'z64',
      'n64',
    ],
    notes:
        'Requires {rom_path} (raw path) and a core in LIBRETRO; content:// is not reliably supported.',
    template: LaunchConfig.intent(
      packageName: 'com.retroarch',
      activityName: 'com.retroarch.browser.retroactivity.RetroActivityFuture',
      action: LaunchConfig.actionMain,
      grantUriRead: false,
      flags: [LaunchFlags.newTask, LaunchFlags.clearTask],
      extras: {
        'ROM': LaunchExtra.string('{rom_path}'),
        'LIBRETRO': LaunchExtra.string(
          '/data/data/com.retroarch/cores/{core}_libretro_android.so',
        ),
        'CONFIGFILE': LaunchExtra.string(
          '/storage/emulated/0/Android/data/com.retroarch/files/retroarch.cfg',
        ),
      },
    ),
  );

  static const dolphin = EmulatorProfile(
    id: 'dolphin',
    name: 'Dolphin',
    platforms: ['gc', 'wii'],
    extensions: [
      'iso',
      'gcm',
      'ciso',
      'gcz',
      'rvz',
      'wbfs',
      'wad',
      'dol',
      'elf',
    ],
    template: LaunchConfig.intent(
      packageName: 'org.dolphinemu.dolphinemu',
      activityName: 'org.dolphinemu.dolphinemu.ui.main.MainActivity',
      flags: [LaunchFlags.newTask, LaunchFlags.clearTask],
      extras: {'AutoStartFile': LaunchExtra.string('{rom_uri}')},
    ),
  );

  static const netherSx2 = EmulatorProfile(
    id: 'nethersx2',
    name: 'NetherSX2',
    platforms: ['ps2'],
    extensions: ['iso', 'chd', 'cso', 'bin', 'gz'],
    template: LaunchConfig.intent(
      packageName: 'xyz.aethersx2.android',
      activityName: 'xyz.aethersx2.android.EmulationActivity',
      flags: [LaunchFlags.newTask, LaunchFlags.clearTask],
      extras: {'bootPath': LaunchExtra.string('{rom_uri}')},
    ),
  );

  static const all = [retroArch, dolphin, netherSx2];
}
