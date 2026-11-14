import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/media/budget_image.dart';
import '../../domain/models/game_item.dart';
import '../../domain/models/library_state.dart';

enum _XmbColumnKind { settings, themes, addGames, games, categories }

class _XmbActionOption {
  const _XmbActionOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTrigger,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTrigger;
}

/// Handheld-optimized PlayStation Portable (PSP) XrossMediaBar (XMB) layout
/// used by `DataDrivenThemeEngine` when `direction == "crossbar"`.
class Ps3XmbView extends StatefulWidget {
  const Ps3XmbView({
    super.key,
    required this.categories,
    required this.categoryIndex,
    required this.selectedGame,
    required this.totalGames,
    required this.themeName,
    required this.nodeForGame,
    required this.emptyAddNode,
    required this.emptyRescanNode,
    required this.onSelectCategory,
    required this.onSwitchCategory,
    required this.onSelectGame,
    required this.onLaunchGame,
    required this.onOpenSettings,
    this.onAddApps,
    this.onRemoveGame,
    this.onEditGame,
    this.onToggleFavorite,
    this.onRescan,
    this.onOpenThemeManager,
    required this.itemAsset,
    required this.accentColor,
    required this.glowColor,
    required this.surfaceColor,
    required this.fgColor,
    required this.mutedColor,
    required this.favoriteColor,
  });

  final List<GameCategory> categories;
  final int categoryIndex;
  final GameItem? selectedGame;
  final int totalGames;
  final String themeName;
  final FocusNode Function(GameItem game) nodeForGame;
  final FocusNode emptyAddNode;
  final FocusNode emptyRescanNode;
  final ValueChanged<int> onSelectCategory;
  final ValueChanged<int> onSwitchCategory;
  final ValueChanged<GameItem> onSelectGame;
  final ValueChanged<GameItem> onLaunchGame;
  final VoidCallback onOpenSettings;
  final VoidCallback? onAddApps;
  final ValueChanged<GameItem>? onRemoveGame;
  final ValueChanged<GameItem>? onEditGame;
  final ValueChanged<GameItem>? onToggleFavorite;
  final VoidCallback? onRescan;
  final VoidCallback? onOpenThemeManager;
  final String itemAsset;
  final Color accentColor;
  final Color glowColor;
  final Color surfaceColor;
  final Color fgColor;
  final Color mutedColor;
  final Color favoriteColor;

  @override
  State<Ps3XmbView> createState() => _Ps3XmbViewState();
}

class _Ps3XmbViewState extends State<Ps3XmbView> {
  _XmbColumnKind _activeColumn = _XmbColumnKind.games;
  bool _optionsOpen = false;
  final Map<String, FocusNode> _menuNodes = {};
  final FocusNode _firstOptionDrawerNode = FocusNode(
    debugLabel: 'psp_xmb_drawer_first',
  );

  @override
  void dispose() {
    for (final node in _menuNodes.values) {
      node.dispose();
    }
    _menuNodes.clear();
    _firstOptionDrawerNode.dispose();
    super.dispose();
  }

  FocusNode _menuNodeFor(String id) =>
      _menuNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'psp_xmb_$id'));

  GameCategory? get _activeCategory {
    if (widget.categories.isEmpty) return null;
    final clamped = widget.categoryIndex.clamp(0, widget.categories.length - 1);
    return widget.categories[clamped];
  }

  void _selectColumn(_XmbColumnKind column) {
    if (_activeColumn == column) {
      return;
    }
    setState(() {
      _activeColumn = column;
      _optionsOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (column == _XmbColumnKind.games) {
        final game = widget.selectedGame;
        if (game != null) {
          widget.nodeForGame(game).requestFocus();
        } else if (widget.emptyAddNode.canRequestFocus) {
          widget.emptyAddNode.requestFocus();
        }
      } else {
        final opts = _optionsForColumn(column);
        if (opts.isNotEmpty) {
          _menuNodeFor(opts.first.id).requestFocus();
        }
      }
    });
  }

  void _moveHorizontal(int delta) {
    final values = _XmbColumnKind.values;
    final nextIdx = _activeColumn.index + delta;
    if (nextIdx >= 0 && nextIdx < values.length) {
      _selectColumn(values[nextIdx]);
    } else if (_activeColumn == _XmbColumnKind.games && delta > 0) {
      widget.onSwitchCategory(1);
    }
  }

  void _toggleOptionsDrawer() {
    setState(() => _optionsOpen = !_optionsOpen);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_optionsOpen) {
        _firstOptionDrawerNode.requestFocus();
      } else if (_activeColumn == _XmbColumnKind.games) {
        final g = widget.selectedGame;
        if (g != null) {
          widget.nodeForGame(g).requestFocus();
        }
      }
    });
  }

  List<_XmbActionOption> _optionsForColumn(_XmbColumnKind column) {
    final cat = _activeCategory;
    return switch (column) {
      _XmbColumnKind.settings => [
        _XmbActionOption(
          id: 'open_settings',
          title: 'Configurações do Sistema',
          subtitle: 'Ordenação, shader de ondas e cache de texturas',
          icon: Icons.tune_rounded,
          onTrigger: widget.onOpenSettings,
        ),
        _XmbActionOption(
          id: 'rescan_lib',
          title: 'Reescanear Biblioteca',
          subtitle: 'Atualizar aplicativos e jogos instalados',
          icon: Icons.refresh_rounded,
          onTrigger: widget.onRescan,
        ),
        _XmbActionOption(
          id: 'next_category',
          title: 'Categoria Atual: ${cat?.title ?? 'Todas'}',
          subtitle: 'Alternar categoria da biblioteca [L1/R1]',
          icon: Icons.sd_storage_rounded,
          onTrigger: () => widget.onSwitchCategory(1),
        ),
      ],
      _XmbColumnKind.themes => [
        _XmbActionOption(
          id: 'theme_manager',
          title: 'Temas & Editor de Cores',
          subtitle: 'Tema ativo: ${widget.themeName}',
          icon: Icons.palette_rounded,
          onTrigger: widget.onOpenThemeManager ?? widget.onOpenSettings,
        ),
        _XmbActionOption(
          id: 'launcher_settings',
          title: 'Preferências de Vídeo & Animação',
          subtitle: 'Reduzir animações de fundo e limpar cache',
          icon: Icons.display_settings_rounded,
          onTrigger: widget.onOpenSettings,
        ),
      ],
      _XmbColumnKind.addGames => [
        _XmbActionOption(
          id: 'add_app',
          title: 'Selecionar Jogos Instalados',
          subtitle: 'Escolher jogos e aplicativos instalados no aparelho',
          icon: Icons.sports_esports_rounded,
          onTrigger: widget.onAddApps ?? widget.onOpenSettings,
        ),
        if (widget.selectedGame != null && widget.onToggleFavorite != null)
          _XmbActionOption(
            id: 'fav_game',
            title: widget.selectedGame!.favorite
                ? 'Remover dos Favoritos'
                : 'Marcar como Favorito',
            subtitle: widget.selectedGame!.title,
            icon: widget.selectedGame!.favorite
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            onTrigger: () => widget.onToggleFavorite!(widget.selectedGame!),
          ),
        if (widget.selectedGame != null && widget.onEditGame != null)
          _XmbActionOption(
            id: 'edit_metadata',
            title: 'Editar Jogo & Metadados',
            subtitle: 'Baixar logo, fundo, ícone, nome e descrição',
            icon: Icons.auto_fix_high_rounded,
            onTrigger: () => widget.onEditGame!(widget.selectedGame!),
          ),
        if (widget.selectedGame != null && widget.onRemoveGame != null)
          _XmbActionOption(
            id: 'remove_game',
            title: 'Retirar da Biblioteca',
            subtitle: widget.selectedGame!.title,
            icon: Icons.delete_outline_rounded,
            onTrigger: () => widget.onRemoveGame!(widget.selectedGame!),
          ),
        _XmbActionOption(
          id: 'rescan_add',
          title: 'Reescanear Pasta de Jogos',
          subtitle: 'Buscar novos APKs e ROMs na pasta configurada',
          icon: Icons.manage_search_rounded,
          onTrigger: widget.onRescan,
        ),
      ],
      _XmbColumnKind.categories => [
        for (var i = 0; i < widget.categories.length; i++)
          _XmbActionOption(
            id: 'cat_pick_$i',
            title: widget.categories[i].title,
            subtitle: '${widget.categories[i].games.length} títulos',
            icon: switch (widget.categories[i].kind) {
              CategoryKind.recent => Icons.schedule_rounded,
              CategoryKind.favorites => Icons.star_rounded,
              CategoryKind.recomp => Icons.memory_rounded,
              CategoryKind.android => Icons.android_rounded,
              CategoryKind.emulated => Icons.videogame_asset_rounded,
              CategoryKind.custom => Icons.folder_special_rounded,
            },
            onTrigger: () {
              widget.onSelectCategory(i);
              _selectColumn(_XmbColumnKind.games);
            },
          ),
      ],
      _XmbColumnKind.games => const [],
    };
  }

  List<_XmbActionOption> _drawerOptions() {
    final game = widget.selectedGame;
    final cat = _activeCategory;
    return [
      if (game != null)
        _XmbActionOption(
          id: 'drawer_launch',
          title: 'Iniciar Jogo',
          subtitle: game.title,
          icon: Icons.play_arrow_rounded,
          onTrigger: () {
            setState(() => _optionsOpen = false);
            widget.onLaunchGame(game);
          },
        ),
      _XmbActionOption(
        id: 'drawer_category',
        title: 'Alternar Categoria',
        subtitle: cat != null ? '${cat.title} (${cat.games.length})' : 'Todas',
        icon: Icons.sd_storage_rounded,
        onTrigger: () => widget.onSwitchCategory(1),
      ),
      if (game != null && widget.onToggleFavorite != null)
        _XmbActionOption(
          id: 'drawer_favorite',
          title: game.favorite ? 'Desfavoritar' : 'Favoritar Jogo',
          subtitle: game.title,
          icon: game.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
          onTrigger: () => widget.onToggleFavorite!(game),
        ),
      if (game != null && widget.onEditGame != null)
        _XmbActionOption(
          id: 'drawer_edit_metadata',
          title: 'Editar Jogo & Metadados',
          subtitle: 'Baixar logo, fundo, ícone, nome e descrição',
          icon: Icons.auto_fix_high_rounded,
          onTrigger: () {
            setState(() => _optionsOpen = false);
            widget.onEditGame!(game);
          },
        ),
      if (game != null && widget.onRemoveGame != null)
        _XmbActionOption(
          id: 'drawer_remove',
          title: 'Retirar da Biblioteca',
          subtitle: game.title,
          icon: Icons.delete_outline_rounded,
          onTrigger: () {
            setState(() => _optionsOpen = false);
            widget.onRemoveGame!(game);
          },
        ),
      if (widget.onAddApps != null)
        _XmbActionOption(
          id: 'drawer_add',
          title: 'Selecionar Jogos Instalados',
          subtitle: 'Marcar quais jogos e apps aparecem na biblioteca',
          icon: Icons.add_box_outlined,
          onTrigger: () {
            setState(() => _optionsOpen = false);
            widget.onAddApps!();
          },
        ),
      if (widget.onOpenThemeManager != null)
        _XmbActionOption(
          id: 'drawer_themes',
          title: 'Layouts & Cores',
          subtitle: 'Temas PSP, PS3, Wireframe e comunidade',
          icon: Icons.palette_outlined,
          onTrigger: () {
            setState(() => _optionsOpen = false);
            widget.onOpenThemeManager!();
          },
        ),
      _XmbActionOption(
        id: 'drawer_settings',
        title: 'Configurações',
        subtitle: 'Ordenação, shader e cache',
        icon: Icons.settings_outlined,
        onTrigger: () {
          setState(() => _optionsOpen = false);
          widget.onOpenSettings();
        },
      ),
      if (widget.onRescan != null)
        _XmbActionOption(
          id: 'drawer_rescan',
          title: 'Reescanear Biblioteca',
          subtitle: 'Atualizar lista de jogos',
          icon: Icons.refresh_rounded,
          onTrigger: () {
            setState(() => _optionsOpen = false);
            widget.onRescan!();
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final compact = h < 460 || w < 700;

        // PSP positions the active horizontal XMB column inside the upper third.
        final activeX = (w * (compact ? 0.24 : 0.26)).clamp(92.0, 320.0);
        final controllerTop = (h * (compact ? 0.13 : 0.19)).clamp(44.0, 150.0);
        final focalTop = controllerTop + (compact ? 68.0 : 94.0);
        final colWidth = compact ? 114.0 : 144.0;
        final spineLeft = (activeX + 22.0 - colWidth / 2).clamp(12.0, w * 0.45);
        final spineTop = (controllerTop + (compact ? 32.0 : 48.0)).clamp(
          74.0,
          focalTop - 20.0,
        );

        final activeCat = _activeCategory;
        final games = activeCat?.games ?? const <GameItem>[];
        final bgPath =
            widget.selectedGame?.media.backgroundPath ??
            widget.selectedGame?.media.bannerPath;

        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (_optionsOpen) {
              if (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.backspace ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonB ||
                  event.logicalKey == LogicalKeyboardKey.gameButtonY) {
                _toggleOptionsDrawer();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _moveHorizontal(-1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _moveHorizontal(1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.gameButtonY) {
              _toggleOptionsDrawer();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bgPath != null &&
                  bgPath.isNotEmpty &&
                  w > 0 &&
                  h > 0 &&
                  w < 4096 &&
                  h < 4096)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: Stack(
                        key: ValueKey(bgPath),
                        fit: StackFit.expand,
                        children: [
                          BudgetImage.file(
                            bgPath,
                            width: w,
                            height: h,
                            fit: BoxFit.cover,
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  const Color(
                                    0xFF061C46,
                                  ).withValues(alpha: 0.44),
                                  Colors.black.withValues(alpha: 0.62),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Clean PSP top-right status bar: Memory Stick count + Clock + 3-bar Battery.
              Positioned(
                top: compact ? 10 : 18,
                right: compact ? 16 : 28,
                child: _PspTopStatusBar(
                  totalGames: widget.totalGames,
                  fgColor: widget.fgColor,
                  accentColor: widget.accentColor,
                ),
              ),

              if (_activeColumn == _XmbColumnKind.games && !compact)
                Positioned(
                  left: activeX + 8,
                  top: (controllerTop - 52).clamp(4.0, controllerTop),
                  child: _XmbUpperUtilityFolders(
                    fgColor: widget.fgColor,
                    accentColor: widget.accentColor,
                  ),
                ),

              // Wide top-third PSP horizontal XMB icon crossbar.
              Positioned(
                left: 0,
                right: 0,
                top: controllerTop,
                child: ExcludeFocus(
                  child: _PspHorizontalBar(
                    activeColumn: _activeColumn,
                    activeX: activeX,
                    maxWidth: w,
                    compact: compact,
                    fgColor: widget.fgColor,
                    accentColor: widget.accentColor,
                    glowColor: widget.glowColor,
                    mutedColor: widget.mutedColor,
                    onSelectColumn: (col) {
                      if (_activeColumn == col &&
                          col == _XmbColumnKind.themes) {
                        (widget.onOpenThemeManager ?? widget.onOpenSettings)();
                        return;
                      }
                      if (_activeColumn == col &&
                          col == _XmbColumnKind.settings) {
                        widget.onOpenSettings();
                        return;
                      }
                      if (_activeColumn == col &&
                          col == _XmbColumnKind.addGames) {
                        (widget.onAddApps ?? widget.onOpenSettings)();
                        return;
                      }
                      _selectColumn(col);
                    },
                  ),
                ),
              ),

              // Active XMB vertical content column directly beneath the "Jogo" icon.
              if (_activeColumn == _XmbColumnKind.games) ...[
                // Vertical spine of 16:9 ICON0 game tiles aligned under the active controller icon.
                Positioned(
                  left: spineLeft,
                  right: compact ? 16 : 36,
                  top: spineTop,
                  bottom: compact ? 42 : 54,
                  child: games.isEmpty
                      ? _PspEmptyGamesSpine(
                          compact: compact,
                          topPad: (focalTop - spineTop).clamp(0.0, 120.0),
                          addNode: widget.emptyAddNode,
                          rescanNode: widget.emptyRescanNode,
                          accentColor: widget.accentColor,
                          glowColor: widget.glowColor,
                          fgColor: widget.fgColor,
                          surfaceColor: widget.surfaceColor,
                          onAddApps: widget.onAddApps,
                          onRescan: widget.onRescan,
                        )
                      : _PspVerticalGameSpine(
                          games: games,
                          selectedGame: widget.selectedGame ?? games.first,
                          itemAsset: widget.itemAsset,
                          compact: compact,
                          topFocalPad: (focalTop - spineTop).clamp(0.0, 160.0),
                          nodeForGame: widget.nodeForGame,
                          fgColor: widget.fgColor,
                          mutedColor: widget.mutedColor,
                          accentColor: widget.accentColor,
                          glowColor: widget.glowColor,
                          surfaceColor: widget.surfaceColor,
                          favoriteColor: widget.favoriteColor,
                          onSelectGame: widget.onSelectGame,
                          onLaunchGame: widget.onLaunchGame,
                        ),
                ),
              ] else
                // On-screen options list for Settings / Themes / +App / Categories columns.
                Positioned(
                  left: (activeX - 24).clamp(16.0, w * 0.4),
                  right: compact ? 20 : 180,
                  top: focalTop,
                  bottom: compact ? 44 : 58,
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _optionsForColumn(_activeColumn).length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final opt = _optionsForColumn(_activeColumn)[index];
                        return FocusTraversalOrder(
                          order: NumericFocusOrder(index.toDouble()),
                          child: _PspMenuOptionRow(
                            option: opt,
                            focusNode: _menuNodeFor(opt.id),
                            autofocus: index == 0,
                            fgColor: widget.fgColor,
                            accentColor: widget.accentColor,
                            glowColor: widget.glowColor,
                            mutedColor: widget.mutedColor,
                            surfaceColor: widget.surfaceColor,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Bottom-right PSP action hints with △ : Options (no bottom category bar).
              Positioned(
                left: compact ? 12 : 24,
                right: compact ? 12 : 28,
                bottom: compact ? 8 : 14,
                child: ExcludeFocus(
                  child: Row(
                    children: [
                      const Spacer(),
                      if (widget.selectedGame != null) ...[
                        _PspButtonHint(
                          symbol: '✕',
                          symbolColor: const Color(0xFF8AB8FF),
                          label: 'Iniciar',
                          fgColor: widget.fgColor,
                          onTap: () =>
                              widget.onLaunchGame(widget.selectedGame!),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (widget.selectedGame != null &&
                          widget.onToggleFavorite != null &&
                          !compact) ...[
                        _PspButtonHint(
                          symbol: '□',
                          symbolColor: const Color(0xFFF09CD8),
                          label: 'Favorito',
                          fgColor: widget.fgColor,
                          onTap: () =>
                              widget.onToggleFavorite!(widget.selectedGame!),
                        ),
                        const SizedBox(width: 10),
                      ],
                      GestureDetector(
                        onTap: _toggleOptionsDrawer,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: _optionsOpen
                                  ? widget.accentColor
                                  : widget.fgColor.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '△',
                                style: TextStyle(
                                  color: Color(0xFF5CE092),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                ': Options',
                                style: TextStyle(
                                  color: widget.fgColor.withValues(alpha: 0.94),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Slide-over PSP OPTIONS drawer.
              if (_optionsOpen)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: (w * 0.34).clamp(250.0, 340.0),
                  child: _PspOptionsOverlay(
                    options: _drawerOptions(),
                    firstFocusNode: _firstOptionDrawerNode,
                    menuNodeFor: _menuNodeFor,
                    surfaceColor: widget.surfaceColor,
                    fgColor: widget.fgColor,
                    accentColor: widget.accentColor,
                    glowColor: widget.glowColor,
                    mutedColor: widget.mutedColor,
                    onClose: _toggleOptionsDrawer,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PspButtonHint extends StatelessWidget {
  const _PspButtonHint({
    required this.symbol,
    required this.symbolColor,
    required this.label,
    required this.fgColor,
    this.onTap,
  });

  final String symbol;
  final Color symbolColor;
  final String label;
  final Color fgColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            symbol,
            style: TextStyle(
              color: symbolColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fgColor.withValues(alpha: 0.88),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PspHorizontalBar extends StatelessWidget {
  const _PspHorizontalBar({
    required this.activeColumn,
    required this.activeX,
    required this.maxWidth,
    required this.compact,
    required this.fgColor,
    required this.accentColor,
    required this.glowColor,
    required this.mutedColor,
    required this.onSelectColumn,
  });

  final _XmbColumnKind activeColumn;
  final double activeX;
  final double maxWidth;
  final bool compact;
  final Color fgColor;
  final Color accentColor;
  final Color glowColor;
  final Color mutedColor;
  final ValueChanged<_XmbColumnKind> onSelectColumn;

  String _label(_XmbColumnKind kind) => switch (kind) {
    _XmbColumnKind.settings => 'Configurações',
    _XmbColumnKind.themes => 'Temas',
    _XmbColumnKind.addGames => '+ Jogo',
    _XmbColumnKind.games => 'Jogo',
    _XmbColumnKind.categories => 'Categorias',
  };

  @override
  Widget build(BuildContext context) {
    final slotWidth = compact ? 66.0 : 88.0;
    final activeWidth = compact ? 84.0 : 104.0;
    final activeCenterX = activeX + 22.0;

    return SizedBox(
      height: compact ? 66 : 86,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final kind in _XmbColumnKind.values)
            Builder(
              builder: (context) {
                final diff = kind.index - activeColumn.index;
                final isSelected = diff == 0;
                final rawLeft = isSelected
                    ? activeCenterX - activeWidth / 2
                    : activeCenterX +
                          (diff < 0
                              ? diff * slotWidth - (activeWidth * 0.25)
                              : diff * slotWidth + (activeWidth * 0.25)) -
                          slotWidth / 2;

                if (rawLeft < -50 || rawLeft > maxWidth - 20) {
                  return const SizedBox.shrink();
                }

                return AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  left: rawLeft.clamp(6.0, maxWidth - slotWidth),
                  top: isSelected ? 0 : 8,
                  width: isSelected ? activeWidth : slotWidth,
                  child: GestureDetector(
                    onTap: () => onSelectColumn(kind),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: isSelected ? 1.0 : 0.62,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _XmbCategoryIcon(
                            kind: kind,
                            size: isSelected
                                ? (compact ? 42 : 54)
                                : (compact ? 26 : 34),
                            color: isSelected
                                ? glowColor
                                : fgColor.withValues(alpha: 0.78),
                            accentColor: accentColor,
                            glowing: isSelected,
                          ),
                          if (isSelected) ...[
                            const SizedBox(height: 3),
                            Text(
                              _label(kind),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: glowColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _XmbUpperUtilityFolders extends StatelessWidget {
  const _XmbUpperUtilityFolders({
    required this.fgColor,
    required this.accentColor,
  });

  final Color fgColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.36,
              child: CustomPaint(
                size: const Size(28, 20),
                painter: _XmbMiniFolderPainter(
                  color: fgColor,
                  accentColor: accentColor,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Opacity(
              opacity: 0.54,
              child: CustomPaint(
                size: const Size(32, 22),
                painter: _XmbMiniFolderPainter(
                  color: fgColor,
                  accentColor: accentColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _XmbMiniFolderPainter extends CustomPainter {
  const _XmbMiniFolderPainter({required this.color, required this.accentColor});

  final Color color;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.20)
      ..lineTo(w * 0.42, h * 0.20)
      ..lineTo(w * 0.50, h * 0.34)
      ..lineTo(w * 0.90, h * 0.34)
      ..quadraticBezierTo(w * 0.96, h * 0.34, w * 0.96, h * 0.42)
      ..lineTo(w * 0.96, h * 0.84)
      ..quadraticBezierTo(w * 0.96, h * 0.92, w * 0.88, h * 0.92)
      ..lineTo(w * 0.12, h * 0.92)
      ..quadraticBezierTo(w * 0.04, h * 0.92, w * 0.04, h * 0.84)
      ..lineTo(w * 0.04, h * 0.28)
      ..quadraticBezierTo(w * 0.04, h * 0.20, w * 0.08, h * 0.20)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.95),
            Color.lerp(color, accentColor, 0.45) ?? color,
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.28, h * 0.48, w * 0.44, h * 0.24),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF0A2449).withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_XmbMiniFolderPainter oldDelegate) =>
      color != oldDelegate.color || accentColor != oldDelegate.accentColor;
}

class _XmbCategoryIcon extends StatelessWidget {
  const _XmbCategoryIcon({
    required this.kind,
    required this.size,
    required this.color,
    required this.accentColor,
    required this.glowing,
  });

  final _XmbColumnKind kind;
  final double size;
  final Color color;
  final Color accentColor;
  final bool glowing;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * 1.18, size),
      painter: _XmbCategoryIconPainter(
        kind: kind,
        color: color,
        accentColor: accentColor,
        glowing: glowing,
      ),
    );
  }
}

class _XmbCategoryIconPainter extends CustomPainter {
  const _XmbCategoryIconPainter({
    required this.kind,
    required this.color,
    required this.accentColor,
    required this.glowing,
  });

  final _XmbColumnKind kind;
  final Color color;
  final Color accentColor;
  final bool glowing;

  Paint _fillPaint(Size size, {double alpha = 1.0}) {
    final top = Color.lerp(color, Colors.white, glowing ? 0.35 : 0.12) ?? color;
    final bottom =
        Color.lerp(color, accentColor, glowing ? 0.55 : 0.42) ?? color;
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          top.withValues(alpha: alpha),
          bottom.withValues(alpha: alpha * 0.92),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
  }

  void _maybeGlow(Canvas canvas, Path path) {
    if (!glowing) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = accentColor.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = _fillPaint(size);
    final cutout = Paint()
      ..color = const Color(
        0xFF0A2449,
      ).withValues(alpha: glowing ? 0.68 : 0.55);

    switch (kind) {
      case _XmbColumnKind.settings:
        final body = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.14, h * 0.30, w * 0.72, h * 0.56),
          Radius.circular(h * 0.10),
        );
        final bodyPath = Path()..addRRect(body);
        _maybeGlow(canvas, bodyPath);
        canvas.drawPath(
          Path()..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.34, h * 0.15, w * 0.32, h * 0.22),
              Radius.circular(h * 0.08),
            ),
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (h * 0.075).clamp(2.0, 4.0)
            ..color = color,
        );
        canvas.drawPath(bodyPath, fill);
        canvas.drawRect(
          Rect.fromLTWH(w * 0.14, h * 0.50, w * 0.72, h * 0.06),
          cutout,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.43, h * 0.44, w * 0.14, h * 0.18),
            const Radius.circular(2),
          ),
          fill,
        );

      case _XmbColumnKind.themes:
        final frame = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.16, h * 0.28, w * 0.62, h * 0.48),
          Radius.circular(h * 0.06),
        );
        final framePath = Path()..addRRect(frame);
        _maybeGlow(canvas, framePath);
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (h * 0.075).clamp(2.0, 3.8)
          ..color = color;
        canvas.drawRRect(frame, stroke);
        // Inner subtle frosted fill
        canvas.drawRRect(frame, _fillPaint(size, alpha: 0.25));
        // Stand base
        canvas.drawLine(
          Offset(w * 0.47, h * 0.76),
          Offset(w * 0.47, h * 0.87),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.32, h * 0.87),
          Offset(w * 0.62, h * 0.87),
          stroke..strokeCap = StrokeCap.round,
        );
        // Broadcast arcs at top-right corner
        final arcPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (h * 0.065).clamp(1.6, 3.2)
          ..strokeCap = StrokeCap.round
          ..color = color;
        canvas.drawArc(
          Rect.fromCircle(center: Offset(w * 0.74, h * 0.30), radius: h * 0.13),
          -math.pi * 0.48,
          math.pi * 0.44,
          false,
          arcPaint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: Offset(w * 0.74, h * 0.30), radius: h * 0.24),
          -math.pi * 0.48,
          math.pi * 0.44,
          false,
          arcPaint,
        );

      case _XmbColumnKind.games:
        final path = Path()
          ..moveTo(w * 0.24, h * 0.28)
          ..lineTo(w * 0.76, h * 0.28)
          ..quadraticBezierTo(w * 0.88, h * 0.28, w * 0.92, h * 0.56)
          ..quadraticBezierTo(w * 0.94, h * 0.80, w * 0.82, h * 0.82)
          ..quadraticBezierTo(w * 0.72, h * 0.83, w * 0.65, h * 0.64)
          ..lineTo(w * 0.35, h * 0.64)
          ..quadraticBezierTo(w * 0.28, h * 0.83, w * 0.18, h * 0.82)
          ..quadraticBezierTo(w * 0.06, h * 0.80, w * 0.08, h * 0.56)
          ..quadraticBezierTo(w * 0.12, h * 0.28, w * 0.24, h * 0.28)
          ..close();

        // Shoulder trigger bumps
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.21, h * 0.21, w * 0.17, h * 0.10),
            const Radius.circular(3),
          ),
          _fillPaint(size, alpha: 0.75),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.62, h * 0.21, w * 0.17, h * 0.10),
            const Radius.circular(3),
          ),
          _fillPaint(size, alpha: 0.75),
        );

        _maybeGlow(canvas, path);
        canvas.drawPath(path, fill);

        // D-pad cross on left
        final dCenter = Offset(w * 0.27, h * 0.46);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: dCenter,
              width: w * 0.15,
              height: h * 0.075,
            ),
            const Radius.circular(1.5),
          ),
          cutout,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: dCenter,
              width: w * 0.065,
              height: h * 0.17,
            ),
            const Radius.circular(1.5),
          ),
          cutout,
        );

        // 4 face button dots on right
        final rCenter = Offset(w * 0.73, h * 0.46);
        final dotR = (h * 0.036).clamp(1.2, 2.2);
        canvas.drawCircle(
          Offset(rCenter.dx, rCenter.dy - h * 0.075),
          dotR,
          cutout,
        );
        canvas.drawCircle(
          Offset(rCenter.dx, rCenter.dy + h * 0.075),
          dotR,
          cutout,
        );
        canvas.drawCircle(
          Offset(rCenter.dx - w * 0.06, rCenter.dy),
          dotR,
          cutout,
        );
        canvas.drawCircle(
          Offset(rCenter.dx + w * 0.06, rCenter.dy),
          dotR,
          cutout,
        );

        // Twin thumbsticks
        final stickR = (h * 0.065).clamp(1.8, 3.6);
        canvas.drawCircle(Offset(w * 0.41, h * 0.56), stickR, cutout);
        canvas.drawCircle(Offset(w * 0.59, h * 0.56), stickR, cutout);

      case _XmbColumnKind.addGames:
        // PlayStation-style shopping bag with handle & □ △ ✕ ○
        final bag = Path()
          ..moveTo(w * 0.25, h * 0.28)
          ..lineTo(w * 0.75, h * 0.28)
          ..lineTo(w * 0.81, h * 0.84)
          ..quadraticBezierTo(w * 0.81, h * 0.90, w * 0.75, h * 0.90)
          ..lineTo(w * 0.25, h * 0.90)
          ..quadraticBezierTo(w * 0.19, h * 0.90, w * 0.19, h * 0.84)
          ..close();

        canvas.drawArc(
          Rect.fromLTWH(w * 0.36, h * 0.10, w * 0.28, h * 0.32),
          math.pi,
          math.pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (h * 0.065).clamp(1.8, 3.2)
            ..color = color,
        );
        _maybeGlow(canvas, bag);
        canvas.drawPath(bag, fill);

        final sym = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (h * 0.042).clamp(1.1, 2.2)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF0A2449).withValues(alpha: 0.82);
        final symS = h * 0.12;
        // Top-left □
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(w * 0.39, h * 0.49),
            width: symS,
            height: symS,
          ),
          sym,
        );
        // Top-right △
        final tc = Offset(w * 0.61, h * 0.49);
        canvas.drawPath(
          Path()
            ..moveTo(tc.dx, tc.dy - symS * 0.55)
            ..lineTo(tc.dx + symS * 0.55, tc.dy + symS * 0.48)
            ..lineTo(tc.dx - symS * 0.55, tc.dy + symS * 0.48)
            ..close(),
          sym,
        );
        // Bottom-left ✕
        final xc = Offset(w * 0.39, h * 0.71);
        final xr = symS * 0.45;
        canvas.drawLine(
          Offset(xc.dx - xr, xc.dy - xr),
          Offset(xc.dx + xr, xc.dy + xr),
          sym,
        );
        canvas.drawLine(
          Offset(xc.dx + xr, xc.dy - xr),
          Offset(xc.dx - xr, xc.dy + xr),
          sym,
        );
        // Bottom-right ○
        canvas.drawCircle(Offset(w * 0.61, h * 0.71), symS * 0.52, sym);

      case _XmbColumnKind.categories:
        final back = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.30, h * 0.22, w * 0.52, h * 0.48),
          Radius.circular(h * 0.08),
        );
        canvas.drawRRect(back, _fillPaint(size, alpha: 0.55));

        final front = Path()
          ..moveTo(w * 0.16, h * 0.30)
          ..lineTo(w * 0.42, h * 0.30)
          ..lineTo(w * 0.49, h * 0.40)
          ..lineTo(w * 0.76, h * 0.40)
          ..quadraticBezierTo(w * 0.82, h * 0.40, w * 0.82, h * 0.47)
          ..lineTo(w * 0.82, h * 0.80)
          ..quadraticBezierTo(w * 0.82, h * 0.86, w * 0.75, h * 0.86)
          ..lineTo(w * 0.22, h * 0.86)
          ..quadraticBezierTo(w * 0.16, h * 0.86, w * 0.16, h * 0.80)
          ..close();
        _maybeGlow(canvas, front);
        canvas.drawPath(front, fill);
        canvas.drawLine(
          Offset(w * 0.28, h * 0.58),
          Offset(w * 0.70, h * 0.58),
          cutout..strokeWidth = (h * 0.05).clamp(1.2, 2.4),
        );
        canvas.drawLine(
          Offset(w * 0.28, h * 0.70),
          Offset(w * 0.58, h * 0.70),
          cutout,
        );
    }
  }

  @override
  bool shouldRepaint(_XmbCategoryIconPainter oldDelegate) =>
      kind != oldDelegate.kind ||
      color != oldDelegate.color ||
      accentColor != oldDelegate.accentColor ||
      glowing != oldDelegate.glowing;
}

class _PspTopStatusBar extends StatelessWidget {
  const _PspTopStatusBar({
    required this.totalGames,
    required this.fgColor,
    required this.accentColor,
  });

  final int totalGames;
  final Color fgColor;
  final Color accentColor;

  String _formatPspClock(DateTime dt) {
    final hour24 = dt.hour;
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = hour24 >= 12 ? 'PM' : 'AM';
    return '${dt.month}/${dt.day}  $hour12:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final stamp = _formatPspClock(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD54F),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Center(
              child: Icon(Icons.add, size: 11, color: Color(0xFF0A1E3A)),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.sd_storage_outlined, size: 14, color: accentColor),
          const SizedBox(width: 3),
          Text(
            '$totalGames',
            style: TextStyle(
              color: fgColor.withValues(alpha: 0.94),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(
            stamp,
            style: TextStyle(
              color: fgColor,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _PspBatteryIndicator(borderColor: fgColor),
          const SizedBox(width: 6),
          Icon(
            Icons.access_time_rounded,
            size: 14,
            color: fgColor.withValues(alpha: 0.9),
          ),
        ],
      ),
    );
  }
}

class _PspBatteryIndicator extends StatelessWidget {
  const _PspBatteryIndicator({required this.borderColor});

  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3,
          height: 8,
          decoration: BoxDecoration(
            color: borderColor.withValues(alpha: 0.9),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(1.5),
            ),
          ),
        ),
        Container(
          width: 24,
          height: 13,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(
              color: borderColor.withValues(alpha: 0.9),
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(2.5),
          ),
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 2 ? 1.5 : 0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFA8F0C6),
                      borderRadius: BorderRadius.circular(0.8),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PspVerticalGameSpine extends StatelessWidget {
  const _PspVerticalGameSpine({
    required this.games,
    required this.selectedGame,
    required this.itemAsset,
    required this.compact,
    required this.topFocalPad,
    required this.nodeForGame,
    required this.fgColor,
    required this.mutedColor,
    required this.accentColor,
    required this.glowColor,
    required this.surfaceColor,
    required this.favoriteColor,
    required this.onSelectGame,
    required this.onLaunchGame,
  });

  final List<GameItem> games;
  final GameItem selectedGame;
  final String itemAsset;
  final bool compact;
  final double topFocalPad;
  final FocusNode Function(GameItem game) nodeForGame;
  final Color fgColor;
  final Color mutedColor;
  final Color accentColor;
  final Color glowColor;
  final Color surfaceColor;
  final Color favoriteColor;
  final ValueChanged<GameItem> onSelectGame;
  final ValueChanged<GameItem> onLaunchGame;

  @override
  Widget build(BuildContext context) {
    final selectedIdx = games.indexWhere((g) => g.id == selectedGame.id);

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: ListView.separated(
        padding: EdgeInsets.only(top: topFocalPad, bottom: compact ? 110 : 220),
        itemCount: games.length,
        separatorBuilder: (_, _) => SizedBox(height: compact ? 6 : 8),
        itemBuilder: (context, index) {
          final game = games[index];
          final isAboveSelected = selectedIdx >= 0 && index < selectedIdx;
          return FocusTraversalOrder(
            order: NumericFocusOrder(index.toDouble()),
            child: _PspSpineRow(
              key: ValueKey(game.id),
              game: game,
              focusNode: nodeForGame(game),
              isSelected: game.id == selectedGame.id,
              isAboveSelected: isAboveSelected,
              itemAsset: itemAsset,
              compact: compact,
              fgColor: fgColor,
              mutedColor: mutedColor,
              accentColor: accentColor,
              glowColor: glowColor,
              surfaceColor: surfaceColor,
              favoriteColor: favoriteColor,
              onFocused: () => onSelectGame(game),
              onActivate: () => onLaunchGame(game),
            ),
          );
        },
      ),
    );
  }
}

class _PspSpineRow extends StatefulWidget {
  const _PspSpineRow({
    super.key,
    required this.game,
    required this.focusNode,
    required this.isSelected,
    required this.isAboveSelected,
    required this.itemAsset,
    required this.compact,
    required this.fgColor,
    required this.mutedColor,
    required this.accentColor,
    required this.glowColor,
    required this.surfaceColor,
    required this.favoriteColor,
    required this.onFocused,
    required this.onActivate,
  });

  final GameItem game;
  final FocusNode focusNode;
  final bool isSelected;
  final bool isAboveSelected;
  final String itemAsset;
  final bool compact;
  final Color fgColor;
  final Color mutedColor;
  final Color accentColor;
  final Color glowColor;
  final Color surfaceColor;
  final Color favoriteColor;
  final VoidCallback onFocused;
  final VoidCallback onActivate;

  @override
  State<_PspSpineRow> createState() => _PspSpineRowState();
}

class _PspSpineRowState extends State<_PspSpineRow> {
  bool _hasFocus = false;

  String _formatStamp(DateTime? dt) {
    final d = (dt ?? widget.game.addedAt).toLocal();
    final hour24 = d.hour;
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final min = d.minute.toString().padLeft(2, '0');
    final ampm = hour24 >= 12 ? 'PM' : 'AM';
    return '${d.month}/${d.day}/${d.year}  $hour12:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final active = _hasFocus || widget.isSelected;
    final colWidth = widget.compact ? 114.0 : 144.0;
    final artW = active ? colWidth : (widget.compact ? 86.0 : 104.0);
    final artH = active
        ? (widget.compact ? 62.0 : 80.0)
        : (widget.compact ? 42.0 : 54.0);

    final artPath = switch (widget.itemAsset) {
      'banner' =>
        widget.game.media.bannerPath ??
            widget.game.media.logoPath ??
            widget.game.media.coverPath ??
            widget.game.media.iconPath,
      'clearLogo' =>
        widget.game.media.logoPath ??
            widget.game.media.bannerPath ??
            widget.game.media.coverPath ??
            widget.game.media.iconPath,
      'icon' => widget.game.media.iconPath,
      _ =>
        widget.game.media.logoPath ??
            widget.game.media.bannerPath ??
            widget.game.media.coverPath ??
            widget.game.media.iconPath,
    };
    final isSquareAppIcon =
        artPath != null &&
        artPath == widget.game.media.iconPath &&
        widget.game.media.bannerPath == null &&
        widget.game.media.coverPath == null &&
        widget.game.media.logoPath == null;

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
            alignment: 0.18,
            duration: const Duration(milliseconds: 160),
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
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: active ? 1.0 : (widget.isAboveSelected ? 0.36 : 0.90),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: colWidth,
                child: Align(
                  alignment: Alignment.center,
                  child: _PspIcon0Artwork(
                    title: widget.game.title,
                    artPath: artPath,
                    isSquareAppIcon: isSquareAppIcon,
                    width: artW,
                    height: artH,
                    active: active,
                    favorite: widget.game.favorite,
                    glowColor: widget.glowColor,
                    accentColor: widget.accentColor,
                    favoriteColor: widget.favoriteColor,
                    surfaceColor: widget.surfaceColor,
                  ),
                ),
              ),
              if (active) ...[
                SizedBox(width: widget.compact ? 12 : 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.game.media.logoPath != null &&
                          widget.game.media.logoPath!.isNotEmpty) ...[
                        BudgetImage.file(
                          widget.game.media.logoPath,
                          width: widget.compact ? 150 : 210,
                          height: widget.compact ? 36 : 48,
                          fit: BoxFit.contain,
                          placeholder: const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        widget.game.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.glowColor,
                          fontSize: widget.compact ? 16 : 19,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: widget.glowColor.withValues(alpha: 0.7),
                              blurRadius: 10,
                            ),
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.75),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Signature PSP 1px horizontal divider rule beneath title.
                      Container(
                        height: 1.0,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              widget.glowColor.withValues(alpha: 0.85),
                              widget.glowColor.withValues(alpha: 0.08),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          _PspPlatformBadge(
                            label: widget.game.platform.toUpperCase(),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${widget.game.playCount}x',
                            style: TextStyle(
                              color: widget.accentColor,
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatStamp(widget.game.lastPlayedAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.mutedColor,
                                fontSize: widget.compact ? 10.5 : 11.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.game.description != null &&
                          widget.game.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.game.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.fgColor.withValues(alpha: 0.88),
                            fontSize: widget.compact ? 10.5 : 11.5,
                            height: 1.2,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.7),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PspIcon0Artwork extends StatelessWidget {
  const _PspIcon0Artwork({
    required this.title,
    required this.artPath,
    this.isSquareAppIcon = false,
    required this.width,
    required this.height,
    required this.active,
    required this.favorite,
    required this.glowColor,
    required this.accentColor,
    required this.favoriteColor,
    required this.surfaceColor,
  });

  final String title;
  final String? artPath;
  final bool isSquareAppIcon;
  final double width;
  final double height;
  final bool active;
  final bool favorite;
  final Color glowColor;
  final Color accentColor;
  final Color favoriteColor;
  final Color surfaceColor;

  @override
  Widget build(BuildContext context) {
    final fallbackBadge = Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active
              ? [
                  surfaceColor.withValues(alpha: 0.92),
                  const Color(0xFF0E4588).withValues(alpha: 0.95),
                ]
              : [
                  Colors.black.withValues(alpha: 0.45),
                  surfaceColor.withValues(alpha: 0.55),
                ],
        ),
      ),
      child: Center(
        child: Text(
          title.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: glowColor,
            fontSize: active ? 13 : 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.9,
            height: 1.08,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.85),
                blurRadius: 4,
              ),
              if (active)
                Shadow(
                  color: accentColor.withValues(alpha: 0.75),
                  blurRadius: 10,
                ),
            ],
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active
                  ? glowColor.withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.22),
              width: active ? 2.0 : 1.0,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.40),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4.5),
            child: artPath != null && isSquareAppIcon
                ? Container(
                    width: width,
                    height: height,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: active
                            ? [
                                const Color(0xFFDCE8F4).withValues(alpha: 0.94),
                                const Color(0xFF93ABC2).withValues(alpha: 0.88),
                              ]
                            : [
                                const Color(0xFFC4D4E4).withValues(alpha: 0.72),
                                surfaceColor.withValues(alpha: 0.72),
                              ],
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: BudgetImage.file(
                            artPath,
                            width: height - 10,
                            height: height - 10,
                            fit: BoxFit.contain,
                            placeholder: fallbackBadge,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active
                                  ? const Color(0xFF0A1D37)
                                  : glowColor,
                              fontSize: active ? 11 : 9.5,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : artPath != null
                ? BudgetImage.file(
                    artPath,
                    width: width,
                    height: height,
                    placeholder: fallbackBadge,
                  )
                : fallbackBadge,
          ),
        ),
        if (favorite)
          Positioned(
            top: -5,
            right: -5,
            child: Icon(Icons.star_rounded, size: 15, color: favoriteColor),
          ),
      ],
    );
  }
}

class _PspPlatformBadge extends StatelessWidget {
  const _PspPlatformBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE5ECF4), Color(0xFF7D8FA3)],
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0A1424),
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

class _PspEmptyGamesSpine extends StatelessWidget {
  const _PspEmptyGamesSpine({
    required this.compact,
    required this.topPad,
    required this.addNode,
    required this.rescanNode,
    required this.accentColor,
    required this.glowColor,
    required this.fgColor,
    required this.surfaceColor,
    this.onAddApps,
    this.onRescan,
  });

  final bool compact;
  final double topPad;
  final FocusNode addNode;
  final FocusNode rescanNode;
  final Color accentColor;
  final Color glowColor;
  final Color fgColor;
  final Color surfaceColor;
  final VoidCallback? onAddApps;
  final VoidCallback? onRescan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nenhum jogo adicionado na biblioteca',
            style: TextStyle(
              color: glowColor,
              fontSize: compact ? 15 : 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _PspPillButton(
                focusNode: addNode,
                label: 'Selecionar Jogos Instalados',
                icon: Icons.sports_esports_rounded,
                accentColor: accentColor,
                fgColor: fgColor,
                surfaceColor: surfaceColor,
                onActivate: onAddApps,
              ),
              _PspPillButton(
                focusNode: rescanNode,
                label: 'Reescanear [SELECT]',
                icon: Icons.refresh_rounded,
                accentColor: accentColor,
                fgColor: fgColor,
                surfaceColor: surfaceColor,
                onActivate: onRescan,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PspPillButton extends StatefulWidget {
  const _PspPillButton({
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
  State<_PspPillButton> createState() => _PspPillButtonState();
}

class _PspPillButtonState extends State<_PspPillButton> {
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _focused
                ? widget.accentColor.withValues(alpha: 0.25)
                : widget.surfaceColor.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _focused
                  ? Colors.white
                  : widget.fgColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 17, color: widget.fgColor),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.fgColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PspMenuOptionRow extends StatefulWidget {
  const _PspMenuOptionRow({
    required this.option,
    required this.focusNode,
    required this.fgColor,
    required this.accentColor,
    required this.glowColor,
    required this.mutedColor,
    required this.surfaceColor,
    this.autofocus = false,
  });

  final _XmbActionOption option;
  final FocusNode focusNode;
  final bool autofocus;
  final Color fgColor;
  final Color accentColor;
  final Color glowColor;
  final Color mutedColor;
  final Color surfaceColor;

  @override
  State<_PspMenuOptionRow> createState() => _PspMenuOptionRowState();
}

class _PspMenuOptionRowState extends State<_PspMenuOptionRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.option.onTrigger?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: () {
          widget.focusNode.requestFocus();
          widget.option.onTrigger?.call();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _focused
                ? widget.surfaceColor.withValues(alpha: 0.75)
                : Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused
                  ? widget.glowColor.withValues(alpha: 0.88)
                  : widget.fgColor.withValues(alpha: 0.14),
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.30),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.option.icon,
                size: 24,
                color: _focused ? widget.glowColor : widget.accentColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.option.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _focused ? widget.glowColor : widget.fgColor,
                        fontSize: 14,
                        fontWeight: _focused
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.option.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: widget.mutedColor, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PspOptionsOverlay extends StatelessWidget {
  const _PspOptionsOverlay({
    required this.options,
    required this.firstFocusNode,
    required this.menuNodeFor,
    required this.surfaceColor,
    required this.fgColor,
    required this.accentColor,
    required this.glowColor,
    required this.mutedColor,
    required this.onClose,
  });

  final List<_XmbActionOption> options;
  final FocusNode firstFocusNode;
  final FocusNode Function(String id) menuNodeFor;
  final Color surfaceColor;
  final Color fgColor;
  final Color accentColor;
  final Color glowColor;
  final Color mutedColor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: 0.94),
        border: Border(
          left: BorderSide(
            color: glowColor.withValues(alpha: 0.45),
            width: 1.2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'OPTIONS',
                  style: TextStyle(
                    color: glowColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: fgColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    'Fechar [B]',
                    style: TextStyle(color: fgColor, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: ListView.separated(
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final opt = options[index];
                  final node = index == 0
                      ? firstFocusNode
                      : menuNodeFor(opt.id);
                  return FocusTraversalOrder(
                    order: NumericFocusOrder(index.toDouble()),
                    child: _PspMenuOptionRow(
                      option: opt,
                      focusNode: node,
                      autofocus: index == 0,
                      fgColor: fgColor,
                      accentColor: accentColor,
                      glowColor: glowColor,
                      mutedColor: mutedColor,
                      surfaceColor: surfaceColor,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
