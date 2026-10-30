import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  // Monitoreo de errores; sin DSN (desarrollo local) la app arranca igual.
  const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  Future<void> arrancar() async {
    if (supabaseUrl.isEmpty || publishableKey.isEmpty) {
      runApp(const BarberiaApp(supabaseConfigured: false));
      return;
    }
    await Supabase.initialize(url: supabaseUrl, publishableKey: publishableKey);
    runApp(const BarberiaApp());
  }

  if (sentryDsn.isEmpty) {
    await arrancar();
    return;
  }

  await SentryFlutter.init((options) {
    options.dsn = sentryDsn;
    options.environment = 'produccion';
    // Solo errores: sin rendimiento ni sesiones grabadas, para no gastar
    // cupo ni enviar más datos de los necesarios.
    options.tracesSampleRate = 0;
    // Ley 172-13: no enviar IP, cookies ni datos del usuario.
    options.sendDefaultPii = false;
  }, appRunner: arrancar);
}
