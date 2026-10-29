import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/admin_page.dart';
import 'pages/auth_gate.dart';
import 'pages/legal_page.dart';
import 'pages/mi_cita_page.dart';
import 'pages/reserva_page.dart';
import 'pages/setup_required_page.dart';
import 'services/plataforma_repository.dart';
import 'services/reserva_repository.dart';
import 'theme.dart';
import 'utils/enlace_publico.dart';

class BarberiaApp extends StatelessWidget {
  const BarberiaApp({
    super.key,
    this.supabaseConfigured = true,
    this.rutaInicial,
    this.reservaRepository,
    this.adminRepository,
  });

  final bool supabaseConfigured;

  /// Ruta con la que abre la app (pruebas). En web se usa el hash de la
  /// URL: `#/reservar/<slug>`, `#/cita/<token>` o cualquier otra cosa.
  final String? rutaInicial;

  /// Repositorio de la reserva pública (pruebas); por defecto, Supabase.
  final ReservaRepository? reservaRepository;

  /// Repositorio del panel `#/admin` (pruebas); por defecto, Supabase.
  final AdminRepository? adminRepository;

  static bool _esRutaAdmin(String? ruta) {
    var limpia = (ruta ?? '').trim();
    if (limpia.startsWith('#')) limpia = limpia.substring(1);
    final corte = limpia.indexOf(RegExp(r'[?#]'));
    if (corte >= 0) limpia = limpia.substring(0, corte);
    return limpia.replaceAll('/', '') == 'admin';
  }

  ReservaRepository? get _repositorio =>
      reservaRepository ??
      (supabaseConfigured
          ? SupabaseReservaRepository(Supabase.instance.client)
          : null);

  /// Página para una ruta. Las públicas no dependen de la sesión: se
  /// muestran aunque haya un usuario conectado.
  Widget _pagina(String? nombre) {
    var publica = RutaPublica.desde(nombre);
    // En web la ruta inicial del motor puede llegar como '/'; el hash
    // de la URL manda.
    if (publica == null && kIsWeb && (nombre == null || nombre == '/')) {
      publica = RutaPublica.desde(Uri.base.fragment);
    }

    if (publica is RutaLegal) {
      return publica.pagina == RutaLegal.terminos
          ? const LegalPage.terminos()
          : const LegalPage.privacidad();
    }
    final admin =
        _esRutaAdmin(nombre) ||
        (kIsWeb &&
            (nombre == null || nombre == '/') &&
            _esRutaAdmin(Uri.base.fragment));
    if (admin && publica == null) {
      if (adminRepository != null) {
        return AdminPage(repository: adminRepository!);
      }
      if (supabaseConfigured) {
        final cliente = Supabase.instance.client;
        // Sin sesión se pide iniciar; al entrar, se abre el panel.
        return StreamBuilder<AuthState>(
          stream: cliente.auth.onAuthStateChange,
          builder: (_, _) => cliente.auth.currentSession == null
              ? const AuthGate()
              : AdminPage(repository: SupabaseAdminRepository(cliente)),
        );
      }
    }

    final repositorio = publica == null ? null : _repositorio;
    if (publica != null && repositorio != null) {
      return switch (publica) {
        RutaReserva(:final slug) => ReservaPage(
          slug: slug,
          repository: repositorio,
        ),
        RutaCita(:final token) => MiCitaPage(
          token: token,
          repository: repositorio,
        ),
        RutaLegal() => const SizedBox.shrink(), // ya resuelto arriba
      };
    }

    return supabaseConfigured ? const AuthGate() : const SetupRequiredPage();
  }

  Route<void> _ruta(String? nombre) => MaterialPageRoute<void>(
    settings: RouteSettings(name: nombre),
    builder: (_) => _pagina(nombre),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barbería PRO',
      debugShowCheckedModeBanner: false,
      theme: temaBarberia(),
      initialRoute: rutaInicial,
      // Una sola página inicial (sin apilar '/', '/reservar', ...).
      onGenerateInitialRoutes: (nombre) => [_ruta(nombre)],
      onGenerateRoute: (settings) => _ruta(settings.name),
    );
  }
}
