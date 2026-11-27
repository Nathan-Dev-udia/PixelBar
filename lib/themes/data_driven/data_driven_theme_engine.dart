import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/input/gamepad_input.dart';
import '../../core/media/budget_image.dart';
import '../../core/rendering/shader_background.dart';
import '../../domain/models/game_item.dart';
import '../../domain/models/library_state.dart';
import '../../domain/models/theme_manifest.dart';
import '../console_theme_widget.dart';
import 'ps3_xmb_view.dart';

/// Declarative interpreter for community & built-in `layout.json` themes.
///
/// Translates [ThemeLayoutNode] trees into native Flutter widgets with
/// `{{selectedGame.*}}` / `{{theme.*}}` data-binding, enforced `BudgetImage`
/// texture budgets, GLSL shader backgrounds, and 100% D-Pad/Gamepad focus.
class DataDrivenThemeEngine extends ConsoleThemeWidget {
  const DataDrivenThemeEngine({
    super.key,
    required super.state,
    required super.onSelectGame,
    required super.onLaunchGame,
    required super.onOpenSettings,
    super.onAddApps,
    super.onRemoveGame,
    super.onEditGame,
    super.onToggleFavorite,
    super.onRescan,
    super.onOpenThemeManager,
  });

  @override
  State<DataDrivenThemeEngine> createState() => _DataDrivenThemeEngineState();

  /// Evaluates `{{...}}` bindings against the current snapshot.
  static String resolveBindings(
    String input, {
    required LibraryState state,
    required GameCategory? category,
    required GameItem? game,
  }) {
    if (!input.contains('{{')) return input;
    return input.replaceAllMapped(_bindingPattern, (match) {
      final token = match[1]!.trim();
      if (token.startsWith('theme.')) {
        final key = token.substring('theme.'.length);
        return switch (key) {
          'id' => state.theme.id,
          'name' => state.theme.name,
          'author' => state.theme.author,
          'version' => state.theme.version,
          _ =>
            state.theme.colors.containsKey(key)
                ? ThemeManifest.formatColorHex(state.theme.colors[key]!)
                : '',
        };
      }
      return switch (token) {
        'selectedGame.title' => game?.title ?? 'Nenhum jogo selecionado',
        'selectedGame.clearLogo' => game?.media.logoPath ?? '',
        'selectedGame.heroBanner' =>
          game?.media.bannerPath ?? game?.media.backgroundPath ?? '',
        'selectedGame.cover' =>
          game?.media.coverPath ?? game?.media.iconPath ?? '',
        'selectedGame.icon' => game?.media.iconPath ?? '',
        'selectedGame.background' =>
          game?.media.backgroundPath ?? game?.media.bannerPath ?? '',
        'selectedGame.platform' => game?.platform.toUpperCase() ?? '-',
        'selectedGame.kind' => game?.kind.name ?? '-',
        'selectedGame.description' => game?.description ?? '',
        'selectedGame.developer' => game?.developer ?? '',
        'selectedGame.releaseYear' => game?.releaseYear ?? '',
        'selectedGame.playCount' => '${game?.playCount ?? 0}',
        'selectedGame.lastPlayed' =>
          game?.lastPlayedAt?.toLocal().toString().substring(0, 16) ?? 'Nunca',
        'selectedCategory.title' => category?.title ?? 'Biblioteca',
        'selectedCategory.count' => '${category?.games.length ?? 0}',
        'library.totalGames' => '${state.totalGames}',
        _ => '',
      };
    });
  }

  static final RegExp _bindingPattern = RegExp(r'\{\{([^}]+)\}\}');
}

class _DataDrivenThemeEngineState extends State<DataDrivenThemeEngine> {
  int _categoryIndex = 0;
  String? _activeGameId;
  final Map<String, FocusNode> _tileNodes = {};
  final FocusNode _emptyAddNode = FocusNode(debugLabel: 'dd_empty_add');
  final FocusNode _emptyRescanNode = FocusNode(debugLabel: 'dd_empty_rescan');
  bool _pendingFocusSync = true;

  @override
  void initState() {
    super.initState();
    _syncSelectionFromState(requestFocus: true);
  }

  @override
  void didUpdateWidget(DataDrivenThemeEngine oldWidget) {
    super.didUpdateWidget(oldWidget);
    final statusChanged = oldWidget.state.status != widget.state.status;
    final themeChanged = oldWidget.state.theme.id != widget.state.theme.id;
    final categoriesChanged =
        oldWidget.state.categories != widget.state.categories;
    final focusedChanged =
        oldWidget.state.focusedGameId != widget.state.focusedGameId;
    if (statusChanged || themeChanged || categoriesChanged || focusedChanged) {
      _syncSelectionFromState(
        requestFocus: statusChanged || themeChanged || categoriesChanged,
      );
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
    return _categories[_categoryIndex.clamp(0, _categories.length - 1)];
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
    () => FocusNode(debugLabel: 'dd_tile:${game.id}'),
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

  void _scheduleInitialFocus({int retries = 3}) {
    _pendingFocusSync = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pendingFocusSync) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _pendingFocusSync = false;
        return;
      }
      final selected = _selectedGame;
      final targetNode = selected != null ? _nodeFor(selected) : _emptyAddNode;
      if (targetNode.context != null && targetNode.canRequestFocus) {
        _pendingFocusSync = false;
        if (!targetNode.hasFocus) {
          targetNode.requestFocus();
        }
      } else if (retries > 0) {
        _scheduleInitialFocus(retries: retries - 1);
      } else {
        _pendingFocusSync = false;
      }
    });
  }

  void _switchCategory(int delta) {
    final cats = _categories;
    if (cats.isEmpty) return;
    final next = (_categoryIndex + delta) % cats.length;
    final wrapped = next < 0 ? next + cats.length : next;
    if (wrapped == _categoryIndex) return;
    _selectCategoryAt(wrapped);
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
    final rootNode = manifest.layout ?? ThemeLayoutNode.defaultConsoleLayout();
    final bgColor = _resolveColor(
      null,
      manifest,
      const Color(0xFF0B0D10),
      tokenFallback: 'background',
    );
    final surfaceColor = _resolveColor(
      null,
      manifest,
      const Color(0xFF12161C),
      tokenFallback: 'surface',
    );
    final accentColor = _resolveColor(
      null,
      manifest,
      const Color(0xFF00E5FF),
      tokenFallback: 'accent',
    );
    final fgColor = _resolveColor(
      null,
      manifest,
      const Color(0xFFE6E6E6),
      tokenFallback: 'textPrimary',
      secondaryToken: 'foreground',
    );
    final mutedColor = _resolveColor(
      null,
      manifest,
      const Color(0xFF7A8494),
      tokenFallback: 'textSecondary',
      secondaryToken: 'muted',
    );
    final dangerColor = _resolveColor(
      null,
      manifest,
      const Color(0xFFFF5370),
      tokenFallback: 'danger',
    );

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
        body: MediaQuery.removePadding(
          context: context,
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.state.errorMessage case final error?)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
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
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _renderNode(rootNode, constraints.biggest, isRoot: true),
                ),
              ),
              if (!manifest.option<bool>('xmbMode', false))
                _DataDrivenBottomBar(
                  themeName: manifest.name,
                  fgColor: fgColor,
                  mutedColor: mutedColor,
                  accentColor: accentColor,
                  surfaceColor: surfaceColor,
                  hasSelectedGame: selected != null,
                  onAddApps: widget.onAddApps,
                  onRemoveGame: selected == null || widget.onRemoveGame == null
                      ? null
                      : () => widget.onRemoveGame!(selected),
                  onEditGame: selected == null || widget.onEditGame == null
                      ? null
                      : () => widget.onEditGame!(selected),
                  onToggleFavorite:
                      selected == null || widget.onToggleFavorite == null
                      ? null
                      : () => widget.onToggleFavorite!(selected),
                  onRescan: widget.onRescan,
                  onOpenThemeManager: widget.onOpenThemeManager,
                  onOpenSettings: widget.onOpenSettings,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _renderNode(
    ThemeLayoutNode node,
    Size viewport, {
    bool isRoot = false,
  }) {
    final child = switch (node.type) {
      ThemeNodeType.stack => _buildStack(node, viewport, isRoot: isRoot),
      ThemeNodeType.row => _buildFlex(node, viewport, Axis.horizontal),
      ThemeNodeType.column => _buildFlex(node, viewport, Axis.vertical),
      ThemeNodeType.positioned => _buildPositioned(node, viewport),
      ThemeNodeType.padding => _buildPadding(node, viewport),
      ThemeNodeType.container => _buildContainer(node, viewport),
      ThemeNodeType.dynamicBackground => _buildDynamicBackground(
        node,
        viewport,
      ),
      ThemeNodeType.mediaCarousel => _buildMediaCarousel(node, viewport),
      ThemeNodeType.gameArtwork => _buildGameArtwork(node, viewport),
      ThemeNodeType.metadataText => _buildMetadataText(node),
    };
    return child;
  }

  Widget _buildStack(
    ThemeLayoutNode node,
    Size viewport, {
    bool isRoot = false,
  }) {
    final alignment = _parseAlignment(node.props['alignment']);
    final fit = node.props['fit'] == 'expand' || isRoot
        ? StackFit.expand
        : StackFit.loose;
    return Stack(
      alignment: alignment,
      fit: fit,
      children: [for (final c in node.children) _renderNode(c, viewport)],
    );
  }

  Widget _buildFlex(ThemeLayoutNode node, Size viewport, Axis axis) {
    final mainAxis = _parseMainAxisAlignment(node.props['mainAxisAlignment']);
    final crossAxis = _parseCrossAxisAlignment(
      node.props['crossAxisAlignment'],
    );
    final hasFlexChild = node.children.any(
      (c) => (c.props['flex'] as num? ?? 0) > 0,
    );
    final mainSize = hasFlexChild || node.props['mainAxisSize'] == 'max'
        ? MainAxisSize.max
        : MainAxisSize.min;

    final children = <Widget>[
      for (final c in node.children)
        _maybeWrapFlexChild(c, _renderNode(c, viewport)),
    ];

    if (axis == Axis.horizontal) {
      return Row(
        mainAxisAlignment: mainAxis,
        crossAxisAlignment: crossAxis,
        mainAxisSize: mainSize,
        children: children,
      );
    }
    if (hasFlexChild) {
      return Column(
        mainAxisAlignment: mainAxis,
        crossAxisAlignment: crossAxis,
        mainAxisSize: MainAxisSize.max,
        children: children,
      );
    }
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        mainAxisAlignment: mainAxis,
        crossAxisAlignment: crossAxis,
        mainAxisSize: mainSize,
        children: children,
      ),
    );
  }

  Widget _maybeWrapFlexChild(ThemeLayoutNode node, Widget built) {
    final flex = (node.props['flex'] as num?)?.toInt();
    if (flex != null && flex > 0) {
      return Expanded(flex: flex, child: built);
    }
    return built;
  }

  Widget _buildPositioned(ThemeLayoutNode node, Size viewport) {
    final child = node.children.isEmpty
        ? const SizedBox.shrink()
        : _renderNode(node.children.first, viewport);
    return Positioned(
      left: _resolveExtent(node.props['left'], viewport.width),
      right: _resolveExtent(node.props['right'], viewport.width),
      top: _resolveExtent(node.props['top'], viewport.height),
      bottom: _resolveExtent(node.props['bottom'], viewport.height),
      width: _resolveExtent(node.props['width'], viewport.width),
      height: _resolveExtent(node.props['height'], viewport.height),
      child: child,
    );
  }

  Widget _buildPadding(ThemeLayoutNode node, Size viewport) {
    final child = node.children.isEmpty
        ? const SizedBox.shrink()
        : _renderNode(node.children.first, viewport);
    return Padding(padding: _parsePadding(node.props), child: child);
  }

  Widget _buildContainer(ThemeLayoutNode node, Size viewport) {
    final manifest = widget.state.theme;
    final width = _resolveExtent(node.props['width'], viewport.width);
    final height = _resolveExtent(node.props['height'], viewport.height);
    final color = node.props['color'] == null
        ? null
        : _resolveColor(node.props['color'], manifest, Colors.transparent);
    final borderColor = node.props['borderColor'] == null
        ? null
        : _resolveColor(node.props['borderColor'], manifest, Colors.white24);
    final borderWidth = (node.props['borderWidth'] as num?)?.toDouble() ?? 1.0;
    final radius = (node.props['borderRadius'] as num?)?.toDouble() ?? 0.0;

    Widget? child;
    if (node.children.length == 1) {
      child = _renderNode(node.children.first, viewport);
    } else if (node.children.length > 1) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final c in node.children) _renderNode(c, viewport)],
      );
    }

    final rawImage = node.props['image'];
    if (rawImage is String &&
        rawImage.isNotEmpty &&
        width != null &&
        height != null) {
      final path = _resolveAssetPath(rawImage);
      child = Stack(
        fit: StackFit.passthrough,
        children: [
          if (path != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: BudgetImage.file(path, width: width, height: height),
            ),
          ?child,
        ],
      );
    }

    return Container(
      width: width,
      height: height,
      alignment: node.props['alignment'] == null
          ? null
          : _parseAlignment(node.props['alignment']),
      padding: _parsePadding(node.props),
      margin: _parseMargin(node.props['margin']),
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius > 0 ? BorderRadius.circular(radius) : null,
        border: borderColor != null
            ? Border.all(color: borderColor, width: borderWidth)
            : null,
      ),
      child: child,
    );
  }

  Widget _buildDynamicBackground(ThemeLayoutNode node, Size viewport) {
    final manifest = widget.state.theme;
    final colorA = _resolveColor(
      node.props['color'],
      manifest,
      const Color(0xFF0B0D10),
      tokenFallback: 'background',
    );
    final colorB = _resolveColor(
      node.props['secondaryColor'],
      manifest,
      const Color(0xFF12161C),
      tokenFallback: 'surface',
    );
    final accentColor = _resolveColor(
      null,
      manifest,
      const Color(0xFF00E5FF),
      tokenFallback: 'accent',
    );

    final rawImage = node.props['image'];
    if (rawImage is String && rawImage.isNotEmpty) {
      final resolvedPath = _resolveAssetPath(rawImage);
      if (resolvedPath != null && resolvedPath.isNotEmpty) {
        final w = viewport.width.clamp(64.0, 2048.0);
        final h = viewport.height.clamp(64.0, 2048.0);
        return Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: Stack(
              key: ValueKey(resolvedPath),
              fit: StackFit.expand,
              children: [
                BudgetImage.file(resolvedPath, width: w, height: h),
                ColoredBox(color: colorA.withValues(alpha: 0.55)),
              ],
            ),
          ),
        );
      }
    }

    final shaderProp = node.props['shader'] as String?;
    if (shaderProp == 'onda_grid' || shaderProp == 'wireframe_grid') {
      return Positioned.fill(
        child: OndaGridBackground(
          colorA: colorA,
          colorB: colorB,
          accentColor: accentColor,
        ),
      );
    }

    final shaderAsset = switch (shaderProp) {
      'ps3_wave' ||
      'psp_wave' ||
      'wave_background' => 'shaders/wave_background.frag',
      final s? when s.endsWith('.frag') => s,
      _ => null,
    };

    if (shaderAsset != null && !widget.state.settings.reduceMotion) {
      return Positioned.fill(
        child: ShaderBackground(
          asset: shaderAsset,
          colorA: colorA,
          colorB: colorB,
          animate: !widget.state.isLaunching,
        ),
      );
    }

    return Positioned.fill(child: ColoredBox(color: colorA));
  }

  Widget _buildMediaCarousel(ThemeLayoutNode node, Size viewport) {
    final manifest = widget.state.theme;
    final accentColor = _resolveColor(
      null,
      manifest,
      const Color(0xFF00E5FF),
      tokenFallback: 'focusGlow',
      secondaryToken: 'accent',
    );
    final surfaceColor = _resolveColor(
      null,
      manifest,
      const Color(0xFF12161C),
      tokenFallback: 'primary',
      secondaryToken: 'surface',
    );
    final fgColor = _resolveColor(
      null,
      manifest,
      const Color(0xFFE6E6E6),
      tokenFallback: 'textPrimary',
      secondaryToken: 'foreground',
    );
    final mutedColor = _resolveColor(
      null,
      manifest,
      const Color(0xFF7A8494),
      tokenFallback: 'textSecondary',
      secondaryToken: 'muted',
    );
    final favoriteColor = _resolveColor(
      null,
      manifest,
      const Color(0xFFFFC400),
      tokenFallback: 'favorite',
    );

    final direction = (node.props['direction'] as String?) ?? 'horizontal';
    final itemAsset = (node.props['itemAsset'] as String?) ?? 'cover';
    final itemWidth = (node.props['itemWidth'] as num?)?.toDouble() ?? 144.0;
    final itemHeight = (node.props['itemHeight'] as num?)?.toDouble() ?? 144.0;
    final spacing = (node.props['spacing'] as num?)?.toDouble() ?? 14.0;
    final focusScale = (node.props['focusScale'] as num?)?.toDouble() ?? 1.06;
    final explicitHeight = _resolveExtent(
      node.props['height'],
      viewport.height,
    );
    final explicitWidth = _resolveExtent(node.props['width'], viewport.width);

    if (widget.state.status == LibraryStatus.loading) {
      return SizedBox(
        height: explicitHeight ?? (itemHeight + 56),
        child: Center(
          child: Text(
            'CARREGANDO BIBLIOTECA...',
            style: TextStyle(color: accentColor, fontFamily: 'monospace'),
          ),
        ),
      );
    }

    final isVertical = direction == 'vertical';
    final isCrossbar = direction == 'crossbar';

    if (isCrossbar) {
      final glowColor = _resolveColor(
        null,
        manifest,
        accentColor,
        tokenFallback: 'focusGlow',
        secondaryToken: 'accent',
      );
      final brandAccent = _resolveColor(
        null,
        manifest,
        accentColor,
        tokenFallback: 'accent',
      );
      final surfacePanelColor = _resolveColor(
        null,
        manifest,
        surfaceColor,
        tokenFallback: 'surface',
        secondaryToken: 'primary',
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          final resolvedHeight =
              explicitHeight ??
              (constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : viewport.height);
          return SizedBox(
            width: explicitWidth ?? double.infinity,
            height: resolvedHeight,
            child: Ps3XmbView(
              categories: _categories,
              categoryIndex: _categoryIndex,
              selectedGame: _selectedGame,
              totalGames: widget.state.totalGames,
              themeName: manifest.name,
              nodeForGame: _nodeFor,
              emptyAddNode: _emptyAddNode,
              emptyRescanNode: _emptyRescanNode,
              onSelectCategory: _selectCategoryAt,
              onSwitchCategory: _switchCategory,
              onSelectGame: (game) {
                if (_activeGameId != game.id) {
                  setState(() => _activeGameId = game.id);
                }
                widget.onSelectGame(game);
              },
              onLaunchGame: widget.onLaunchGame,
              onOpenSettings: widget.onOpenSettings,
              onAddApps: widget.onAddApps,
              onRemoveGame: widget.onRemoveGame,
              onEditGame: widget.onEditGame,
              onToggleFavorite: widget.onToggleFavorite,
              onRescan: widget.onRescan,
              onOpenThemeManager: widget.onOpenThemeManager,
              itemAsset: itemAsset,
              accentColor: brandAccent,
              glowColor: glowColor,
              surfaceColor: surfacePanelColor,
              fgColor: fgColor,
              mutedColor: mutedColor,
              favoriteColor: favoriteColor,
            ),
          );
        },
      );
    }

    final cat = _activeCategory;
    if (cat == null || cat.games.isEmpty) {
      return SizedBox(
        height: explicitHeight ?? (itemHeight + 64),
        child: Center(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _ActionPill(
                focusNode: _emptyAddNode,
                label: 'Selecionar Jogos [X]',
                icon: Icons.add_box_outlined,
                accentColor: accentColor,
                fgColor: fgColor,
                surfaceColor: surfaceColor,
                onActivate: widget.onAddApps,
              ),
              _ActionPill(
                focusNode: _emptyRescanNode,
                label: 'Reescanear [SELECT]',
                icon: Icons.refresh,
                accentColor: accentColor,
                fgColor: fgColor,
                surfaceColor: surfaceColor,
                onActivate: widget.onRescan,
              ),
            ],
          ),
        ),
      );
    }

    final iconSize = (itemWidth * 0.56).clamp(32.0, itemHeight - 40);

    final list = FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: ListView.separated(
        scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        itemCount: cat.games.length,
        separatorBuilder: (_, _) => SizedBox(
          width: isVertical ? 0 : spacing,
          height: isVertical ? spacing : 0,
        ),
        itemBuilder: (context, index) {
          final game = cat.games[index];
          return FocusTraversalOrder(
            order: NumericFocusOrder(index.toDouble()),
            child: _CarouselGameCard(
              game: game,
              focusNode: _nodeFor(game),
              isSelected: _activeGameId == game.id,
              width: itemWidth,
              height: itemHeight,
              artworkSize: iconSize,
              itemAsset: itemAsset,
              focusScale: focusScale,
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

    return SizedBox(
      width: explicitWidth ?? double.infinity,
      height: explicitHeight ?? (isVertical ? 260 : itemHeight + 60),
      child: list,
    );
  }

  Widget _buildGameArtwork(ThemeLayoutNode node, Size viewport) {
    final manifest = widget.state.theme;
    final width = _resolveExtent(node.props['width'], viewport.width) ?? 80.0;
    final height =
        _resolveExtent(node.props['height'], viewport.height) ?? 80.0;
    final radius = (node.props['borderRadius'] as num?)?.toDouble() ?? 8.0;
    final fit = _parseBoxFit(node.props['fit']);
    final accentColor = _resolveColor(
      null,
      manifest,
      const Color(0xFF00E5FF),
      tokenFallback: 'accent',
    );
    final mutedColor = _resolveColor(
      null,
      manifest,
      const Color(0xFF7A8494),
      tokenFallback: 'textSecondary',
      secondaryToken: 'muted',
    );

    final game = _selectedGame;
    String? path;
    final rawSrc = node.props['src'];
    if (rawSrc is String && rawSrc.isNotEmpty) {
      path = _resolveAssetPath(rawSrc);
    } else {
      final assetType = (node.props['assetType'] as String?) ?? 'cover';
      path = _artworkForGame(game, assetType);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BudgetImage.file(
        path,
        width: width,
        height: height,
        fit: fit,
        placeholder: Container(
          width: width,
          height: height,
          color: mutedColor.withValues(alpha: 0.14),
          child: Icon(
            switch (game?.kind) {
              GameKind.recompPort => Icons.memory,
              GameKind.emulated => Icons.videogame_asset,
              _ => Icons.android,
            },
            size: (width < height ? width : height) * 0.45,
            color: accentColor.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataText(ThemeLayoutNode node) {
    final manifest = widget.state.theme;
    final rawText = (node.props['text'] as String?) ?? '';
    final text = DataDrivenThemeEngine.resolveBindings(
      rawText,
      state: widget.state,
      category: _activeCategory,
      game: _selectedGame,
    );
    final color = _resolveColor(
      node.props['color'],
      manifest,
      const Color(0xFFE6E6E6),
      tokenFallback: 'textPrimary',
      secondaryToken: 'foreground',
    );
    final fontSize = (node.props['fontSize'] as num?)?.toDouble() ?? 14.0;
    final letterSpacing = (node.props['letterSpacing'] as num?)?.toDouble();
    final maxLines = (node.props['maxLines'] as num?)?.toInt();
    final fontWeight = switch (node.props['fontWeight']) {
      'bold' || 'w700' => FontWeight.bold,
      'w600' || 'semiBold' => FontWeight.w600,
      'w500' || 'medium' => FontWeight.w500,
      'w300' || 'light' => FontWeight.w300,
      _ => FontWeight.normal,
    };
    final fontFamily = node.props['fontFamily'] as String?;
    final textAlign = switch (node.props['textAlign']) {
      'center' => TextAlign.center,
      'right' || 'end' => TextAlign.end,
      _ => TextAlign.start,
    };

    return Text(
      text,
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : TextOverflow.visible,
      textAlign: textAlign,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: fontFamily,
        letterSpacing: letterSpacing,
      ),
    );
  }

  String? _artworkForGame(GameItem? game, String assetType) {
    if (game == null) return null;
    return switch (assetType) {
      'clearLogo' || 'logo' => game.media.logoPath,
      'banner' ||
      'heroBanner' => game.media.bannerPath ?? game.media.backgroundPath,
      'background' => game.media.backgroundPath ?? game.media.bannerPath,
      'icon' => game.media.iconPath,
      _ => game.media.coverPath ?? game.media.iconPath,
    };
  }

  String? _resolveAssetPath(String raw) {
    final bound = DataDrivenThemeEngine.resolveBindings(
      raw,
      state: widget.state,
      category: _activeCategory,
      game: _selectedGame,
    );
    if (bound.isEmpty) return null;
    if (bound.startsWith('/') ||
        bound.startsWith('assets/') ||
        bound.contains('://')) {
      return bound;
    }
    final base = widget.state.theme.basePath;
    if (base == null || base.isEmpty) return bound;
    return base.startsWith('assets/') ? '$base/$bound' : p.join(base, bound);
  }

  static Color _resolveColor(
    Object? raw,
    ThemeManifest manifest,
    Color fallback, {
    String? tokenFallback,
    String? secondaryToken,
  }) {
    if (raw is int) return Color(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      final trimmed = raw.trim();
      final match = RegExp(r'^\{\{theme\.([^}]+)\}\}$').firstMatch(trimmed);
      final token = match != null
          ? match[1]!.trim()
          : (trimmed.startsWith('@') ? trimmed.substring(1) : trimmed);
      if (manifest.colors.containsKey(token)) {
        return Color(manifest.colors[token]!);
      }
      try {
        return Color(parseColor(trimmed));
      } on Object {
        // Fall through to token defaults.
      }
    }
    if (tokenFallback != null && manifest.colors.containsKey(tokenFallback)) {
      return Color(manifest.colors[tokenFallback]!);
    }
    if (secondaryToken != null && manifest.colors.containsKey(secondaryToken)) {
      return Color(manifest.colors[secondaryToken]!);
    }
    return fallback;
  }

  static double? _resolveExtent(Object? raw, double parentExtent) {
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final s = raw.trim();
      if (s.endsWith('%')) {
        final pct = double.tryParse(s.substring(0, s.length - 1));
        if (pct != null) return (pct / 100.0) * parentExtent;
      }
      return double.tryParse(s);
    }
    return null;
  }

  static EdgeInsets _parsePadding(Map<String, Object?> props) {
    if (props['padding'] is num) {
      return EdgeInsets.all((props['padding']! as num).toDouble());
    }
    final h = (props['horizontal'] as num?)?.toDouble() ?? 0.0;
    final v = (props['vertical'] as num?)?.toDouble() ?? 0.0;
    return EdgeInsets.only(
      left: (props['left'] as num?)?.toDouble() ?? h,
      right: (props['right'] as num?)?.toDouble() ?? h,
      top: (props['top'] as num?)?.toDouble() ?? v,
      bottom: (props['bottom'] as num?)?.toDouble() ?? v,
    );
  }

  static EdgeInsets? _parseMargin(Object? raw) {
    if (raw is num) return EdgeInsets.all(raw.toDouble());
    if (raw is Map) {
      final h = (raw['horizontal'] as num?)?.toDouble() ?? 0.0;
      final v = (raw['vertical'] as num?)?.toDouble() ?? 0.0;
      return EdgeInsets.only(
        left: (raw['left'] as num?)?.toDouble() ?? h,
        right: (raw['right'] as num?)?.toDouble() ?? h,
        top: (raw['top'] as num?)?.toDouble() ?? v,
        bottom: (raw['bottom'] as num?)?.toDouble() ?? v,
      );
    }
    return null;
  }

  static Alignment _parseAlignment(Object? raw) => switch (raw) {
    'topLeft' => Alignment.topLeft,
    'topCenter' => Alignment.topCenter,
    'topRight' => Alignment.topRight,
    'centerLeft' => Alignment.centerLeft,
    'centerRight' => Alignment.centerRight,
    'bottomLeft' => Alignment.bottomLeft,
    'bottomCenter' => Alignment.bottomCenter,
    'bottomRight' => Alignment.bottomRight,
    _ => Alignment.center,
  };

  static MainAxisAlignment _parseMainAxisAlignment(Object? raw) =>
      switch (raw) {
        'center' => MainAxisAlignment.center,
        'end' => MainAxisAlignment.end,
        'spaceBetween' => MainAxisAlignment.spaceBetween,
        'spaceAround' => MainAxisAlignment.spaceAround,
        'spaceEvenly' => MainAxisAlignment.spaceEvenly,
        _ => MainAxisAlignment.start,
      };

  static CrossAxisAlignment _parseCrossAxisAlignment(Object? raw) =>
      switch (raw) {
        'center' => CrossAxisAlignment.center,
        'end' => CrossAxisAlignment.end,
        'stretch' => CrossAxisAlignment.stretch,
        _ => CrossAxisAlignment.start,
      };

  static BoxFit _parseBoxFit(Object? raw) => switch (raw) {
    'contain' => BoxFit.contain,
    'fill' => BoxFit.fill,
    'fitWidth' => BoxFit.fitWidth,
    'fitHeight' => BoxFit.fitHeight,
    _ => BoxFit.cover,
  };
}

class _CarouselGameCard extends StatefulWidget {
  const _CarouselGameCard({
    required this.game,
    required this.focusNode,
    required this.isSelected,
    required this.width,
    required this.height,
    required this.artworkSize,
    required this.itemAsset,
    required this.focusScale,
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
  final double width;
  final double height;
  final double artworkSize;
  final String itemAsset;
  final double focusScale;
  final Color surfaceColor;
  final Color fgColor;
  final Color mutedColor;
  final Color accentColor;
  final Color favoriteColor;
  final VoidCallback onFocused;
  final VoidCallback onActivate;

  @override
  State<_CarouselGameCard> createState() => _CarouselGameCardState();
}

class _CarouselGameCardState extends State<_CarouselGameCard> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _hasFocus || widget.isSelected;
    final artPath = switch (widget.itemAsset) {
      'banner' =>
        widget.game.media.bannerPath ??
            widget.game.media.coverPath ??
            widget.game.media.iconPath,
      'icon' => widget.game.media.iconPath,
      'clearLogo' => widget.game.media.logoPath ?? widget.game.media.iconPath,
      _ => widget.game.media.coverPath ?? widget.game.media.iconPath,
    };

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
          scale: _hasFocus ? widget.focusScale : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: widget.width,
            height: widget.height,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _hasFocus
                  ? widget.accentColor.withValues(alpha: 0.16)
                  : widget.surfaceColor.withValues(alpha: 0.88),
              border: Border.all(
                color: _hasFocus
                    ? widget.accentColor
                    : (highlighted
                          ? widget.accentColor.withValues(alpha: 0.45)
                          : widget.mutedColor.withValues(alpha: 0.3)),
                width: _hasFocus ? 2.2 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
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
                        artPath,
                        width: widget.artworkSize,
                        height: widget.artworkSize,
                        placeholder: Container(
                          width: widget.artworkSize,
                          height: widget.artworkSize,
                          color: widget.mutedColor.withValues(alpha: 0.16),
                          child: Icon(
                            switch (widget.game.kind) {
                              GameKind.recompPort => Icons.memory,
                              GameKind.emulated => Icons.videogame_asset,
                              GameKind.androidNative => Icons.android,
                            },
                            size: widget.artworkSize * 0.48,
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

class _DataDrivenBottomBar extends StatelessWidget {
  const _DataDrivenBottomBar({
    required this.themeName,
    required this.fgColor,
    required this.mutedColor,
    required this.accentColor,
    required this.surfaceColor,
    required this.hasSelectedGame,
    required this.onAddApps,
    required this.onRemoveGame,
    required this.onEditGame,
    required this.onToggleFavorite,
    required this.onRescan,
    required this.onOpenThemeManager,
    required this.onOpenSettings,
  });

  final String themeName;
  final Color fgColor;
  final Color mutedColor;
  final Color accentColor;
  final Color surfaceColor;
  final bool hasSelectedGame;
  final VoidCallback? onAddApps;
  final VoidCallback? onRemoveGame;
  final VoidCallback? onEditGame;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onRescan;
  final VoidCallback? onOpenThemeManager;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: 0.92),
          border: Border(
            top: BorderSide(color: mutedColor.withValues(alpha: 0.25)),
          ),
        ),
        child: Wrap(
          spacing: 14,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                if (hasSelectedGame)
                  _HudHint(
                    keyLabel: 'A',
                    label: 'Iniciar',
                    accentColor: accentColor,
                    fgColor: fgColor,
                  ),
                if (onAddApps != null)
                  _HudHint(
                    keyLabel: 'X',
                    label: '+App',
                    accentColor: accentColor,
                    fgColor: fgColor,
                    onTap: onAddApps,
                  ),
                if (onToggleFavorite != null)
                  _HudHint(
                    keyLabel: 'Y',
                    label: 'Favorito',
                    accentColor: accentColor,
                    fgColor: fgColor,
                    onTap: onToggleFavorite,
                  ),
                if (onRemoveGame != null)
                  _HudHint(
                    keyLabel: 'DEL',
                    label: 'Retirar',
                    accentColor: accentColor,
                    fgColor: fgColor,
                    onTap: onRemoveGame,
                  ),
                if (onEditGame != null)
                  _HudHint(
                    keyLabel: 'META',
                    label: 'Metadados',
                    accentColor: accentColor,
                    fgColor: fgColor,
                    onTap: onEditGame,
                  ),
                _HudHint(
                  keyLabel: 'L1/R1',
                  label: 'Categoria',
                  accentColor: accentColor,
                  fgColor: fgColor,
                ),
                if (onRescan != null)
                  _HudHint(
                    keyLabel: 'SELECT',
                    label: 'Rescan',
                    accentColor: accentColor,
                    fgColor: fgColor,
                    onTap: onRescan,
                  ),
                if (onOpenThemeManager != null)
                  _HudHint(
                    keyLabel: 'TEMAS',
                    label: 'Layouts & Cores',
                    accentColor: accentColor,
                    fgColor: fgColor,
                    onTap: onOpenThemeManager,
                  ),
                _HudHint(
                  keyLabel: 'START',
                  label: 'Config',
                  accentColor: accentColor,
                  fgColor: fgColor,
                  onTap: onOpenSettings,
                ),
              ],
            ),
            Text(
              'Onda Pixel • $themeName',
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

class _HudHint extends StatelessWidget {
  const _HudHint({
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
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: fgColor, fontSize: 11)),
      ],
    );
    return onTap == null ? child : GestureDetector(onTap: onTap, child: child);
  }
}

class _ActionPill extends StatefulWidget {
  const _ActionPill({
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
  State<_ActionPill> createState() => _ActionPillState();
}

class _ActionPillState extends State<_ActionPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? widget.accentColor.withValues(alpha: 0.2)
                : widget.surfaceColor,
            border: Border.all(
              color: _focused
                  ? widget.accentColor
                  : widget.fgColor.withValues(alpha: 0.3),
              width: _focused ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: _focused ? widget.accentColor : widget.fgColor,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: _focused ? widget.accentColor : widget.fgColor,
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
