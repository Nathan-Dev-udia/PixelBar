import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/gamepad_input.dart';
import '../../core/media/budget_image.dart';
import '../../core/state/library_controller.dart';
import '../../data/metadata/game_metadata_service.dart';
import '../../domain/models/game_item.dart';

enum _EditorTab { download, general, media }

/// Playnite-style game metadata editor and online downloader.
class GameMetadataEditorDialog extends ConsumerStatefulWidget {
  const GameMetadataEditorDialog({super.key, required this.game});

  final GameItem game;

  @override
  ConsumerState<GameMetadataEditorDialog> createState() =>
      _GameMetadataEditorDialogState();
}

class _GameMetadataEditorDialogState
    extends ConsumerState<GameMetadataEditorDialog> {
  _EditorTab _tab = _EditorTab.download;
  late GameItem _currentGame;

  late TextEditingController _searchCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _platformCtrl;
  late TextEditingController _devCtrl;
  late TextEditingController _yearCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _sgdbKeyCtrl;

  bool _searching = false;
  bool _busy = false;
  bool _showKeyConfig = false;
  String? _bannerText;
  bool _bannerIsError = false;
  List<MetadataCandidate> _results = const [];

  bool _applyText = true;
  bool _dlBanner = true;
  bool _dlLogo = true;
  bool _dlBackground = true;
  bool _dlCover = true;
  bool _dlIcon = true;

  @override
  void initState() {
    super.initState();
    _currentGame = widget.game;
    _searchCtrl = TextEditingController(text: _currentGame.title);
    _titleCtrl = TextEditingController(text: _currentGame.title);
    _platformCtrl = TextEditingController(text: _currentGame.platform);
    _devCtrl = TextEditingController(text: _currentGame.developer ?? '');
    _yearCtrl = TextEditingController(text: _currentGame.releaseYear ?? '');
    _descCtrl = TextEditingController(text: _currentGame.description ?? '');
    _sgdbKeyCtrl = TextEditingController(
      text: ref.read(libraryControllerProvider).settings.steamGridDbApiKey,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _titleCtrl.dispose();
    _platformCtrl.dispose();
    _devCtrl.dispose();
    _yearCtrl.dispose();
    _descCtrl.dispose();
    _sgdbKeyCtrl.dispose();
    super.dispose();
  }

  void _syncControllers(GameItem game) {
    _currentGame = game;
    _searchCtrl.text = game.title;
    _titleCtrl.text = game.title;
    _platformCtrl.text = game.platform;
    _devCtrl.text = game.developer ?? '';
    _yearCtrl.text = game.releaseYear ?? '';
    _descCtrl.text = game.description ?? '';
  }

  void _setBanner(String message, {bool isError = false}) {
    setState(() {
      _bannerText = message;
      _bannerIsError = isError;
    });
  }

  void _cycleTab(int delta) {
    const values = _EditorTab.values;
    final next = (values.indexOf(_tab) + delta) % values.length;
    setState(() {
      _tab = values[next < 0 ? next + values.length : next];
    });
  }

  Future<void> _runSearch() async {
    if (_searching || _busy) return;
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      _setBanner('Digite o nome do jogo para buscar.', isError: true);
      return;
    }
    setState(() {
      _searching = true;
      _bannerText = null;
    });
    try {
      final settings = ref.read(libraryControllerProvider).settings;
      final candidates = await ref
          .read(gameMetadataServiceProvider)
          .search(query, steamGridDbApiKey: settings.steamGridDbApiKey);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _results = candidates;
        if (candidates.isEmpty) {
          _bannerText = 'Nenhum resultado encontrado para "$query".';
          _bannerIsError = true;
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      _setBanner('Falha ao buscar metadados: $e', isError: true);
    }
  }

  Future<void> _applyCandidate(MetadataCandidate candidate) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(libraryControllerProvider.notifier)
          .downloadMetadataForGame(
            _currentGame,
            candidate,
            applyText: _applyText,
            downloadIcon: _dlIcon,
            downloadLogo: _dlLogo,
            downloadCover: _dlCover,
            downloadBanner: _dlBanner,
            downloadBackground: _dlBackground,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _syncControllers(updated);
      });
      _setBanner('Metadados e mídias aplicados para "${updated.title}"!');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _setBanner('Erro ao baixar metadados: $e', isError: true);
    }
  }

  Future<void> _saveApiKey() async {
    if (_busy) return;
    final currentSettings = ref.read(libraryControllerProvider).settings;
    await ref
        .read(libraryControllerProvider.notifier)
        .updateSettings(
          currentSettings.copyWith(steamGridDbApiKey: _sgdbKeyCtrl.text.trim()),
        );
    if (!mounted) return;
    _setBanner('Chave SteamGridDB salva nas configurações.');
  }

  Future<void> _saveGeneralFields() async {
    if (_busy) return;
    final nextTitle = _titleCtrl.text.trim();
    if (nextTitle.isEmpty) {
      _setBanner('O nome do jogo não pode ficar vazio.', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = _currentGame.copyWith(
        title: nextTitle,
        platform: _platformCtrl.text.trim().isEmpty
            ? _currentGame.platform
            : _platformCtrl.text.trim(),
        developer: _devCtrl.text.trim(),
        releaseYear: _yearCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        titleCustomized: true,
      );
      await ref.read(libraryControllerProvider.notifier).updateGame(updated);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _syncControllers(updated);
      });
      _setBanner('Metadados salvos para "${updated.title}"!');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _setBanner('Erro ao salvar alterações: $e', isError: true);
    }
  }

  Future<void> _pickLocalArtwork({
    required String slot,
    required int maxWidth,
    required int maxHeight,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final gateway = ref.read(launcherGatewayProvider);
      final picked = await gateway.pickFile(mimeTypes: const ['image/*']);
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final importedPath = await gateway.importArtwork(
        picked.uri,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      if (!mounted) return;
      if (importedPath.isEmpty) {
        setState(() => _busy = false);
        _setBanner(
          'Não foi possível importar a imagem selecionada.',
          isError: true,
        );
        return;
      }
      final nextMedia = switch (slot) {
        'banner' => _currentGame.media.copyWith(bannerPath: importedPath),
        'logo' => _currentGame.media.copyWith(logoPath: importedPath),
        'background' => _currentGame.media.copyWith(
          backgroundPath: importedPath,
        ),
        'cover' => _currentGame.media.copyWith(coverPath: importedPath),
        _ => _currentGame.media.copyWith(iconPath: importedPath),
      };
      final updated = _currentGame.copyWith(media: nextMedia);
      await ref.read(libraryControllerProvider.notifier).updateGame(updated);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _currentGame = updated;
      });
      _setBanner('Imagem local aplicada ao jogo!');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _setBanner('Falha ao importar imagem local: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            _cycleTab(intent.delta);
            return null;
          },
        ),
      },
      child: Dialog(
        backgroundColor: const Color(0xFF0F131A),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                if (_bannerText != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (_bannerIsError
                                  ? const Color(0xFFFF5370)
                                  : const Color(0xFF00E5FF))
                              .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _bannerIsError
                            ? const Color(0xFFFF5370)
                            : const Color(0xFF00E5FF),
                      ),
                    ),
                    child: Text(
                      _bannerText!,
                      style: TextStyle(
                        color: _bannerIsError
                            ? const Color(0xFFFF8A9B)
                            : const Color(0xFF9DF4FF),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: switch (_tab) {
                    _EditorTab.download => _buildDownloadTab(),
                    _EditorTab.general => _buildGeneralTab(),
                    _EditorTab.media => _buildLocalMediaTab(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EDITAR JOGO & METADADOS (PLAYNITE)',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _currentGame.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _EditorTabButton(
              label: '[L1] Baixar Metadados',
              active: _tab == _EditorTab.download,
              onTap: () => setState(() => _tab = _EditorTab.download),
            ),
            _EditorTabButton(
              label: 'Geral (Nome & Descrição)',
              active: _tab == _EditorTab.general,
              onTap: () => setState(() => _tab = _EditorTab.general),
            ),
            _EditorTabButton(
              label: '[R1] Mídia Local (SAF)',
              active: _tab == _EditorTab.media,
              onTap: () => setState(() => _tab = _EditorTab.media),
            ),
            _EditorTabButton(
              label: 'Fechar [B]',
              active: false,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Color(0xFFE6E6E6), fontSize: 13),
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText:
                      'Nome do jogo (ex: God of War Collection, Super Mario, Zelda, Hades)',
                  hintStyle: const TextStyle(color: Color(0xFF5A6270)),
                  filled: true,
                  fillColor: const Color(0xFF171D26),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF2D3748)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: (_searching || _busy) ? null : _runSearch,
              icon: _searching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 17),
              label: const Text('Buscar Metadados'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _OptionChip(
              label: 'Nome & Descrição',
              selected: _applyText,
              onToggle: () => setState(() => _applyText = !_applyText),
            ),
            _OptionChip(
              label: 'Banner/ICON0',
              selected: _dlBanner,
              onToggle: () => setState(() => _dlBanner = !_dlBanner),
            ),
            _OptionChip(
              label: 'Logo',
              selected: _dlLogo,
              onToggle: () => setState(() => _dlLogo = !_dlLogo),
            ),
            _OptionChip(
              label: 'Fundo',
              selected: _dlBackground,
              onToggle: () => setState(() => _dlBackground = !_dlBackground),
            ),
            _OptionChip(
              label: 'Capa',
              selected: _dlCover,
              onToggle: () => setState(() => _dlCover = !_dlCover),
            ),
            _OptionChip(
              label: 'Ícone',
              selected: _dlIcon,
              onToggle: () => setState(() => _dlIcon = !_dlIcon),
            ),
            TextButton(
              onPressed: () => setState(() => _showKeyConfig = !_showKeyConfig),
              child: Text(
                _showKeyConfig
                    ? 'Ocultar SteamGridDB Key'
                    : 'SteamGridDB Key (opcional)',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        if (_showKeyConfig) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _sgdbKeyCtrl,
                  style: const TextStyle(
                    color: Color(0xFFE6E6E6),
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Cole sua SteamGridDB API Key v2 (opcional)',
                    hintStyle: const TextStyle(color: Color(0xFF5A6270)),
                    filled: true,
                    fillColor: const Color(0xFF171D26),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _saveApiKey,
                child: const Text('Salvar Chave'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _searching
                        ? 'Consultando Steam, Nintendo, Wikipedia (PS2/PS3/Retro) e SteamGridDB...'
                        : 'Toque em "Buscar Metadados" para buscar em Steam, Nintendo e Wikipedia (PS2/PS3/PSP/Retro).',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF7A8494),
                      fontSize: 12.5,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    final metaLine = [
                      item.provider,
                      if (item.releaseYear != null) item.releaseYear!,
                      if (item.developer != null) item.developer!,
                    ].join(' • ');
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171D26),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2D3748)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFF4F9FF),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  metaLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF8AA0B8),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _busy
                                ? null
                                : () => _applyCandidate(item),
                            child: const Text('Baixar & Aplicar'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGeneralTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabeledField(label: 'Nome do Jogo', controller: _titleCtrl),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _LabeledField(
                  label: 'Plataforma',
                  controller: _platformCtrl,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LabeledField(
                  label: 'Desenvolvedor',
                  controller: _devCtrl,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: _LabeledField(
                  label: 'Ano de Lançamento',
                  controller: _yearCtrl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _LabeledField(label: 'Descrição', controller: _descCtrl, maxLines: 4),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _saveGeneralFields,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Salvar Alterações'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalMediaTab() {
    final slots = [
      (
        slot: 'banner',
        title: 'Banner 16:9 (ICON0)',
        path: _currentGame.media.bannerPath,
        maxWidth: 640,
        maxHeight: 360,
      ),
      (
        slot: 'logo',
        title: 'Logo Transparente (ClearLogo)',
        path: _currentGame.media.logoPath,
        maxWidth: 640,
        maxHeight: 360,
      ),
      (
        slot: 'background',
        title: 'Imagem de Fundo (Background)',
        path: _currentGame.media.backgroundPath,
        maxWidth: 1280,
        maxHeight: 720,
      ),
      (
        slot: 'cover',
        title: 'Capa Vertical (Cover)',
        path: _currentGame.media.coverPath,
        maxWidth: 480,
        maxHeight: 720,
      ),
      (
        slot: 'icon',
        title: 'Ícone (Icon)',
        path: _currentGame.media.iconPath,
        maxWidth: 256,
        maxHeight: 256,
      ),
    ];

    return ListView.separated(
      itemCount: slots.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = slots[index];
        final hasImage = item.path != null && item.path!.isNotEmpty;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF171D26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2D3748)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: hasImage
                    ? BudgetImage.file(
                        item.path,
                        width: 68,
                        height: 40,
                        fit: BoxFit.contain,
                      )
                    : Container(
                        width: 68,
                        height: 40,
                        color: const Color(0xFF0F131A),
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: Color(0xFF5A6270),
                          size: 18,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: Color(0xFFF4F9FF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      hasImage ? 'Configurado' : 'Padrão / Vazio',
                      style: TextStyle(
                        color: hasImage
                            ? const Color(0xFF5CE092)
                            : const Color(0xFF7A8494),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _pickLocalArtwork(
                        slot: item.slot,
                        maxWidth: item.maxWidth,
                        maxHeight: item.maxHeight,
                      ),
                child: const Text('Escolher Arquivo'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditorTabButton extends StatelessWidget {
  const _EditorTabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF00E5FF).withValues(alpha: 0.18)
              : const Color(0xFF171D26),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: active ? const Color(0xFF00E5FF) : const Color(0xFF2D3748),
          ),
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
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onToggle,
  });

  final String label;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) => onToggle(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8AA0B8),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Color(0xFFF4F9FF), fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFF171D26),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF2D3748)),
            ),
          ),
        ),
      ],
    );
  }
}
