import 'package:flutter/material.dart';

import 'savings_chat_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _signIn() {
    if (!_formKey.currentState!.validate()) return;

    final navigator = Navigator.of(context);
    navigator.pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 550),
        pageBuilder: (context, animation, secondaryAnimation) =>
            SavingsChatScreen(
              onLogout: () {
                navigator.pushReplacement<void, void>(
                  MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
                );
              },
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return AnimatedBuilder(
            animation: curved,
            child: child,
            builder: (context, child) {
              final progress = curved.value;
              final rotation = (1 - progress) * -0.12;
              final scale = 0.94 + (progress * 0.06);
              return Opacity(
                opacity: progress,
                child: Transform(
                  alignment: Alignment.centerRight,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY(rotation)
                    ..setEntry(0, 0, scale)
                    ..setEntry(1, 1, scale),
                  child: child,
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF100817),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _SignInBackdrop(),
          const Positioned(top: 105, right: 58, child: _SignInOrb()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => TweenAnimationBuilder<double>(
                tween: Tween(begin: -0.12, end: 0),
                duration: const Duration(milliseconds: 850),
                curve: Curves.easeOutCubic,
                builder: (context, rotation, child) {
                  final progress = 1 - (rotation.abs() / 0.12);
                  return Opacity(
                    opacity: progress.clamp(0, 1),
                    child: Transform(
                      alignment: Alignment.centerLeft,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0015)
                        ..rotateY(rotation)
                        ..setEntry(0, 0, 0.96 + (progress * 0.04))
                        ..setEntry(1, 1, 0.96 + (progress * 0.04)),
                      child: child,
                    ),
                  );
                },
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 32,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 34),
                          const _BrandMark(),
                          const SizedBox(height: 58),
                          const _IntroIllustration(),
                          const SizedBox(height: 38),
                          const Text(
                            'Banking, in\nyour own words.',
                            style: TextStyle(
                              fontSize: 38,
                              height: 1.08,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.4,
                              color: Color(0xFFF8F1FC),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'A smarter way to understand your money.\nJust start a conversation.',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.55,
                              color: Color(0xFFC1B3CA),
                            ),
                          ),
                          const SizedBox(height: 30),
                          _InputField(
                            controller: _emailController,
                            label: 'Email address',
                            hint: 'you@example.com',
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter your email address';
                              }
                              if (!value.contains('@') ||
                                  !value.contains('.')) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          _InputField(
                            controller: _passwordController,
                            label: 'Password',
                            hint: 'Enter your password',
                            obscureText: _obscurePassword,
                            suffix: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: const Color(0xFFB7A2C4),
                                size: 20,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Enter your password';
                              }
                              if (value.length < 4) {
                                return 'Password must be at least 4 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              onPressed: _signIn,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF7136B5),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Sign in securely',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(width: 9),
                                  Icon(Icons.arrow_forward_rounded, size: 19),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 19),
                          const Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 14,
                                  color: Color(0xFFB6A8BF),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Your conversations stay private',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFB6A8BF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF7136B5),
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        SizedBox(width: 10),
        Text(
          'equitas',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: Color(0xFFF8F1FC),
          ),
        ),
      ],
    );
  }
}

class _IntroIllustration extends StatelessWidget {
  const _IntroIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFF542B78).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFFAB7FD0).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8E37DB).withValues(alpha: 0.2),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.chat_bubble_outline_rounded,
        color: Color(0xFFE9D7FF),
        size: 34,
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(color: Color(0xFFF6EFF9)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFFC6B5D1)),
        floatingLabelStyle: const TextStyle(color: Color(0xFFD6B5FF)),
        hintStyle: const TextStyle(color: Color(0xFF9C8BA8)),
        errorStyle: const TextStyle(color: Color(0xFFFF9AB3)),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF21132D).withValues(alpha: 0.82),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 17,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF59436B)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF59436B)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFCE9AFF), width: 1.4),
        ),
      ),
    );
  }
}

class _SignInBackdrop extends StatelessWidget {
  const _SignInBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF21102F), Color(0xFF100817), Color(0xFF160B23)],
            ),
          ),
        ),
        Positioned(
          top: -135,
          right: -95,
          child: _SignInBloom(
            size: 330,
            color: const Color(0xFF8B2CAC).withValues(alpha: 0.36),
          ),
        ),
        Positioned(
          bottom: -175,
          right: -120,
          child: _SignInBloom(
            size: 390,
            color: const Color(0xFF00B9CE).withValues(alpha: 0.3),
          ),
        ),
        Positioned(
          bottom: 55,
          left: -205,
          child: _SignInBloom(
            size: 360,
            color: const Color(0xFF4734D0).withValues(alpha: 0.28),
          ),
        ),
      ],
    );
  }
}

class _SignInBloom extends StatelessWidget {
  const _SignInBloom({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _SignInOrb extends StatelessWidget {
  const _SignInOrb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      height: 118,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7423FF).withValues(alpha: 0.48),
            blurRadius: 40,
            spreadRadius: 8,
          ),
          BoxShadow(
            color: const Color(0xFFFF35D3).withValues(alpha: 0.17),
            blurRadius: 32,
            spreadRadius: 2,
          ),
        ],
        gradient: const RadialGradient(
          center: Alignment(-0.45, -0.42),
          colors: [
            Color(0xFF83D6FF),
            Color(0xFF5545FF),
            Color(0xFFAA1DFF),
            Color(0xFF451052),
            Color(0x00200A31),
          ],
          stops: [0, 0.2, 0.48, 0.73, 1],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(0.38, 0.48),
            colors: [
              const Color(0xFF100817).withValues(alpha: 0),
              const Color(0xFF13091B).withValues(alpha: 0.66),
            ],
            stops: const [0.32, 1],
          ),
        ),
      ),
    );
  }
}
