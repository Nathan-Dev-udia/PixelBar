import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/input/gamepad_input.dart';
import 'core/memory/lifecycle_memory_manager.dart';
import 'core/state/library_controller.dart';
import 'domain/models/game_item.dart';
import 'domain/models/launcher_settings.dart';
import 'domain/models/platform_models.dart';
import 'themes/console_theme_widget.dart';
import 'themes/data_driven/data_driven_theme_engine.dart';
import 'themes/manager/theme_manager_screen.dart';
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

  Future<void> _openSettings(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const _SettingsDialog(),
  );

  Future<void> _openThemeManager(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const ThemeManagerDialog(),
  );
}

class _ManualAppPickerDialog extends ConsumerStatefulWidget {
  const _ManualAppPickerDialog();

  @override
  ConsumerState<_ManualAppPickerDialog> createState() =>
      _ManualAppPickerDialogState();
}

class _ManualAppPickerDialogState
    extends ConsumerState<_ManualAppPickerDialog> {
  late Future<List<InstalledApp>> _appsFuture;
  GameKind _selectedKind = GameKind.androidNative;

  @override
  void initState() {
    super.initState();
    _appsFuture = ref
        .read(launcherGatewayProvider)
        .getInstalledApps(gamesOnly: false);
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryControllerProvider);
    final existingById = <String, GameItem>{
      for (final c in libraryState.categories)
        for (final g in c.games) g.id: g,
    };

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
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'ADICIONAR APP INSTALADO',
                        style: TextStyle(
                          color: Color(0xFF00E5FF),
                          fontFamily: 'monospace',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _FocusableMenuRow(
                      autofocus: true,
                      label: _selectedKind == GameKind.recompPort
                          ? 'Tipo: Port Recomp'
                          : 'Tipo: Android Nativo',
                      trailing: 'Trocar [A]',
                      compact: true,
                      onActivate: () {
                        setState(() {
                          _selectedKind =
                              _selectedKind == GameKind.androidNative
                              ? GameKind.recompPort
                              : GameKind.androidNative;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<InstalledApp>>(
                    future: _appsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final apps = snapshot.data ?? const [];
                      if (apps.isEmpty) {
                        return const Center(
                          child: Text(
                            'Nenhum aplicativo encontrado no dispositivo.',
                            style: TextStyle(color: Color(0xFF8C96A5)),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: apps.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final app = apps[index];
                          final existing =
                              existingById[GameItem.idForPackage(
                                app.packageName,
                              )];
                          final isAdded = existing != null;
                          return _FocusableMenuRow(
                            label: app.label,
                            subtitle: isAdded
                                ? '${app.packageName} • ADICIONADO'
                                : '${app.packageName}${app.isGame ? ' • GAME' : ''}',
                            trailing: isAdded ? 'Retirar [A]' : 'Adicionar [A]',
                            onActivate: () async {
                              final notifier = ref.read(
                                libraryControllerProvider.notifier,
                              );
                              if (isAdded) {
                                await notifier.removeGame(existing);
                              } else {
                                await notifier.addManualApp(
                                  app,
                                  kind: _selectedKind,
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              }
                            },
                          );
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
                          label: 'Importar jogos Android automaticamente',
                          trailing: settings.autoImportGames ? 'ON' : 'OFF',
                          onActivate: () => controller.updateSettings(
                            settings.copyWith(
                              autoImportGames: !settings.autoImportGames,
                            ),
                          ),
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
                          label: 'Reescanear aplicativos instalados',
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
    this.compact = false,
  });

  final String label;
  final String? subtitle;
  final String trailing;
  final VoidCallback onActivate;
  final bool autofocus;
  final bool compact;

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
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 12 : 14,
            vertical: widget.compact ? 6 : 10,
          ),
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
            mainAxisSize: widget.compact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (widget.compact)
                Text(
                  widget.label,
                  style: TextStyle(
                    color: _focused
                        ? const Color(0xFF00E5FF)
                        : const Color(0xFFE6E6E6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
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
