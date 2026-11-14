import 'package:flutter/material.dart';

import '../../core/input/gamepad_input.dart';
import '../../data/update/app_update_service.dart';

enum _UpdateDialogPhase { ready, downloading, permissionRequired, error }

/// Console-styled auto-update modal navigable by gamepad D-Pad/A/B and touch.
class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
    required this.updateService,
  });

  final AppUpdateInfo updateInfo;
  final AppUpdateService updateService;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  _UpdateDialogPhase _phase = _UpdateDialogPhase.ready;
  double _progress = 0;
  int _receivedBytes = 0;
  int? _totalBytes;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _totalBytes = widget.updateInfo.assetSizeBytes;
  }

  Future<void> _startDownloadAndInstall() async {
    if (_phase == _UpdateDialogPhase.downloading) return;
    setState(() {
      _phase = _UpdateDialogPhase.downloading;
      _progress = 0;
      _receivedBytes = 0;
      _totalBytes = widget.updateInfo.assetSizeBytes;
      _errorMessage = null;
    });

    try {
      final launched = await widget.updateService.downloadAndInstall(
        widget.updateInfo,
        onProgress: (progress, received, total) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _receivedBytes = received;
            if (total != null && total > 0) {
              _totalBytes = total;
            }
          });
        },
      );
      if (!mounted) return;
      if (launched) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _phase = _UpdateDialogPhase.permissionRequired;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdateDialogPhase.error;
        _errorMessage = e.toString();
      });
    }
  }

  void _dismiss() {
    if (_phase == _UpdateDialogPhase.downloading) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.updateInfo;
    final notes = update.releaseNotes.isEmpty
        ? 'Nova build arm64 disponível no GitHub Releases (${update.assetName}).'
        : update.releaseNotes;

    return PopScope(
      canPop: _phase != _UpdateDialogPhase.downloading,
      child: Actions(
        actions: {
          GamepadBackIntent: CallbackAction<GamepadBackIntent>(
            onInvoke: (_) {
              _dismiss();
              return null;
            },
          ),
        },
        child: FocusScope(
          autofocus: true,
          child: Dialog(
            backgroundColor: const Color(0xFF12161C),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFF00E5FF), width: 1.4),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.system_update_rounded,
                          color: Color(0xFF00E5FF),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _phase == _UpdateDialogPhase.downloading
                                ? 'BAIXANDO ATUALIZAÇÃO'
                                : 'ATUALIZAÇÃO DISPONÍVEL',
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontFamily: 'monospace',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(
                                0xFF00E5FF,
                              ).withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            update.latestTag,
                            style: const TextStyle(
                              color: Color(0xFFE2E8F0),
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Versão instalada: v${update.currentVersion}  •  Nova: ${update.releaseName}',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_phase == _UpdateDialogPhase.downloading) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: _progress > 0 ? _progress : null,
                          backgroundColor: const Color(0xFF1E2633),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF00E5FF),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _formatProgressText(),
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ] else ...[
                      Container(
                        constraints: const BoxConstraints(maxHeight: 170),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1117),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF263040)),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            _bodyMessage(notes),
                            style: TextStyle(
                              color:
                                  _phase == _UpdateDialogPhase.error ||
                                      _phase ==
                                          _UpdateDialogPhase.permissionRequired
                                  ? const Color(0xFFFCA5A5)
                                  : const Color(0xFFCBD5E1),
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_phase == _UpdateDialogPhase.downloading)
                      const Text(
                        'A instalação abrirá automaticamente ao concluir o download.',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _ConsoleDialogButton(
                              autofocus: true,
                              primary: true,
                              label: _phase == _UpdateDialogPhase.ready
                                  ? 'Atualizar Agora'
                                  : 'Tentar Novamente',
                              hint: '[A]',
                              onActivate: _startDownloadAndInstall,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ConsoleDialogButton(
                              label: 'Depois',
                              hint: '[B]',
                              onActivate: _dismiss,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _bodyMessage(String defaultNotes) {
    switch (_phase) {
      case _UpdateDialogPhase.ready:
        return defaultNotes;
      case _UpdateDialogPhase.permissionRequired:
        return 'Permissão necessária: habilite "Instalar apps desconhecidos" '
            'para o OndaDeck nas configurações do Android e tente novamente.';
      case _UpdateDialogPhase.error:
        return 'Não foi possível concluir a atualização:\n'
            '${_errorMessage ?? "Erro desconhecido"}';
      case _UpdateDialogPhase.downloading:
        return '';
    }
  }

  String _formatProgressText() {
    final receivedMb = (_receivedBytes / (1024 * 1024)).toStringAsFixed(1);
    final total = _totalBytes;
    if (total != null && total > 0) {
      final percent = (_progress * 100).round().clamp(0, 100);
      final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
      return '$percent%  •  $receivedMb MB / $totalMb MB';
    }
    return '$receivedMb MB baixados...';
  }
}

class _ConsoleDialogButton extends StatefulWidget {
  const _ConsoleDialogButton({
    required this.label,
    required this.hint,
    required this.onActivate,
    this.autofocus = false,
    this.primary = false,
  });

  final String label;
  final String hint;
  final VoidCallback onActivate;
  final bool autofocus;
  final bool primary;

  @override
  State<_ConsoleDialogButton> createState() => _ConsoleDialogButtonState();
}

class _ConsoleDialogButtonState extends State<_ConsoleDialogButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.primary
        ? const Color(0xFF00E5FF)
        : const Color(0xFF94A3B8);

    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (_focused != focused) {
          setState(() => _focused = focused);
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: _focused
                ? accent.withValues(alpha: 0.22)
                : const Color(0xFF1A2029),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _focused ? accent : const Color(0xFF2D3542),
              width: _focused ? 1.8 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _focused ? accent : const Color(0xFFE2E8F0),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.hint,
                style: TextStyle(
                  color: _focused ? accent : const Color(0xFF64748B),
                  fontFamily: 'monospace',
                  fontSize: 11.5,
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
