import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  if (supabaseUrl.isEmpty || publishableKey.isEmpty) {
    runApp(const BarberiaApp(supabaseConfigured: false));
    return;
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: publishableKey);
  runApp(const BarberiaApp());
}
