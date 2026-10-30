import 'dart:math' as math;

import 'package:flutter/material.dart';

Future<void> showVoicePrompt(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close voice input',
    barrierColor: const Color(0xE606142E),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) =>
        const _VoicePromptScreen(),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _VoicePromptScreen extends StatefulWidget {
  const _VoicePromptScreen();

  @override
  State<_VoicePromptScreen> createState() => _VoicePromptScreenState();
}

class _VoicePromptScreenState extends State<_VoicePromptScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _hasResolvedMotionPreference = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_hasResolvedMotionPreference && reduceMotion == _reduceMotion) return;
    _hasResolvedMotionPreference = true;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller
        ..stop()
        ..value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      key: const ValueKey('voice-prompt-screen'),
      backgroundColor: const Color(0xFF06142E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A1F42),
                  Color(0xFF06142E),
                  Color(0xFF091B3A),
                ],
              ),
            ),
          ),
          Positioned(
            left: size.width * 0.12,
            right: size.width * 0.12,
            top: size.height * 0.5 - 125,
            height: 250,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF168BFF).withValues(alpha: 0.12),
                    const Color(0xFF168BFF).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    key: const ValueKey('close-voice-prompt'),
                    tooltip: 'Close voice input',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFFEAF4FF),
                      size: 25,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Speak something',
                        key: const ValueKey('voice-prompt-title'),
                        style: TextStyle(
                          fontSize: (size.width * 0.075).clamp(27, 34),
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.8,
                          color: const Color(0xFFF5F9FF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Voice input is coming soon.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFFB5CAE3),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  key: const ValueKey('voice-wave'),
                  width: double.infinity,
                  height: 130,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) => Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0015)
                        ..rotateX(_reduceMotion ? 0 : -0.09)
                        ..rotateY(
                          _reduceMotion
                              ? 0
                              : math.sin(_controller.value * math.pi * 2) *
                                    0.035,
                        ),
                      child: CustomPaint(
                        painter: _VoiceWavePainter(
                          phase: _controller.value,
                          reduceMotion: _reduceMotion,
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
                  child: Text(
                    'Tap the close button when you’re done.',
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFFB5CAE3).withValues(alpha: 0.76),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  const _VoiceWavePainter({required this.phase, required this.reduceMotion});

  final double phase;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = reduceMotion ? 0.0 : phase * math.pi * 2;
    _drawWave(
      canvas,
      size,
      progress - 0.58,
      const Color(0xFF168BFF).withValues(alpha: 0.72),
      3,
      0.29,
    );
    _drawWave(canvas, size, progress, const Color(0xFF8CCBFF), 1.8, 0.2);
    _drawWave(
      canvas,
      size,
      progress + 0.78,
      Colors.white.withValues(alpha: 0.92),
      1.25,
      0.13,
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size,
    double phase,
    Color color,
    double strokeWidth,
    double amplitudeFactor,
  ) {
    final centerY = size.height * 0.5;
    final path = Path();
    final amplitude = size.height * amplitudeFactor;
    for (var index = 0; index <= 120; index++) {
      final progress = index / 120;
      final x = size.width * progress;
      final envelope = 0.35 + (0.65 * math.sin(progress * math.pi));
      final fundamental = math.sin((progress * math.pi * 2.2) + phase);
      final detail = math.sin((progress * math.pi * 4.1) - (phase * 0.7));
      final y =
          centerY +
          (amplitude * envelope * (fundamental * 0.72 + detail * 0.28));
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: color.a * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 4
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_VoiceWavePainter oldDelegate) =>
      phase != oldDelegate.phase || reduceMotion != oldDelegate.reduceMotion;
}
