import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Animated GPU background driven by a lightweight fragment shader — the
/// sanctioned replacement for animated `BackdropFilter` blur.
///
/// The ticker pauses automatically when the route is hidden ([TickerMode]),
/// and the widget is unmounted entirely during hard hibernation.
class ShaderBackground extends StatefulWidget {
  const ShaderBackground({
    super.key,
    required this.colorA,
    required this.colorB,
    this.asset = 'shaders/wave_background.frag',
    this.animate = true,
    this.child,
  });

  final String asset;
  final Color colorA;
  final Color colorB;
  final bool animate;
  final Widget? child;

  @override
  State<ShaderBackground> createState() => _ShaderBackgroundState();
}

class _ShaderBackgroundState extends State<ShaderBackground>
    with SingleTickerProviderStateMixin {
  static final Map<String, Future<ui.FragmentProgram>> _programs = {};

  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadProgram();
  }

  Future<void> _loadProgram() async {
    try {
      final program = await _programs.putIfAbsent(
        widget.asset,
        () => ui.FragmentProgram.fromAsset(widget.asset),
      );
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
      if (widget.animate) _ticker.start();
    } on Object {
      // Fallback to solid painter if shader compilation is unavailable on host.
    }
  }

  void _onTick(Duration elapsed) => _time.value = elapsed.inMicroseconds / 1e6;

  @override
  void didUpdateWidget(ShaderBackground old) {
    super.didUpdateWidget(old);
    if (_shader == null) return;
    if (widget.animate && !_ticker.isActive) _ticker.start();
    if (!widget.animate && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    return RepaintBoundary(
      child: CustomPaint(
        painter: shader == null
            ? _SolidPainter(widget.colorA)
            : _ShaderPainter(shader, _time, widget.colorA, widget.colorB),
        child: widget.child,
      ),
    );
  }
}

class _SolidPainter extends CustomPainter {
  const _SolidPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
  @override
  bool shouldRepaint(_SolidPainter old) => old.color != color;
}

class _ShaderPainter extends CustomPainter {
  _ShaderPainter(this.shader, this.time, this.colorA, this.colorB)
    : super(repaint: time);

  final ui.FragmentShader shader;
  final ValueNotifier<double> time;
  final Color colorA;
  final Color colorB;

  @override
  void paint(Canvas canvas, Size size) {
    var i = 0;
    shader
      ..setFloat(i++, size.width)
      ..setFloat(i++, size.height)
      ..setFloat(i++, time.value);
    for (final c in [colorA, colorB]) {
      shader
        ..setFloat(i++, c.r * c.a)
        ..setFloat(i++, c.g * c.a)
        ..setFloat(i++, c.b * c.a)
        ..setFloat(i++, c.a);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ShaderPainter old) =>
      old.shader != shader || old.colorA != colorA || old.colorB != colorB;
}
