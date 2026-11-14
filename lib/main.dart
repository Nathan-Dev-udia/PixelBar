import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/input/gamepad_input.dart';
import 'core/media/budget_image.dart';
import 'core/memory/lifecycle_memory_manager.dart';
import 'core/state/library_controller.dart';
import 'domain/models/game_item.dart';
import 'domain/models/launcher_settings.dart';
import 'domain/models/platform_models.dart';
import 'themes/console_theme_widget.dart';
import 'themes/data_driven/data_driven_theme_engine.dart';
import 'themes/manager/theme_manager_screen.dart';
import 'themes/metadata/game_metadata_editor_dialog.dart';
import 'themes/update/app_update_dialog.dart';
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

class _OndaDeckShell extends ConsumerStatefulWidget {
  const _OndaDeckShell();

  @override
  ConsumerState<_OndaDeckShell> createState() => _OndaDeckShellState();
}

class _OndaDeckShellState extends ConsumerState<_OndaDeckShell> {
  bool _updateCheckStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runSilentStartupUpdateCheck();
    });
  }

  Future<void> _runSilentStartupUpdateCheck() async {
    if (_updateCheckStarted || !mounted) return;
    _updateCheckStarted = true;
    final updateService = ref.read(appUpdateServiceProvider);
    try {
      await updateService.cleanupStaleUpdates();
      final info = await updateService.checkForUpdate();
      if (!mounted || !info.hasUpdate) return;
      await showDialog<void>(
        context: context,
        builder: (_) =>
            AppUpdateDialog(updateInfo: info, updateService: updateService),
      );
    } catch (_) {
      // Silent startup check must never block launcher startup when offline.
    }
  }

  @override
  Widget build(BuildContext context) {
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

class _ManualAppPickerDialog extends ConsumerStatefulWidget {
  const _ManualAppPickerDialog();

  @override
  ConsumerState<_ManualAppPickerDialog> createState() =>
      _ManualAppPickerDialogState();
}

class _ManualAppPickerDialogState
    extends ConsumerState<_ManualAppPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _filterIndex = 0;
  List<InstalledApp> _installedApps = const [];
  Map<String, String> _iconPaths = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = ref.read(libraryControllerProvider.notifier);
      final apps = [...await controller.loadInstalledApps()];
      apps.sort((a, b) {
        if (a.isGame != b.isGame) return a.isGame ? -1 : 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _installedApps = apps;
        _loading = false;
      });

      final icons = await controller.loadAppIcons([
        for (final app in apps) app.packageName,
      ]);
      if (!mounted || icons.isEmpty) return;
      setState(() {
        _iconPaths = {..._iconPaths, ...icons};
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erro ao listar jogos e aplicativos: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);
    final gamesById = <String, GameItem>{
      for (final c in libraryState.categories)
        for (final g in c.games) g.id: g,
    };

    bool isAppSelected(InstalledApp app) {
      final existing = gamesById[GameItem.idForPackage(app.packageName)];
      return existing != null && !existing.hidden;
    }

    final trimmedQuery = _query.trim().toLowerCase();
    final filteredApps = [
      for (final app in _installedApps)
        if ((_filterIndex == 0 ||
                (_filterIndex == 1 && app.isGame) ||
                (_filterIndex == 2 && isAppSelected(app))) &&
            (trimmedQuery.isEmpty ||
                app.label.toLowerCase().contains(trimmedQuery) ||
                app.packageName.toLowerCase().contains(trimmedQuery)))
          app,
    ];

    return Actions(
      actions: {
        GamepadBackIntent: CallbackAction<GamepadBackIntent>(
          onInvoke: (_) {
            Navigator.of(context).pop();
            return null;
          },
        ),
        GamepadPageIntent: CallbackAction<GamepadPageIntent>(
          onInvoke: (intent) {
            setState(() {
              _filterIndex = (_filterIndex + intent.delta) % 3;
              if (_filterIndex < 0) _filterIndex += 3;
            });
            return null;
          },
        ),
      },
      child: Dialog(
        backgroundColor: const Color(0xFF12161C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 460),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'SELECIONAR JOGOS & APPS INSTALADOS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF00E5FF),
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.14),
                        border: Border.all(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '${gamesById.length} na biblioteca',
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PickerHeaderButton(
                      label: 'Pasta de ROMs',
                      onTap: () async {
                        await controller.pickAndSyncGamesFolder();
                      },
                    ),
                    const SizedBox(width: 6),
                    _PickerHeaderButton(
                      label: 'Fechar [B]',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    style: const TextStyle(
                      color: Color(0xFFE6E6E6),
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF1A2029),
                      hintText: 'Pesquisar jogos ou aplicativos instalados...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF7D8796),
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 18,
                        color: Color(0xFF8C96A5),
                      ),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: Color(0xFF8C96A5),
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF2D3542)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _PickerFilterChip(
                        label: 'Todos (${_installedApps.length})',
                        selected: _filterIndex == 0,
                        onTap: () => setState(() => _filterIndex = 0),
                      ),
                      const SizedBox(width: 8),
                      _PickerFilterChip(
                        label:
                            'Jogos Sugeridos (${_installedApps.where((a) => a.isGame).length})',
                        selected: _filterIndex == 1,
                        onTap: () => setState(() => _filterIndex = 1),
                      ),
                      const SizedBox(width: 8),
                      _PickerFilterChip(
                        label:
                            'Selecionados (${_installedApps.where(isAppSelected).length})',
                        selected: _filterIndex == 2,
                        onTap: () => setState(() => _filterIndex = 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF00E5FF),
                          ),
                        )
                      : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFF5370),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _PickerHeaderButton(
                                label: 'Tentar novamente',
                                onTap: _loadApps,
                              ),
                            ],
                          ),
                        )
                      : filteredApps.isEmpty
                      ? Center(
                          child: Text(
                            _installedApps.isEmpty
                                ? 'Nenhum jogo ou aplicativo encontrado no aparelho.'
                                : _filterIndex == 2
                                ? 'Nenhum jogo selecionado ainda. Marque na aba "Todos".'
                                : 'Nenhum resultado encontrado para "$_query".',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF8C96A5)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filteredApps.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final app = filteredApps[index];
                            final gameId = GameItem.idForPackage(
                              app.packageName,
                            );
                            final existing = gamesById[gameId];
                            final selected =
                                existing != null && !existing.hidden;
                            final iconPath =
                                existing?.media.iconPath ??
                                _iconPaths[app.packageName];

                            return _InstalledAppPickerRow(
                              autofocus: index == 0,
                              app: app,
                              iconPath: iconPath,
                              selected: selected,
                              onToggle: () async {
                                if (selected) {
                                  await controller.removeGame(existing);
                                } else {
                                  await controller.addManualApp(app);
                                }
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '[D-Pad] Navegar   [A] Marcar/Desmarcar   [L1/R1] Filtrar   [B] Voltar',
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

class _PickerHeaderButton extends StatelessWidget {
  const _PickerHeaderButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2029),
          border: Border.all(color: const Color(0xFF2D3542)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFE6E6E6),
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PickerFilterChip extends StatelessWidget {
  const _PickerFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00E5FF).withValues(alpha: 0.18)
              : const Color(0xFF1A2029),
          border: Border.all(
            color: selected ? const Color(0xFF00E5FF) : const Color(0xFF2D3542),
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF00E5FF) : const Color(0xFF8C96A5),
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _InstalledAppPickerRow extends StatefulWidget {
  const _InstalledAppPickerRow({
    required this.app,
    required this.iconPath,
    required this.selected,
    required this.onToggle,
    this.autofocus = false,
  });

  final InstalledApp app;
  final String? iconPath;
  final bool selected;
  final VoidCallback onToggle;
  final bool autofocus;

  @override
  State<_InstalledAppPickerRow> createState() => _InstalledAppPickerRowState();
}

class _InstalledAppPickerRowState extends State<_InstalledAppPickerRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final activeBorder = _focused
        ? const Color(0xFF00E5FF)
        : (widget.selected
              ? const Color(0xFF00E5FF).withValues(alpha: 0.55)
              : const Color(0xFF2D3542));
    final kindLabel = widget.app.isGame ? 'JOGO DETECTADO' : 'APLICATIVO';

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
            widget.onToggle();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _focused
                ? const Color(0xFF00E5FF).withValues(alpha: 0.16)
                : (widget.selected
                      ? const Color(0xFF00E5FF).withValues(alpha: 0.07)
                      : const Color(0xFF1A2029)),
            border: Border.all(
              color: activeBorder,
              width: _focused ? 1.8 : 1.0,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                widget.selected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 20,
                color: widget.selected
                    ? const Color(0xFF00E5FF)
                    : const Color(0xFF7D8796),
              ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BudgetImage.file(
                  widget.iconPath,
                  width: 38,
                  height: 38,
                  placeholder: Container(
                    width: 38,
                    height: 38,
                    color: const Color(0xFF242B36),
                    child: Icon(
                      widget.app.isGame
                          ? Icons.sports_esports_rounded
                          : Icons.android_rounded,
                      size: 20,
                      color: widget.app.isGame
                          ? const Color(0xFF00E5FF)
                          : const Color(0xFF8C96A5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.app.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _focused
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFFE6E6E6),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$kindLabel • ${widget.app.packageName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF7D8796),
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.selected ? '✓ Na Biblioteca [A]' : '+ Adicionar [A]',
                style: TextStyle(
                  color: widget.selected
                      ? const Color(0xFF10B981)
                      : (_focused
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFF8C96A5)),
                  fontFamily: 'monospace',
                  fontSize: 11,
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

class _SettingsDialog extends ConsumerStatefulWidget {
  const _SettingsDialog();

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  bool _checkingUpdates = false;
  String? _updateStatus;

  Future<void> _checkUpdatesManually() async {
    if (_checkingUpdates) return;
    setState(() {
      _checkingUpdates = true;
      _updateStatus = 'Verificando...';
    });

    final updateService = ref.read(appUpdateServiceProvider);
    try {
      final info = await updateService.checkForUpdate();
      if (!mounted) return;
      if (info.hasUpdate) {
        final nav = Navigator.of(context);
        nav.pop();
        await showDialog<void>(
          context: nav.context,
          builder: (_) =>
              AppUpdateDialog(updateInfo: info, updateService: updateService),
        );
        return;
      }
      setState(() {
        _checkingUpdates = false;
        _updateStatus = info.latestTag.isEmpty
            ? 'Sem releases'
            : 'Atualizado (v${info.currentVersion})';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingUpdates = false;
        _updateStatus = 'Falha ao consultar';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                          label: 'Selecionar Jogos e Apps Instalados',
                          trailing: '${state.totalGames} jogos',
                          onActivate: () {
                            final nav = Navigator.of(context);
                            nav.pop();
                            showDialog<void>(
                              context: nav.context,
                              builder: (_) => const _ManualAppPickerDialog(),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        _FocusableMenuRow(
                          label: 'Pasta de ROMs (Emuladores)',
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
                          label: 'Verificar Atualizações',
                          trailing: _checkingUpdates
                              ? 'Verificando...'
                              : (_updateStatus ?? 'GitHub Releases'),
                          onActivate: _checkUpdatesManually,
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
    this.autofocus = false,
  });

  final String label;
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
