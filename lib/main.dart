import 'package:flutter/material.dart';

import 'screenes/sign_in_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isLightTheme = false;

  void _setLightTheme(bool isLightTheme) {
    if (_isLightTheme == isLightTheme) return;
    setState(() => _isLightTheme = isLightTheme);
  }

  ThemeData _theme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    const blue = Color(0xFF2878E8);
    final background = isLight
        ? const Color(0xFFF7FAFF)
        : const Color(0xFF061A35);
    final surface = isLight ? Colors.white : const Color(0xFF0B2341);
    final text = isLight ? const Color(0xFF102D58) : const Color(0xFFF5F9FF);

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isLight ? const Color(0xFFC8DCF6) : const Color(0xFF315783),
          ),
        ),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue,
        brightness: brightness,
        primary: blue,
        surface: background,
      ),
      fontFamily: 'Roboto',
      textTheme: (isLight ? ThemeData.light() : ThemeData.dark()).textTheme
          .apply(bodyColor: text, displayColor: text),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.all(8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Equitas',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _isLightTheme ? ThemeMode.light : ThemeMode.dark,
      home: SignInScreen(onThemeChanged: _setLightTheme),
    );
  }
}
