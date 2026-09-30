import 'package:flutter/material.dart';

import 'pages/auth_gate.dart';
import 'pages/setup_required_page.dart';
import 'theme.dart';

class BarberiaApp extends StatelessWidget {
  const BarberiaApp({super.key, this.supabaseConfigured = true});

  final bool supabaseConfigured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barbería PRO',
      debugShowCheckedModeBanner: false,
      theme: temaBarberia(),
      home: supabaseConfigured ? const AuthGate() : const SetupRequiredPage(),
    );
  }
}
