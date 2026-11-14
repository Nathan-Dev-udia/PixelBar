import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/input/gamepad_input.dart';
import 'core/memory/lifecycle_memory_manager.dart';
import 'core/state/library_controller.dart';
import 'domain/models/game_item.dart';
import 'domain/models/launcher_settings.dart';
import 'themes/console_theme_widget.dart';
import 'themes/data_driven/data_driven_theme_engine.dart';
import 'themes/manager/theme_manager_screen.dart';
import 'themes/metadata/game_metadata_editor_dialog.dart';
import 'themes/wireframe_debug/wireframe_debug_theme.dart';

void registerDefaultThemes() {
  if (!ThemeEngineRegistry.instance.hasEngine('data_driven')) {
    ThemeEngineRegistry.instance.register(
      'data_driven',
      ({
        Key? key,
        required state,
        required onSelectGame,
        required onLaunchGame,
        required onOpenSettings,
        onAddApps,
        onRemoveGame,
        onEditGame,
        onToggleFavorite,
        onRescan,
        onOpenThemeManager,
      }) => DataDrivenThemeEngine(
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
      ),
    );
  }
  if (!ThemeEngineRegistry.instance.hasEngine('wireframe_debug')) {
    ThemeEngineRegistry.instance.register(
      'wireframe_debug',
      ({
        Key? key,
        required state,
        required onSelectGame,
        required onLaunchGame,
        required onOpenSettings,
        onAddApps,
        onRemoveGame,
        onEditGame,
        onToggleFavorite,
        onRescan,
        onOpenThemeManager,
      }) => WireframeDebugTheme(
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
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  LifecycleMemoryManager.instance.install();
  registerDefaultThemes();

  runApp(const ProviderScope(child: OndaDeckApp()));
}

class OndaDeckApp extends StatefulWidget {
  const OndaDeckApp({super.key});

  @override
  State<OndaDeckApp> createState() => _OndaDeckAppState();
}

class _OndaDeckAppState extends State<OndaDeckApp> {
  @override
  void initState() {
    super.initState();
    registerDefaultThemes();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OndaDeck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      shortcuts: {...WidgetsApp.defaultShortcuts, ...GamepadShortcuts.bindings},
      home: const _OndaDeckShell(),
    );
  }
}

class _OndaDeckShell extends ConsumerWidget {
  const _OndaDeckShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);

    return Actions(
      actions: {
        GamepadBackIntent: CallbackAction<GamepadBackIntent>(
          onInvoke: (_) {
            final nav = Navigator.of(context);
            if (nav.canPop()) nav.pop();
            return null;
          },
        ),
      },
      child: ValueListenableBuilder<HibernationLevel?>(
        valueListenable: LifecycleMemoryManager.instance.hibernation,
        builder: (context, hibernation, _) {
          if (hibernation == HibernationLevel.hard) {
            return const ColoredBox(color: Color(0xFF000000));
          }
          return ThemeEngineRegistry.instance.build(
            engineId: state.theme.engine,
            state: state,
            onSelectGame: controller.selectGame,
            onLaunchGame: controller.launchGame,
            onOpenSettings: () => _openSettings(context),
            onAddApps: () => _openManualAppPicker(context),
            onRemoveGame: controller.removeGame,
            onEditGame: (game) => _openGameMetadataEditor(context, game),
            onToggleFavorite: controller.toggleFavorite,
            onRescan: controller.refreshInstalledApps,
            onOpenThemeManager: () => _openThemeManager(context),
          );
        },
      ),
    );
  }

  Future<void> _openManualAppPicker(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const _ManualAppPickerDialog(),
  );

  Future<void> _openGameMetadataEditor(BuildContext context, GameItem game) =>
      showDialog<void>(
        context: context,
        builder: (_) => GameMetadataEditorDialog(game: game),
      );

  Future<void> _openSettings(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const _SettingsDialog(),
  );

  Future<void> _openThemeManager(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const ThemeManagerDialog(),
  );
}

class _ManualAppPickerDialog extends ConsumerWidget {
  const _ManualAppPickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);
    final settings = libraryState.settings;
    final gamesById = <String, GameItem>{
      for (final c in libraryState.categories)
        for (final g in c.games) g.id: g,
    };
    final games = gamesById.values.toList();
    final hasFolder =
        settings.gamesFolderUri != null && settings.gamesFolderUri!.isNotEmpty;

    return Actions(
      actions: {
        GamepadBackIntent: CallbackAction<GamepadBackIntent>(
          onInvoke: (_) {
            Navigator.of(context).pop();
            return null;
          },
        ),
      },
      child: Dialog(
        backgroundColor: const Color(0xFF12161C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'PASTA DE JOGOS (APKS & ROMS)',
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontFamily: 'monospace',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pasta ativa: ${settings.gamesFolderName ?? 'Nenhuma pasta selecionada'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8C96A5),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                _FocusableMenuRow(
                  autofocus: true,
                  label: 'Escolher Pasta de Jogos',
                  subtitle:
                      'OndaDeck importa apenas APKs e ROMs desta pasta (via SAF)',
                  trailing: '[A]',
                  onActivate: () async {
                    await controller.pickAndSyncGamesFolder();
                  },
                ),
                if (hasFolder) ...[
                  const SizedBox(height: 8),
                  _FocusableMenuRow(
                    label: 'Reescanear Pasta',
                    trailing: libraryState.isSyncing
                        ? 'Sincronizando...'
                        : '[R]',
                    onActivate: () async {
                      await controller.refreshInstalledApps();
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: games.isEmpty
                      ? Center(
                          child: Text(
                            hasFolder
                                ? 'Nenhum arquivo APK ou ROM encontrado nesta pasta.'
                                : 'Nenhuma pasta selecionada. Escolha uma pasta com seus APKs ou ROMs.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF8C96A5)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: games.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final game = games[index];
                            final originLabel =
                                game.source == GameSource.scanned
                                ? 'DA PASTA'
                                : 'MANUAL';
                            return _FocusableMenuRow(
                              label: game.title,
                              subtitle:
                                  '${game.platform.toUpperCase()} • $originLabel',
                              trailing: 'Retirar [A]',
                              onActivate: () async {
                                await controller.removeGame(game);
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '[D-Pad] Navegar   [A] Selecionar   [B] Voltar',
                  style: TextStyle(
                    color: Color(0xFF5A6270),
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);
    final settings = state.settings;

    return Actions(
      actions: {
        GamepadBackIntent: CallbackAction<GamepadBackIntent>(
          onInvoke: (_) {
            Navigator.of(context).pop();
            return null;
          },
        ),
      },
      child: Dialog(
        backgroundColor: const Color(0xFF12161C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'CONFIGURAÇÕES DO LAUNCHER',
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontFamily: 'monospace',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FocusableMenuRow(
                          autofocus: true,
                          label: 'Gerenciar Temas & Editor de Cores',
                          trailing: state.theme.name,
                          onActivate: () {
                            Navigator.of(context).pop();
                            showDialog<void>(
                              context: context,
                              builder: (_) => const ThemeManagerDialog(),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        _FocusableMenuRow(
                          label: 'Pasta de Jogos (APKs / ROMs)',
                          trailing: settings.gamesFolderName ?? 'Selecionar',
                          onActivate: () async {
                            await controller.pickAndSyncGamesFolder();
                          },
                        ),
                        const SizedBox(height: 8),
                        _FocusableMenuRow(
                          label: 'Mostrar itens ocultos',
                          trailing: settings.showHidden ? 'ON' : 'OFF',
                          onActivate: () => controller.updateSettings(
                            settings.copyWith(showHidden: !settings.showHidden),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _FocusableMenuRow(
                          label: 'Reduzir animações (shader de fundo)',
                          trailing: settings.reduceMotion ? 'ON' : 'OFF',
                          onActivate: () => controller.updateSettings(
                            settings.copyWith(
                              reduceMotion: !settings.reduceMotion,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _FocusableMenuRow(
                          label: 'Ordenação da biblioteca',
                          trailing: switch (settings.sortMode) {
                            LibrarySortMode.alphabetical => 'A-Z',
                            LibrarySortMode.recentlyPlayed => 'Recentes',
                            LibrarySortMode.mostPlayed => 'Mais Jogados',
                          },
                          onActivate: () {
                            const values = LibrarySortMode.values;
                            final next =
                                values[(settings.sortMode.index + 1) %
                                    values.length];
                            controller.updateSettings(
                              settings.copyWith(sortMode: next),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        _FocusableMenuRow(
                          label: 'Reescanear pasta de jogos',
                          trailing: state.isSyncing
                              ? 'Sincronizando...'
                              : 'Executar',
                          onActivate: () {
                            controller.refreshInstalledApps();
                            Navigator.of(context).pop();
                          },
                        ),
                        const SizedBox(height: 8),
                        _FocusableMenuRow(
                          label: 'Limpar cache de texturas agora',
                          trailing: 'Purgar',
                          onActivate:
                              LifecycleMemoryManager.instance.purgeImageCache,
                        ),
                        const SizedBox(height: 8),
                        _FocusableMenuRow(
                          label: 'Fechar',
                          trailing: '[B]',
                          onActivate: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableMenuRow extends StatefulWidget {
  const _FocusableMenuRow({
    required this.label,
    required this.trailing,
    required this.onActivate,
    this.subtitle,
    this.autofocus = false,
  });

  final String label;
  final String? subtitle;
  final String trailing;
  final VoidCallback onActivate;
  final bool autofocus;

  @override
  State<_FocusableMenuRow> createState() => _FocusableMenuRowState();
}

class _FocusableMenuRowState extends State<_FocusableMenuRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        if (_focused != f) {
          setState(() => _focused = f);
        }
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 120),
          );
        }
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onActivate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? const Color(0xFF00E5FF).withValues(alpha: 0.16)
                : const Color(0xFF1A2029),
            border: Border.all(
              color: _focused
                  ? const Color(0xFF00E5FF)
                  : const Color(0xFF2D3542),
              width: _focused ? 1.8 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: _focused
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFFE6E6E6),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.subtitle case final sub?)
                      Text(
                        sub,
                        style: const TextStyle(
                          color: Color(0xFF7D8796),
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                widget.trailing,
                style: TextStyle(
                  color: _focused
                      ? const Color(0xFF00E5FF)
                      : const Color(0xFF8C96A5),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
