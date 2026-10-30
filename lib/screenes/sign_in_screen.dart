import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/local_account_store.dart';
import 'savings_chat_screen.dart';
import '../widgets/glowing_blue_sphere.dart';

bool _isLightTheme(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light;

String _displayNameFromEmail(String email) {
  final name = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ').trim();
  return name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.onThemeChanged});

  final ValueChanged<bool> onThemeChanged;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isAuthenticating = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _userNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating || !_formKey.currentState!.validate()) return;
    setState(() => _isAuthenticating = true);

    final isSignUp = _isSignUp;
    final email = _emailController.text.trim().toLowerCase();
    final userName = isSignUp
        ? _userNameController.text.trim()
        : _displayNameFromEmail(email);
    try {
      final authenticated = isSignUp
          ? await LocalAccountStore.instance.register(
              email,
              _passwordController.text,
            )
          : await LocalAccountStore.instance.verify(
              email,
              _passwordController.text,
            );
      if (!mounted) return;
      if (!authenticated) {
        FocusManager.instance.primaryFocus?.unfocus();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isSignUp
                  ? 'An account already uses this email'
                  : 'Email or password is incorrect',
            ),
          ),
        );
        return;
      }

      await LocalAccountStore.instance.clearSavedProfile(email);
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 550),
          pageBuilder: (context, animation, secondaryAnimation) =>
              SavingsChatScreen(
                userName: userName,
                onThemeChanged: widget.onThemeChanged,
                onLogout: () {
                  navigator.pushReplacement<void, void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SignInScreen(onThemeChanged: widget.onThemeChanged),
                    ),
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
    } catch (error, stackTrace) {
      debugPrint('Local account authentication failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not access local account data: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isLightTheme(context)
          ? const Color(0xFFF7FAFF)
          : const Color(0xFF061A35),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _SignInBackdrop(isLightTheme: _isLightTheme(context)),
          const Positioned(
            top: 105,
            right: 48,
            child: GlowingBlueSphere(diameter: 96),
          ),
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
                          _BrandMark(isLightTheme: _isLightTheme(context)),
                          const SizedBox(height: 42),
                          const _IntroIllustration(),
                          const SizedBox(height: 28),
                          Text(
                            _isSignUp
                                ? 'Your money,\nyour way.'
                                : 'Banking, in\nyour own words.',
                            style: TextStyle(
                              fontSize: 38,
                              height: 1.08,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.4,
                              color: _isLightTheme(context)
                                  ? const Color(0xFF102D58)
                                  : const Color(0xFFF5F9FF),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _isSignUp ? 'Create your account to get started.' : 'A smarter way to understand your money.\nJust start a conversation.',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.55,
                              color: _isLightTheme(context)
                                  ? const Color(0xFF48658A)
                                  : const Color(0xFFB8CDE8),
                            ),
                          ),
                          const SizedBox(height: 22),
                          if (_isSignUp) ...[
                            _InputField(
                              controller: _userNameController,
                              isLightTheme: _isLightTheme(context),
                              label: 'Username',
                              hint: 'Your name',
                              keyboardType: TextInputType.name,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter your name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),
                          ],
                          _InputField(
                            controller: _emailController,
                            isLightTheme: _isLightTheme(context),
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
                          const SizedBox(height: 10),
                          _InputField(
                            controller: _passwordController,
                            isLightTheme: _isLightTheme(context),
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
                                color: const Color(0xFFB8CDE8),
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
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton(
                              onPressed: _isAuthenticating
                                  ? null
                                  : _authenticate,
                              style: FilledButton.styleFrom(
                                backgroundColor: _isLightTheme(context)
                                    ? const Color(0xFF123C78)
                                    : const Color(0xFFF1F6FF),
                                foregroundColor: _isLightTheme(context)
                                    ? Colors.white
                                    : const Color(0xFF092447),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_isAuthenticating)
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else ...[
                                    Text(
                                      _isSignUp
                                          ? 'Create account'
                                          : 'Sign in securely',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 19,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 13),
                          Center(
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => _isSignUp = !_isSignUp),
                              child: Text(
                                _isSignUp
                                    ? 'Already have an account? Sign in'
                                    : 'New here? Create an account',
                              ),
                            ),
                          ),
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 14,
                                  color: _isLightTheme(context)
                                      ? const Color(0xFF48658A)
                                      : const Color(0xFFB8CDE8),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Your account is saved on this device',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _isLightTheme(context)
                                        ? const Color(0xFF48658A)
                                        : const Color(0xFFB8CDE8),
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
  const _BrandMark({required this.isLightTheme});

  final bool isLightTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF55A8FF), Color(0xFF2457D6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
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
            color: isLightTheme
                ? const Color(0xFF102D58)
                : const Color(0xFFF5F9FF),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2E6FCB).withValues(alpha: 0.88),
            const Color(0xFF0B2A55).withValues(alpha: 0.94),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFF80BCFF).withValues(alpha: 0.42),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF398DFF).withValues(alpha: 0.32),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.chat_bubble_outline_rounded,
        color: Color(0xFFE7F3FF),
        size: 34,
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.isLightTheme,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final bool isLightTheme;
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
      style: TextStyle(
        color: isLightTheme ? const Color(0xFF102D58) : const Color(0xFFF5F9FF),
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          color: isLightTheme
              ? const Color(0xFF48658A)
              : const Color(0xFFB8CDE8),
        ),
        floatingLabelStyle: const TextStyle(color: Color(0xFF8DC5FF)),
        hintStyle: const TextStyle(color: Color(0xFF8EA8C8)),
        errorStyle: const TextStyle(color: Color(0xFFFF9EAE)),
        suffixIcon: suffix,
        filled: true,
        fillColor: isLightTheme
            ? const Color(0xFFEAF2FC)
            : const Color(0xFF08264E).withValues(alpha: 0.9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isLightTheme
                ? const Color(0xFFC8DCF6)
                : const Color(0xFF315783),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isLightTheme
                ? const Color(0xFFC8DCF6)
                : const Color(0xFF315783),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF80BCFF), width: 1.4),
        ),
      ),
    );
  }
}

class _SignInBackdrop extends StatelessWidget {
  const _SignInBackdrop({required this.isLightTheme});

  final bool isLightTheme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isLightTheme
                  ? const [
                      Color(0xFFFFFFFF),
                      Color(0xFFF4F8FF),
                      Color(0xFFEAF3FF),
                    ]
                  : const [
                      Color(0xFF0A2C59),
                      Color(0xFF061A35),
                      Color(0xFF031126),
                    ],
            ),
          ),
        ),
        Positioned(
          top: -135,
          right: -95,
          child: _SignInBloom(
            size: 330,
            color: isLightTheme
                ? const Color(0xFF71B5FF).withValues(alpha: 0.24)
                : const Color(0xFF2F82F6).withValues(alpha: 0.33),
          ),
        ),
        Positioned(
          bottom: -175,
          right: -120,
          child: _SignInBloom(
            size: 390,
            color: isLightTheme
                ? const Color(0xFF8CCBFF).withValues(alpha: 0.23)
                : const Color(0xFF13C8E8).withValues(alpha: 0.25),
          ),
        ),
        Positioned(
          bottom: 55,
          left: -205,
          child: _SignInBloom(
            size: 360,
            color: isLightTheme
                ? const Color(0xFF2563EB).withValues(alpha: 0.13)
                : const Color(0xFF1E65D5).withValues(alpha: 0.3),
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
