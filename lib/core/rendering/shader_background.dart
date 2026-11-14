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

/// Static dark wireframe cyber-grid background used by the Default theme so it
/// stays visually distinct from the PSP XMB silk wave ribbons.
class OndaGridBackground extends StatelessWidget {
  const OndaGridBackground({
    super.key,
    required this.colorA,
    required this.colorB,
    this.accentColor = const Color(0xFF00E5FF),
    this.child,
  });

  final Color colorA;
  final Color colorB;
  final Color accentColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _OndaGridPainter(
          colorA: colorA,
          colorB: colorB,
          accentColor: accentColor,
        ),
        child: child,
      ),
    );
  }
}

class _OndaGridPainter extends CustomPainter {
  const _OndaGridPainter({
    required this.colorA,
    required this.colorB,
    required this.accentColor,
  });

  final Color colorA;
  final Color colorB;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colorA, colorB],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.55),
        radius: 0.95,
        colors: [
          accentColor.withValues(alpha: 0.14),
          accentColor.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, glowPaint);

    final gridPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.08)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const horizontalStep = 44.0;
    for (double y = horizontalStep; y < size.height; y += horizontalStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Subtle perspective vertical grid lines fanning slightly toward the bottom edge.
    const columns = 14;
    final centerX = size.width * 0.5;
    final topStep = size.width / columns;
    final bottomSpread = size.width * 1.28 / columns;
    for (var i = -columns ~/ 2; i <= columns ~/ 2; i++) {
      final topX = centerX + i * topStep;
      final bottomX = centerX + i * bottomSpread;
      canvas.drawLine(Offset(topX, 0), Offset(bottomX, size.height), gridPaint);
    }

    // Corner HUD bracket accents.
    final bracketPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.14)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const inset = 16.0;
    const arm = 18.0;
    // Top-left
    canvas.drawLine(
      const Offset(inset, inset),
      const Offset(inset + arm, inset),
      bracketPaint,
    );
    canvas.drawLine(
      const Offset(inset, inset),
      const Offset(inset, inset + arm),
      bracketPaint,
    );
    // Top-right
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(size.width - inset - arm, inset),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(size.width - inset, inset + arm),
      bracketPaint,
    );
    // Bottom-left
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(inset + arm, size.height - inset),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(inset, size.height - inset - arm),
      bracketPaint,
    );
    // Bottom-right
    canvas.drawLine(
      Offset(size.width - inset, size.height - inset),
      Offset(size.width - inset - arm, size.height - inset),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(size.width - inset, size.height - inset),
      Offset(size.width - inset, size.height - inset - arm),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(_OndaGridPainter old) =>
      old.colorA != colorA ||
      old.colorB != colorB ||
      old.accentColor != accentColor;
}
