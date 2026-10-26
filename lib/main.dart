import 'package:flutter/material.dart';

import 'screenes/sign_in_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF15251F);
    const forest = Color(0xFF175C48);

    return MaterialApp(
      title: 'Equitas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8F4),
        colorScheme: ColorScheme.fromSeed(
          seedColor: forest,
          primary: forest,
          surface: const Color(0xFFF7F8F4),
        ),
        fontFamily: 'Roboto',
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
      ),
      home: const SignInScreen(),
    );
  }
}
