import 'dart:math' as math;

import 'package:flutter/material.dart';

class GlowingBlueSphere extends StatefulWidget {
  const GlowingBlueSphere({super.key, required this.diameter});

  final double diameter;

  @override
  State<GlowingBlueSphere> createState() => _GlowingBlueSphereState();
}

class _GlowingBlueSphereState extends State<GlowingBlueSphere>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _hasResolvedMotionPreference = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
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
        ..value = 0.5;
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
    return SizedBox.square(
      dimension: widget.diameter,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final phase = _reduceMotion ? 0.5 : _controller.value;
            final wave = math.sin(phase * math.pi * 2);
            final pulse = 0.94 + ((wave + 1) * 0.045);
            final highlightX = -0.42 + (phase * 0.72);
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0018)
                ..rotateX(
                  _reduceMotion ? 0 : math.cos(phase * math.pi * 2) * 0.06,
                )
                ..rotateY(_reduceMotion ? 0 : wave * 0.09)
                ..scaleByDouble(pulse, pulse, 1, 1),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8CCBFF)
                          .withValues(alpha: 0.22 + ((wave + 1) * 0.12)),
                      blurRadius:
                          widget.diameter * (0.32 + ((wave + 1) * 0.08)),
                      spreadRadius: widget.diameter * 0.055,
                    ),
                    BoxShadow(
                      color: const Color(0xFF168BFF)
                          .withValues(alpha: 0.28 + ((wave + 1) * 0.1)),
                      blurRadius: widget.diameter * 0.2,
                      spreadRadius: 1,
                    ),
                  ],
                  gradient: RadialGradient(
                    center: Alignment(highlightX, -0.34),
                    radius: 0.92,
                    colors: [
                      const Color(0xFF8CCBFF),
                      const Color(0xFF8CCBFF),
                      const Color(0xFF2563EB),
                      const Color(0xFF168BFF),
                      const Color(0xFF2563EB),
                      const Color(0xFF0A1F42),
                      const Color(0xFF06142E),
                    ],
                    stops: const [0, 0.12, 0.29, 0.48, 0.67, 0.84, 1],
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(highlightX, -0.34),
                      radius: 0.58,
                      colors: [
                        const Color(0xFF8CCBFF)
                            .withValues(alpha: 0.38 + ((wave + 1) * 0.08)),
                        const Color(0xFF2563EB).withValues(alpha: 0.16),
                        const Color(0xFF0A1F42).withValues(alpha: 0.08),
                        const Color(0xFF0A1F42).withValues(alpha: 0),
                      ],
                      stops: const [0, 0.23, 0.44, 1],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
