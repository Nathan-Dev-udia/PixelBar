import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/gamepad_input.dart';
import '../../core/media/budget_image.dart';
import '../../core/state/library_controller.dart';
import '../../domain/models/theme_manifest.dart';

/// Gamepad-first & touch-accessible modal for browsing/importing community
/// `.zip`/`.ondatheme` packages and editing active theme color tokens.
class ThemeManagerDialog extends ConsumerStatefulWidget {
  const ThemeManagerDialog({super.key});

  @override
  ConsumerState<ThemeManagerDialog> createState() => _ThemeManagerDialogState();
}

class _ThemeManagerDialogState extends ConsumerState<ThemeManagerDialog> {
  int _tabIndex = 0;
  List<ThemeManifest> _themes = const [];
  bool _loadingThemes = true;
  bool _busy = false;
  String? _statusMessage;
  bool _isError = false;

  late String _editingThemeId;
  Map<String, int> _draftColors = {};
  String? _selectedToken;
  final TextEditingController _hexController = TextEditingController();

  static const List<int> _quickPalette = [
    0xFF00E5FF,
    0xFF3B82F6,
    0xFF6366F1,
    0xFFA855F7,
    0xFFEC4899,
    0xFFFF5370,
    0xFFFF9800,
    0xFFFFC400,
    0xFF10B981,
    0xFF0B0D10,
    0xFF161B22,
    0xFFE6E6E6,
  ];

  @override
  void initState() {
    super.initState();
    final activeTheme = ref.read(libraryControllerProvider).theme;
    _initEditorFor(activeTheme);
    _reloadThemes();
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _initEditorFor(ThemeManifest theme) {
    _editingThemeId = theme.id;
    _draftColors = Map<String, int>.of(theme.colors);
    _selectedToken = _draftColors.isNotEmpty ? _draftColors.keys.first : null;
    _syncHexField();
  }

  void _syncHexField() {
    final token = _selectedToken;
    if (token != null && _draftColors.containsKey(token)) {
      _hexController.text = ThemeManifest.formatColorHex(_draftColors[token]!);
    } else {
      _hexController.text = '';
    }
  }

  Future<void> _reloadThemes({String? focusThemeId}) async {
    setState(() => _loadingThemes = true);
    try {
      final list = await ref
          .read(libraryControllerProvider.notifier)
          .listThemes();
      if (!mounted) return;
      final targetId =
          focusThemeId ?? ref.read(libraryControllerProvider).theme.id;
      final matched = list.where((t) => t.id == targetId).firstOrNull;
      setState(() {
        _themes = list;
        _loadingThemes = false;
        if (matched != null) {
          _initEditorFor(matched);
        } else if (list.isNotEmpty) {
          _initEditorFor(list.first);
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingThemes = false;
        _setBanner('Erro ao listar temas: $e', isError: true);
      });
    }
  }

  void _setBanner(String message, {required bool isError}) {
    _statusMessage = message;
    _isError = isError;
  }

  Future<void> _importTheme() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final imported = await ref
          .read(libraryControllerProvider.notifier)
          .importThemeFromSaf();
      if (!mounted) return;
      if (imported == null) {
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _busy = false;
        _setBanner(
          'Tema "${imported.name}" importado e ativado!',
          isError: false,
        );
      });
      await _reloadThemes(focusThemeId: imported.id);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _setBanner('Falha ao importar tema: $e', isError: true);
      });
    }
  }

  Future<void> _activateTheme(ThemeManifest theme) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(libraryControllerProvider.notifier)
          .activateTheme(theme.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _initEditorFor(theme);
        _setBanner('Tema "${theme.name}" ativado.', isError: false);
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _setBanner('Erro ao ativar tema: $e', isError: true);
      });
    }
  }

  Future<void> _deleteTheme(ThemeManifest theme) async {
    if (_busy || theme.isBuiltIn) return;
    setState(() => _busy = true);
    try {
      await ref.read(libraryControllerProvider.notifier).deleteTheme(theme.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _setBanner('Tema "${theme.name}" excluído.', isError: false);
      });
      await _reloadThemes();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _setBanner('Erro ao excluir tema: $e', isError: true);
      });
    }
  }

  Future<void> _saveDraftColors() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(libraryControllerProvider.notifier)
          .saveThemeColorOverrides(_editingThemeId, _draftColors);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _setBanner('Cores salvas em user_overrides.json!', isError: false);
      });
      await _reloadThemes(focusThemeId: _editingThemeId);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _setBanner('Erro ao salvar cores: $e', isError: true);
      });
    }
  }

  Future<void> _resetColors() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(libraryControllerProvider.notifier)
          .resetThemeColorOverrides(_editingThemeId);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _setBanner('Cores restauradas para o padrão original.', isError: false);
      });
      await _reloadThemes(focusThemeId: _editingThemeId);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _setBanner('Erro ao restaurar cores: $e', isError: true);
      });
    }
  }

  void _updateSelectedColor(int argb) {
    final token = _selectedToken;
    if (token == null) return;
    setState(() {
      _draftColors[token] = argb;
      _syncHexField();
    });
  }

  void _applyHexInput() {
    try {
      final parsed = parseColor(_hexController.text);
      _updateSelectedColor(parsed);
      setState(() {
        _setBanner('Cor hexadecimal aplicada.', isError: false);
      });
    } on Object {
      setState(() {
        _setBanner('Hex inválido. Use #RRGGBB ou #AARRGGBB.', isError: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeThemeId = ref.watch(libraryControllerProvider).theme.id;

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
              _tabIndex = (_tabIndex + intent.delta) % 2;
              if (_tabIndex < 0) _tabIndex += 2;
            });
            return null;
          },
        ),
      },
      child: Dialog(
        backgroundColor: const Color(0xFF12161C),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780, maxHeight: 460),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'TEMAS & EDITOR DE CORES',
                        style: TextStyle(
                          color: Color(0xFF00E5FF),
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _TabButton(
                      label: '[L1] Temas',
                      active: _tabIndex == 0,
                      onTap: () => setState(() => _tabIndex = 0),
                    ),
                    const SizedBox(width: 8),
                    _TabButton(
                      label: '[R1] Editor de Cores',
                      active: _tabIndex == 1,
                      onTap: () => setState(() => _tabIndex = 1),
                    ),
                    const SizedBox(width: 8),
                    _FocusableButton(
                      label: 'Fechar [B]',
                      compact: true,
                      onActivate: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                if (_statusMessage case final msg?) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (_isError
                                  ? const Color(0xFFFF5370)
                                  : const Color(0xFF10B981))
                              .withValues(alpha: 0.16),
                      border: Border.all(
                        color: _isError
                            ? const Color(0xFFFF5370)
                            : const Color(0xFF10B981),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      msg,
                      style: TextStyle(
                        color: _isError
                            ? const Color(0xFFFF5370)
                            : const Color(0xFF10B981),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: _tabIndex == 0
                      ? _buildThemesTab(activeThemeId)
                      : _buildColorEditorTab(),
                ),
                const SizedBox(height: 8),
                const Text(
                  '[D-Pad] Navegar   [A] Ativar / Ajustar   [L1/R1] Alternar Aba   [B] Voltar',
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

  Widget _buildThemesTab(String activeThemeId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FocusableButton(
          autofocus: true,
          label: _busy
              ? 'Processando pacote em Isolate...'
              : 'Importar Tema (.zip / .ondatheme)',
          icon: Icons.folder_zip_outlined,
          accentHighlight: true,
          onActivate: _busy ? null : _importTheme,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _loadingThemes
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: _themes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final theme = _themes[index];
                    final isActive = theme.id == activeThemeId;
                    return _ThemeListTile(
                      theme: theme,
                      isActive: isActive,
                      onActivate: () => _activateTheme(theme),
                      onEditColors: () {
                        setState(() {
                          _initEditorFor(theme);
                          _tabIndex = 1;
                        });
                      },
                      onDelete: theme.isBuiltIn
                          ? null
                          : () => _deleteTheme(theme),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildColorEditorTab() {
    if (_draftColors.isEmpty) {
      return const Center(
        child: Text(
          'Este tema não declarou tokens editáveis em "colors".',
          style: TextStyle(color: Color(0xFF8C96A5)),
        ),
      );
    }

    final entries = _draftColors.entries.toList();
    final token = _selectedToken ?? entries.first.key;
    final currentArgb = _draftColors[token] ?? 0xFF00E5FF;
    final hsv = HSVColor.fromColor(Color(currentArgb));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 240,
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final selected = entry.key == token;
              return _ColorTokenTile(
                autofocus: index == 0,
                token: entry.key,
                argb: entry.value,
                selected: selected,
                onSelect: () {
                  setState(() {
                    _selectedToken = entry.key;
                    _syncHexField();
                  });
                },
              );
            },
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(currentArgb),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white54),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Token: $token',
                            style: const TextStyle(
                              color: Color(0xFFE6E6E6),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            ThemeManifest.formatColorHex(currentArgb),
                            style: const TextStyle(
                              color: Color(0xFF8C96A5),
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _GamepadHsvSlider(
                  label: 'Matiz (H)',
                  value: hsv.hue / 360.0,
                  displayValue: '${hsv.hue.round()}°',
                  trackGradient: const [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                  onChanged: (v) => _updateSelectedColor(
                    hsv
                        .withHue((v * 360.0).clamp(0.0, 359.0))
                        .toColor()
                        .toARGB32(),
                  ),
                ),
                const SizedBox(height: 6),
                _GamepadHsvSlider(
                  label: 'Saturação (S)',
                  value: hsv.saturation,
                  displayValue: '${(hsv.saturation * 100).round()}%',
                  trackGradient: [
                    hsv.withSaturation(0).toColor(),
                    hsv.withSaturation(1).toColor(),
                  ],
                  onChanged: (v) => _updateSelectedColor(
                    hsv.withSaturation(v.clamp(0.0, 1.0)).toColor().toARGB32(),
                  ),
                ),
                const SizedBox(height: 6),
                _GamepadHsvSlider(
                  label: 'Brilho (V)',
                  value: hsv.value,
                  displayValue: '${(hsv.value * 100).round()}%',
                  trackGradient: [Colors.black, hsv.withValue(1).toColor()],
                  onChanged: (v) => _updateSelectedColor(
                    hsv.withValue(v.clamp(0.0, 1.0)).toColor().toARGB32(),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _quickPalette)
                      _PaletteSwatchButton(
                        argb: c,
                        selected: c == currentArgb,
                        onSelect: () => _updateSelectedColor(c),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _hexController,
                          style: const TextStyle(
                            color: Color(0xFFE6E6E6),
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '#RRGGBB',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: (_) => _applyHexInput(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FocusableButton(
                      label: 'Aplicar Hex',
                      compact: true,
                      onActivate: _applyHexInput,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _FocusableButton(
                      label: 'Salvar Cores',
                      icon: Icons.save_outlined,
                      accentHighlight: true,
                      onActivate: _busy ? null : _saveDraftColors,
                    ),
                    _FocusableButton(
                      label: 'Restaurar Padrão',
                      icon: Icons.restore,
                      onActivate: _busy ? null : _resetColors,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF00E5FF).withValues(alpha: 0.18)
                : const Color(0xFF1A2029),
            border: Border.all(
              color: active ? const Color(0xFF00E5FF) : const Color(0xFF2D3542),
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFF00E5FF) : const Color(0xFFE6E6E6),
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeListTile extends StatelessWidget {
  const _ThemeListTile({
    required this.theme,
    required this.isActive,
    required this.onActivate,
    required this.onEditColors,
    this.onDelete,
  });

  final ThemeManifest theme;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onEditColors;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bg = Color(theme.color('background', 0xFF0B0D10));
    final primary = Color(theme.color('primary', 0xFF12161C));
    final accent = Color(theme.color('accent', 0xFF00E5FF));
    final fg = Color(theme.color('textPrimary', 0xFFE6E6E6));

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2029),
        border: Border.all(
          color: isActive ? const Color(0xFF00E5FF) : const Color(0xFF2D3542),
          width: isActive ? 1.6 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: theme.previewImage != null
                ? BudgetImage.file(
                    theme.previewImage,
                    width: 84,
                    height: 52,
                    placeholder: _swatchPreview(bg, primary, accent, fg),
                  )
                : _swatchPreview(bg, primary, accent, fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      theme.name,
                      style: const TextStyle(
                        color: Color(0xFFE6E6E6),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _Badge(
                      label: theme.isBuiltIn ? 'BUILT-IN' : 'IMPORTADO',
                      color: theme.isBuiltIn
                          ? const Color(0xFF7A8494)
                          : const Color(0xFFA855F7),
                    ),
                    if (isActive)
                      const _Badge(label: 'ATIVO', color: Color(0xFF00E5FF)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'por ${theme.author} • v${theme.version}',
                  style: const TextStyle(
                    color: Color(0xFF8C96A5),
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                if (theme.description.isNotEmpty)
                  Text(
                    theme.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 6,
            children: [
              if (!isActive)
                _FocusableButton(
                  label: 'Ativar',
                  compact: true,
                  onActivate: onActivate,
                ),
              _FocusableButton(
                label: 'Cores',
                compact: true,
                onActivate: onEditColors,
              ),
              if (onDelete != null)
                _FocusableButton(
                  label: 'Excluir',
                  compact: true,
                  danger: true,
                  onActivate: onDelete,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _swatchPreview(Color bg, Color primary, Color accent, Color fg) =>
      SizedBox(
        width: 84,
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: ColoredBox(color: bg, child: const SizedBox.expand()),
            ),
            Expanded(
              child: ColoredBox(color: primary, child: const SizedBox.expand()),
            ),
            Expanded(
              child: ColoredBox(color: accent, child: const SizedBox.expand()),
            ),
            Expanded(
              child: ColoredBox(color: fg, child: const SizedBox.expand()),
            ),
          ],
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ColorTokenTile extends StatefulWidget {
  const _ColorTokenTile({
    required this.token,
    required this.argb,
    required this.selected,
    required this.onSelect,
    this.autofocus = false,
  });

  final String token;
  final int argb;
  final bool selected;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  State<_ColorTokenTile> createState() => _ColorTokenTileState();
}

class _ColorTokenTileState extends State<_ColorTokenTile> {
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
            duration: const Duration(milliseconds: 110),
          );
        }
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _focused || widget.selected
                ? const Color(0xFF00E5FF).withValues(alpha: 0.14)
                : const Color(0xFF1A2029),
            border: Border.all(
              color: _focused
                  ? const Color(0xFF00E5FF)
                  : (widget.selected
                        ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                        : const Color(0xFF2D3542)),
              width: _focused ? 1.8 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Color(widget.argb),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white54),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.token,
                  style: TextStyle(
                    color: _focused
                        ? const Color(0xFF00E5FF)
                        : const Color(0xFFE6E6E6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                ThemeManifest.formatColorHex(widget.argb),
                style: const TextStyle(
                  color: Color(0xFF7A8494),
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GamepadHsvSlider extends StatefulWidget {
  const _GamepadHsvSlider({
    required this.label,
    required this.value,
    required this.displayValue,
    required this.trackGradient,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String displayValue;
  final List<Color> trackGradient;
  final ValueChanged<double> onChanged;

  @override
  State<_GamepadHsvSlider> createState() => _GamepadHsvSliderState();
}

class _GamepadHsvSliderState extends State<_GamepadHsvSlider> {
  bool _focused = false;

  void _updateFromLocalOffset(double dx, double width) {
    if (width <= 0) return;
    widget.onChanged((dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.onChanged((widget.value - 0.05).clamp(0.0, 1.0));
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          widget.onChanged((widget.value + 0.05).clamp(0.0, 1.0));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: _focused
                      ? const Color(0xFF00E5FF)
                      : const Color(0xFFE6E6E6),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                widget.displayValue,
                style: const TextStyle(
                  color: Color(0xFF8C96A5),
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final knobX = (widget.value.clamp(0.0, 1.0) * (width - 14)).clamp(
                0.0,
                (width - 14).clamp(0.0, width),
              );
              return GestureDetector(
                onTapDown: (d) =>
                    _updateFromLocalOffset(d.localPosition.dx, width),
                onHorizontalDragUpdate: (d) =>
                    _updateFromLocalOffset(d.localPosition.dx, width),
                child: Container(
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: widget.trackGradient),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: _focused
                          ? const Color(0xFF00E5FF)
                          : Colors.white24,
                      width: _focused ? 2 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: knobX,
                        top: 1,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black54),
                          ),
                        ),
                      ),
                    ],
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

class _PaletteSwatchButton extends StatefulWidget {
  const _PaletteSwatchButton({
    required this.argb,
    required this.selected,
    required this.onSelect,
  });

  final int argb;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<_PaletteSwatchButton> createState() => _PaletteSwatchButtonState();
}

class _PaletteSwatchButtonState extends State<_PaletteSwatchButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onFocusChange: (f) => setState(() => _focused = f),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Color(widget.argb),
            shape: BoxShape.circle,
            border: Border.all(
              color: _focused
                  ? const Color(0xFF00E5FF)
                  : (widget.selected ? Colors.white : Colors.white24),
              width: _focused || widget.selected ? 2.2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableButton extends StatefulWidget {
  const _FocusableButton({
    required this.label,
    required this.onActivate,
    this.icon,
    this.autofocus = false,
    this.compact = false,
    this.accentHighlight = false,
    this.danger = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onActivate;
  final bool autofocus;
  final bool compact;
  final bool accentHighlight;
  final bool danger;

  @override
  State<_FocusableButton> createState() => _FocusableButtonState();
}

class _FocusableButtonState extends State<_FocusableButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.danger
        ? const Color(0xFFFF5370)
        : (widget.accentHighlight
              ? const Color(0xFF00E5FF)
              : const Color(0xFFE6E6E6));
    return FocusableActionDetector(
      autofocus: widget.autofocus,
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
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 10 : 14,
            vertical: widget.compact ? 6 : 9,
          ),
          decoration: BoxDecoration(
            color: _focused
                ? baseColor.withValues(alpha: 0.2)
                : const Color(0xFF1A2029),
            border: Border.all(
              color: _focused ? baseColor : baseColor.withValues(alpha: 0.35),
              width: _focused ? 1.8 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: baseColor),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: baseColor,
                  fontSize: widget.compact ? 11 : 12,
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
