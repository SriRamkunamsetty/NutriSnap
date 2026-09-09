import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AnimatedScaleIn extends StatelessWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  const AnimatedScaleIn({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 100),
    this.duration = const Duration(milliseconds: 400),
  });

  @override
  Widget build(BuildContext context) {
    return child
        .animate()
        .scale(delay: delay, duration: duration, curve: Curves.easeOutBack);
  }
}

class AnimatedFadeSlide extends StatelessWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double beginSlide;

  const AnimatedFadeSlide({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 300),
    this.duration = const Duration(milliseconds: 400),
    this.beginSlide = 0.1,
  });

  @override
  Widget build(BuildContext context) {
    return child
        .animate()
        .slideY(begin: beginSlide, end: 0, delay: delay, duration: duration, curve: Curves.easeOut)
        .fadeIn(delay: delay, duration: duration);
  }
}

class AnimatedFadeIn extends StatelessWidget {
  final Widget child;
  final Duration delay;

  const AnimatedFadeIn({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    return child.animate().fadeIn(delay: delay);
  }
}
