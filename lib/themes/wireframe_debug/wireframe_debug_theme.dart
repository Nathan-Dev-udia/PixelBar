import 'package:flutter/material.dart';

import '../../core/input/gamepad_input.dart';
import '../../core/media/budget_image.dart';
import '../../core/rendering/shader_background.dart';
import '../../domain/models/game_item.dart';
import '../../domain/models/library_state.dart';
import '../console_theme_widget.dart';

/// Minimalist diagnostic console theme ("10-foot experience") used to validate:
/// 1. Installed package listing & manual addition
/// 2. 100% D-Pad / Gamepad navigation (FocusNode + Shortcuts + Actions)
/// 3. Game launch & hard memory hibernation
class WireframeDebugTheme extends ConsoleThemeWidget {
  const WireframeDebugTheme({
    super.key,
    required super.state,
    required super.onSelectGame,
    required super.onLaunchGame,
    required super.onOpenSettings,
    super.onAddApps,
    super.onRemoveGame,
    super.onToggleFavorite,
    super.onRescan,
    super.onOpenThemeManager,
  });

  @override
  State<WireframeDebugTheme> createState() => _WireframeDebugThemeState();
}

class _WireframeDebugThemeState extends State<WireframeDebugTheme> {
  int _categoryIndex = 0;
  String? _activeGameId;
  final Map<String, FocusNode> _tileNodes = {};
  final FocusNode _emptyAddNode = FocusNode(debugLabel: 'wireframe_empty_add');
  final FocusNode _emptyRescanNode = FocusNode(
    debugLabel: 'wireframe_empty_rescan',
  );
  bool _pendingFocusSync = true;

  @override
  void initState() {
    super.initState();
    _syncSelectionFromState(requestFocus: true);
  }

  @override
  void didUpdateWidget(WireframeDebugTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    final categoriesChanged =
        oldWidget.state.categories != widget.state.categories;
    final focusedChanged =
        oldWidget.state.focusedGameId != widget.state.focusedGameId;
    if (categoriesChanged || focusedChanged) {
      _syncSelectionFromState(requestFocus: categoriesChanged);
    }
  }

  @override
  void dispose() {
    for (final node in _tileNodes.values) {
      node.dispose();
    }
    _tileNodes.clear();
    _emptyAddNode.dispose();
    _emptyRescanNode.dispose();
    super.dispose();
  }

  List<GameCategory> get _categories => widget.state.categories;

  GameCategory? get _activeCategory {
    if (_categories.isEmpty) return null;
    final clamped = _categoryIndex.clamp(0, _categories.length - 1);
    return _categories[clamped];
  }

  GameItem? get _selectedGame {
    final cat = _activeCategory;
    if (cat == null || cat.games.isEmpty) return null;
    final id = _activeGameId ?? widget.state.focusedGameId;
    if (id != null) {
      for (final g in cat.games) {
        if (g.id == id) return g;
      }
    }
    return cat.games.first;
  }

  FocusNode _nodeFor(GameItem game) => _tileNodes.putIfAbsent(
    game.id,
    () => FocusNode(debugLabel: 'tile:${game.id}'),
  );

  void _syncSelectionFromState({bool requestFocus = false}) {
    final cats = _categories;
    if (cats.isEmpty) {
      _categoryIndex = 0;
      _activeGameId = null;
      _pruneUnusedNodes(const {});
      if (requestFocus) _scheduleInitialFocus();
      return;
    }

    _categoryIndex = _categoryIndex.clamp(0, cats.length - 1);

    final targetId = widget.state.focusedGameId ?? _activeGameId;
    if (targetId != null) {
      final currentCat = cats[_categoryIndex];
      if (currentCat.games.any((g) => g.id == targetId)) {
        _activeGameId = targetId;
      } else {
        var found = false;
        for (var i = 0; i < cats.length; i++) {
          if (cats[i].games.any((g) => g.id == targetId)) {
            _categoryIndex = i;
            _activeGameId = targetId;
            found = true;
            break;
          }
        }
        if (!found) {
          _activeGameId = currentCat.games.isNotEmpty
              ? currentCat.games.first.id
              : null;
        }
      }
    } else {
      final currentCat = cats[_categoryIndex];
      _activeGameId = currentCat.games.isNotEmpty
          ? currentCat.games.first.id
          : null;
    }

    final liveIds = {for (final c in cats) ...c.games.map((g) => g.id)};
    _pruneUnusedNodes(liveIds);

    if (requestFocus) {
      _scheduleInitialFocus();
    }
  }

  void _pruneUnusedNodes(Set<String> liveIds) {
    final dead = _tileNodes.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in dead) {
      _tileNodes.remove(id)?.dispose();
    }
  }

  void _scheduleInitialFocus() {
    _pendingFocusSync = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pendingFocusSync) return;
      _pendingFocusSync = false;
      final selected = _selectedGame;
      if (selected != null) {
        final node = _nodeFor(selected);
        if (node.canRequestFocus && !node.hasFocus) {
          node.requestFocus();
        }
      } else if (_emptyAddNode.canRequestFocus) {
        _emptyAddNode.requestFocus();
      }
    });
  }

  void _switchCategory(int delta) {
    final cats = _categories;
    if (cats.isEmpty) return;
    final nextIndex = (_categoryIndex + delta) % cats.length;
    final wrapped = nextIndex < 0 ? nextIndex + cats.length : nextIndex;
    if (wrapped == _categoryIndex) return;
    setState(() {
      _categoryIndex = wrapped;
      final games = cats[wrapped].games;
      _activeGameId = games.isNotEmpty ? games.first.id : null;
    });
    final selected = _selectedGame;
    if (selected != null) {
      widget.onSelectGame(selected);
    }
    _scheduleInitialFocus();
  }

  void _selectCategoryAt(int index) {
    if (index < 0 || index >= _categories.length || index == _categoryIndex) {
      return;
    }
    setState(() {
      _categoryIndex = index;
      final games = _categories[index].games;
      _activeGameId = games.isNotEmpty ? games.first.id : null;
    });
    final selected = _selectedGame;
    if (selected != null) {
      widget.onSelectGame(selected);
    }
    _scheduleInitialFocus();
  }

  @override
  Widget build(BuildContext context) {
    final manifest = widget.state.theme;
    final bgColor = Color(manifest.color('background', 0xFF0B0D10));
    final surfaceColor = Color(manifest.color('surface', 0xFF12161C));
    final fgColor = Color(manifest.color('foreground', 0xFFE6E6E6));
    final mutedColor = Color(manifest.color('muted', 0xFF5A6270));
    final accentColor = Color(manifest.color('accent', 0xFF00E5FF));
    final favoriteColor = Color(manifest.color('favorite', 0xFFFFC400));
    final dangerColor = Color(manifest.color('danger', 0xFFFF5370));

    final tileWidth = manifest.option<int>('tileWidth', 148).toDouble();
    final tileHeight = manifest.option<int>('tileHeight', 148).toDouble();
    final iconSize = manifest.option<int>('iconSize', 72).toDouble();
    final showDebugPanel = manifest.option<bool>('showDebugPanel', true);

    final selected = _selectedGame;

    return Actions(
      actions: {
        GamepadPageIntent: CallbackAction<GamepadPageIntent>(
          onInvoke: (intent) {
            _switchCategory(intent.delta);
            return null;
          },
        ),
        GamepadContextIntent: CallbackAction<GamepadContextIntent>(
          onInvoke: (_) {
            widget.onAddApps?.call();
            return null;
          },
        ),
        GamepadAltIntent: CallbackAction<GamepadAltIntent>(
          onInvoke: (_) {
            if (selected != null) widget.onToggleFavorite?.call(selected);
            return null;
          },
        ),
        GamepadMenuIntent: CallbackAction<GamepadMenuIntent>(
          onInvoke: (_) {
            widget.onOpenSettings();
            return null;
          },
        ),
        GamepadSelectIntent: CallbackAction<GamepadSelectIntent>(
          onInvoke: (_) {
            widget.onRescan?.call();
            return null;
          },
        ),
      },
      child: Scaffold(
        backgroundColor: bgColor,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (!widget.state.settings.reduceMotion)
              Positioned.fill(
                child: ShaderBackground(
                  colorA: bgColor,
                  colorB: surfaceColor,
                  animate: !widget.state.isLaunching,
                ),
              ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopHudBar(
                    categories: _categories,
                    activeIndex: _categoryIndex,
                    isSyncing: widget.state.isSyncing,
                    totalGames: widget.state.totalGames,
                    fgColor: fgColor,
                    mutedColor: mutedColor,
                    accentColor: accentColor,
                    surfaceColor: surfaceColor,
                    onSelectTab: _selectCategoryAt,
                  ),
                  if (widget.state.errorMessage case final error?)
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: dangerColor.withValues(alpha: 0.16),
                        border: Border.all(color: dangerColor),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        error,
                        style: TextStyle(
                          color: dangerColor,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildLibraryArea(
                            surfaceColor: surfaceColor,
                            fgColor: fgColor,
                            mutedColor: mutedColor,
                            accentColor: accentColor,
                            favoriteColor: favoriteColor,
                            tileWidth: tileWidth,
                            tileHeight: tileHeight,
                            iconSize: iconSize,
                          ),
                        ),
                        if (showDebugPanel)
                          SizedBox(
                            width: 300,
                            child: _DebugInspectorPanel(
                              game: selected,
                              state: widget.state,
                              surfaceColor: surfaceColor,
                              fgColor: fgColor,
                              mutedColor: mutedColor,
                              accentColor: accentColor,
                              favoriteColor: favoriteColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _BottomLegendBar(
                    fgColor: fgColor,
                    mutedColor: mutedColor,
                    accentColor: accentColor,
                    surfaceColor: surfaceColor,
                    hasSelectedGame: selected != null,
                    onAddApps: widget.onAddApps,
                    onRemoveGame:
                        selected == null || widget.onRemoveGame == null
                        ? null
                        : () => widget.onRemoveGame!(selected),
                    onToggleFavorite:
                        selected == null || widget.onToggleFavorite == null
                        ? null
                        : () => widget.onToggleFavorite!(selected),
                    onRescan: widget.onRescan,
                    onOpenSettings: widget.onOpenSettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryArea({
    required Color surfaceColor,
    required Color fgColor,
    required Color mutedColor,
    required Color accentColor,
    required Color favoriteColor,
    required double tileWidth,
    required double tileHeight,
    required double iconSize,
  }) {
    if (widget.state.status == LibraryStatus.loading) {
      return Center(
        child: Text(
          'CARREGANDO BIBLIOTECA...',
          style: TextStyle(
            color: accentColor,
            fontFamily: 'monospace',
            letterSpacing: 1.4,
          ),
        ),
      );
    }

    final cat = _activeCategory;
    if (cat == null || cat.games.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: 0.9),
              border: Border.all(color: mutedColor.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sports_esports_outlined,
                  size: 48,
                  color: accentColor,
                ),
                const SizedBox(height: 12),
                Text(
                  'Nenhum jogo indexado ainda',
                  style: TextStyle(
                    color: fgColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Adicione manualmente apps/ports instalados ou execute uma nova varredura.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedColor, fontSize: 13),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    _WireframeActionButton(
                      focusNode: _emptyAddNode,
                      label: 'Adicionar App',
                      icon: Icons.add_box_outlined,
                      accentColor: accentColor,
                      fgColor: fgColor,
                      surfaceColor: surfaceColor,
                      onActivate: widget.onAddApps,
                    ),
                    _WireframeActionButton(
                      focusNode: _emptyRescanNode,
                      label: 'Reescanear',
                      icon: Icons.refresh,
                      accentColor: accentColor,
                      fgColor: fgColor,
                      surfaceColor: surfaceColor,
                      onActivate: widget.onRescan,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(24, 14, 16, 16),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: tileWidth + 24,
          mainAxisExtent: tileHeight + 12,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: cat.games.length,
        itemBuilder: (context, index) {
          final game = cat.games[index];
          final node = _nodeFor(game);
          final isSelected = _activeGameId == game.id;
          return FocusTraversalOrder(
            order: NumericFocusOrder(index.toDouble()),
            child: _GameTile(
              game: game,
              focusNode: node,
              isSelected: isSelected,
              iconSize: iconSize,
              surfaceColor: surfaceColor,
              fgColor: fgColor,
              mutedColor: mutedColor,
              accentColor: accentColor,
              favoriteColor: favoriteColor,
              onFocused: () {
                if (_activeGameId != game.id) {
                  setState(() => _activeGameId = game.id);
                }
                widget.onSelectGame(game);
              },
              onActivate: () => widget.onLaunchGame(game),
            ),
          );
        },
      ),
    );
  }
}

class _TopHudBar extends StatelessWidget {
  const _TopHudBar({
    required this.categories,
    required this.activeIndex,
    required this.isSyncing,
    required this.totalGames,
    required this.fgColor,
    required this.mutedColor,
    required this.accentColor,
    required this.surfaceColor,
    required this.onSelectTab,
  });

  final List<GameCategory> categories;
  final int activeIndex;
  final bool isSyncing;
  final int totalGames;
  final Color fgColor;
  final Color mutedColor;
  final Color accentColor;
  final Color surfaceColor;
  final ValueChanged<int> onSelectTab;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: mutedColor.withValues(alpha: 0.25)),
          ),
        ),
        child: Row(
          children: [
            Text(
              'ONDADECK // WIREFRAME',
              style: TextStyle(
                color: accentColor,
                fontFamily: 'monospace',
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (categories.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '[L1]',
                          style: TextStyle(
                            color: mutedColor,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    for (var i = 0; i < categories.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => onSelectTab(i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: i == activeIndex
                                  ? accentColor.withValues(alpha: 0.16)
                                  : surfaceColor,
                              border: Border.all(
                                color: i == activeIndex
                                    ? accentColor
                                    : mutedColor.withValues(alpha: 0.35),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${categories[i].title.toUpperCase()} (${categories[i].games.length})',
                              style: TextStyle(
                                color: i == activeIndex ? accentColor : fgColor,
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: i == activeIndex
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (categories.isNotEmpty)
                      Text(
                        '[R1]',
                        style: TextStyle(
                          color: mutedColor,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (isSyncing)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accentColor,
                  ),
                ),
              ),
            Text(
              'JOGOS: $totalGames',
              style: TextStyle(
                color: mutedColor,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameTile extends StatefulWidget {
  const _GameTile({
    required this.game,
    required this.focusNode,
    required this.isSelected,
    required this.iconSize,
    required this.surfaceColor,
    required this.fgColor,
    required this.mutedColor,
    required this.accentColor,
    required this.favoriteColor,
    required this.onFocused,
    required this.onActivate,
  });

  final GameItem game;
  final FocusNode focusNode;
  final bool isSelected;
  final double iconSize;
  final Color surfaceColor;
  final Color fgColor;
  final Color mutedColor;
  final Color accentColor;
  final Color favoriteColor;
  final VoidCallback onFocused;
  final VoidCallback onActivate;

  @override
  State<_GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<_GameTile> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _hasFocus || widget.isSelected;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        if (_hasFocus != focused) {
          setState(() => _hasFocus = focused);
        }
        if (focused) {
          widget.onFocused();
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
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
        onTap: () {
          widget.focusNode.requestFocus();
          widget.onActivate();
        },
        child: AnimatedScale(
          scale: _hasFocus ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _hasFocus
                  ? widget.accentColor.withValues(alpha: 0.14)
                  : widget.surfaceColor.withValues(alpha: 0.85),
              border: Border.all(
                color: _hasFocus
                    ? widget.accentColor
                    : (highlighted
                          ? widget.accentColor.withValues(alpha: 0.45)
                          : widget.mutedColor.withValues(alpha: 0.3)),
                width: _hasFocus ? 2.2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BudgetImage.file(
                        widget.game.media.coverPath ??
                            widget.game.media.iconPath,
                        width: widget.iconSize,
                        height: widget.iconSize,
                        placeholder: Container(
                          width: widget.iconSize,
                          height: widget.iconSize,
                          color: widget.mutedColor.withValues(alpha: 0.16),
                          child: Icon(
                            switch (widget.game.kind) {
                              GameKind.recompPort => Icons.memory,
                              GameKind.emulated => Icons.videogame_asset,
                              GameKind.androidNative => Icons.android,
                            },
                            size: widget.iconSize * 0.48,
                            color: _hasFocus
                                ? widget.accentColor
                                : widget.mutedColor,
                          ),
                        ),
                      ),
                    ),
                    if (widget.game.favorite)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Icon(
                          Icons.star,
                          size: 16,
                          color: widget.favoriteColor,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.game.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _hasFocus ? widget.accentColor : widget.fgColor,
                    fontSize: 12,
                    fontWeight: _hasFocus ? FontWeight.bold : FontWeight.w500,
                    height: 1.15,
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

class _DebugInspectorPanel extends StatelessWidget {
  const _DebugInspectorPanel({
    required this.game,
    required this.state,
    required this.surfaceColor,
    required this.fgColor,
    required this.mutedColor,
    required this.accentColor,
    required this.favoriteColor,
  });

  final GameItem? game;
  final LibraryState state;
  final Color surfaceColor;
  final Color fgColor;
  final Color mutedColor;
  final Color accentColor;
  final Color favoriteColor;

  @override
  Widget build(BuildContext context) {
    final cache = PaintingBinding.instance.imageCache;
    final usedMb = (cache.currentSizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final maxMb = (cache.maximumSizeBytes / (1024 * 1024)).toStringAsFixed(0);

    return ExcludeFocus(
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 14, 24, 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: 0.9),
          border: Border.all(color: mutedColor.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TELEMETRIA & DETALHES',
              style: TextStyle(
                color: accentColor,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _kv('TEX CACHE', '$usedMb / $maxMb MB (${cache.currentSize} imgs)'),
            _kv('TEMA', '${state.theme.name} (${state.theme.engine})'),
            _kv(
              'ESTADO',
              state.isLaunching
                  ? 'HIBERNANDO / INICIANDO'
                  : state.status.name.toUpperCase(),
            ),
            Divider(color: mutedColor.withValues(alpha: 0.25), height: 22),
            if (game == null)
              Text(
                'Nenhum item selecionado.',
                style: TextStyle(
                  color: mutedColor,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              game!.title,
                              style: TextStyle(
                                color: fgColor,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (game!.favorite)
                            Icon(Icons.star, size: 18, color: favoriteColor),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _kv('ID', game!.id),
                      _kv('TIPO', game!.kind.name),
                      _kv('ORIGEM', game!.source.name),
                      _kv('PLATAFORMA', game!.platform.toUpperCase()),
                      _kv('LAUNCH', game!.launch.toString()),
                      _kv('EXECUÇÕES', '${game!.playCount}'),
                      _kv(
                        'ÚLTIMO USO',
                        game!.lastPlayedAt?.toLocal().toString().substring(
                              0,
                              16,
                            ) ??
                            'Nunca',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          k,
          style: TextStyle(
            color: mutedColor,
            fontFamily: 'monospace',
            fontSize: 10,
          ),
        ),
        Text(
          v,
          style: TextStyle(
            color: fgColor,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class _BottomLegendBar extends StatelessWidget {
  const _BottomLegendBar({
    required this.fgColor,
    required this.mutedColor,
    required this.accentColor,
    required this.surfaceColor,
    required this.hasSelectedGame,
    required this.onAddApps,
    required this.onRemoveGame,
    required this.onToggleFavorite,
    required this.onRescan,
    required this.onOpenSettings,
  });

  final Color fgColor;
  final Color mutedColor;
  final Color accentColor;
  final Color surfaceColor;
  final bool hasSelectedGame;
  final VoidCallback? onAddApps;
  final VoidCallback? onRemoveGame;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onRescan;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: 0.9),
          border: Border(
            top: BorderSide(color: mutedColor.withValues(alpha: 0.25)),
          ),
        ),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                if (hasSelectedGame)
                  _LegendPill(
                    keyLabel: 'A',
                    label: 'Iniciar',
                    accentColor: accentColor,
                    fgColor: fgColor,
                  ),
                if (onAddApps != null)
                  _LegendPill(
                    keyLabel: 'X',
                    label: '+App Manual',
                    accentColor: accentColor,
                    fgColor: fgColor,
                    onTap: onAddApps,
                  ),
                if (onToggleFavorite != null)
                  _LegendPill(
                    keyLabel: 'Y',
                    label: 'Favorito',
                    accentColor: accentColor,
                    fgColor: fgColor,
                    onTap: onToggleFavorite,
                  ),
                if (onRemoveGame != null)
                  _LegendPill(
                    keyLabel: 'DEL',
                    label: 'Retirar',
                    accentColor: accentColor,
                    fgColor: fgColor,
                    onTap: onRemoveGame,
                  ),
                _LegendPill(
                  keyLabel: 'L1/R1',
                  label: 'Categoria',
                  accentColor: accentColor,
                  fgColor: fgColor,
                ),
                if (onRescan != null)
                  _LegendPill(
                    keyLabel: 'SELECT',
                    label: 'Rescan',
                    accentColor: accentColor,
                    fgColor: fgColor,
                    onTap: onRescan,
                  ),
                _LegendPill(
                  keyLabel: 'START',
                  label: 'Config',
                  accentColor: accentColor,
                  fgColor: fgColor,
                  onTap: onOpenSettings,
                ),
              ],
            ),
            Text(
              'Onda Pixel',
              style: TextStyle(
                color: mutedColor,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  const _LegendPill({
    required this.keyLabel,
    required this.label,
    required this.accentColor,
    required this.fgColor,
    this.onTap,
  });

  final String keyLabel;
  final String label;
  final Color accentColor;
  final Color fgColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: accentColor),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            keyLabel,
            style: TextStyle(
              color: accentColor,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: fgColor, fontSize: 12)),
      ],
    );
    return onTap == null ? child : GestureDetector(onTap: onTap, child: child);
  }
}

class _WireframeActionButton extends StatefulWidget {
  const _WireframeActionButton({
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.fgColor,
    required this.surfaceColor,
    required this.onActivate,
  });

  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final Color accentColor;
  final Color fgColor;
  final Color surfaceColor;
  final VoidCallback? onActivate;

  @override
  State<_WireframeActionButton> createState() => _WireframeActionButtonState();
}

class _WireframeActionButtonState extends State<_WireframeActionButton> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _hasFocus = f),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onActivate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _hasFocus
                ? widget.accentColor.withValues(alpha: 0.2)
                : widget.surfaceColor,
            border: Border.all(
              color: _hasFocus
                  ? widget.accentColor
                  : widget.fgColor.withValues(alpha: 0.3),
              width: _hasFocus ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: _hasFocus ? widget.accentColor : widget.fgColor,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: _hasFocus ? widget.accentColor : widget.fgColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
