import 'package:flutter/widgets.dart';

import '../domain/models/game_item.dart';
import '../domain/models/library_state.dart';

/// Abstract UI isolation contract for all OndaDeck themes.
///
/// Themes are pure presentation layers: they receive an immutable [LibraryState]
/// and emit standardized interaction events without directly touching storage,
/// isolates, or platform channels.
abstract class ConsoleThemeWidget extends StatefulWidget {
  const ConsoleThemeWidget({
    super.key,
    required this.state,
    required this.onSelectGame,
    required this.onLaunchGame,
    required this.onOpenSettings,
    this.onAddApps,
    this.onRemoveGame,
    this.onEditGame,
    this.onToggleFavorite,
    this.onRescan,
    this.onOpenThemeManager,
  });

  final LibraryState state;
  final ValueChanged<GameItem> onSelectGame;
  final ValueChanged<GameItem> onLaunchGame;
  final VoidCallback onOpenSettings;
  final VoidCallback? onAddApps;
  final ValueChanged<GameItem>? onRemoveGame;
  final ValueChanged<GameItem>? onEditGame;
  final ValueChanged<GameItem>? onToggleFavorite;
  final VoidCallback? onRescan;
  final VoidCallback? onOpenThemeManager;
}

typedef ConsoleThemeBuilder =
    ConsoleThemeWidget Function({
      Key? key,
      required LibraryState state,
      required ValueChanged<GameItem> onSelectGame,
      required ValueChanged<GameItem> onLaunchGame,
      required VoidCallback onOpenSettings,
      VoidCallback? onAddApps,
      ValueChanged<GameItem>? onRemoveGame,
      ValueChanged<GameItem>? onEditGame,
      ValueChanged<GameItem>? onToggleFavorite,
      VoidCallback? onRescan,
      VoidCallback? onOpenThemeManager,
    });

/// Maps `ThemeManifest.engine` identifiers to concrete [ConsoleThemeWidget] builders.
final class ThemeEngineRegistry {
  ThemeEngineRegistry._();

  static final ThemeEngineRegistry instance = ThemeEngineRegistry._();

  static const String defaultEngineId = 'wireframe_debug';

  final Map<String, ConsoleThemeBuilder> _engines = {};

  void register(String engineId, ConsoleThemeBuilder builder) {
    _engines[engineId] = builder;
  }

  bool hasEngine(String engineId) => _engines.containsKey(engineId);

  List<String> get registeredEngines => List.unmodifiable(_engines.keys);

  ConsoleThemeWidget build({
    Key? key,
    required String engineId,
    required LibraryState state,
    required ValueChanged<GameItem> onSelectGame,
    required ValueChanged<GameItem> onLaunchGame,
    required VoidCallback onOpenSettings,
    VoidCallback? onAddApps,
    ValueChanged<GameItem>? onRemoveGame,
    ValueChanged<GameItem>? onEditGame,
    ValueChanged<GameItem>? onToggleFavorite,
    VoidCallback? onRescan,
    VoidCallback? onOpenThemeManager,
  }) {
    final builder = _engines[engineId] ?? _engines[defaultEngineId];
    if (builder == null) {
      throw StateError(
        'No theme engine registered for "$engineId" or default "$defaultEngineId".',
      );
    }
    return builder(
      key: key,
      state: state,
      onSelectGame: onSelectGame,
      onLaunchGame: onLaunchGame,
      onOpenSettings: onOpenSettings,
      onAddApps: onAddApps,
      onRemoveGame: onRemoveGame,
      onEditGame: onEditGame,
      onToggleFavorite: onToggleFavorite,
      onRescan: onRescan,
      onOpenThemeManager: onOpenThemeManager,
    );
  }
}
