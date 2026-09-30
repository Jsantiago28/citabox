import 'package:flutter/material.dart';

import 'pages/auth_gate.dart';
import 'pages/setup_required_page.dart';

class BarberiaApp extends StatelessWidget {
  const BarberiaApp({super.key, this.supabaseConfigured = true});

  final bool supabaseConfigured;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF161716);
    const gold = Color(0xFFC9A24B);

    return MaterialApp(
      title: 'Barbería PRO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F2),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F5F2),
          foregroundColor: ink,
          centerTitle: false,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: ink,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ),
      home: supabaseConfigured ? const AuthGate() : const SetupRequiredPage(),
    );
  }
}
