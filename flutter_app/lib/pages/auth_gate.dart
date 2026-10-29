import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/mfa_repository.dart';
import '../services/password_repository.dart';
import 'business_home_page.dart';
import 'login_page.dart';
import 'recuperar_password_page.dart';
import 'verificacion_mfa_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, this.mfaRepository});

  /// Inyectable en pruebas; por defecto la verificación de Supabase.
  final MfaRepository? mfaRepository;

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? client.auth.currentSession;
        if (session == null) return const LoginPage();

        // Barbero invitado que entró por el enlace del correo: ya tiene
        // perfil, pero aún no tiene contraseña. Al guardarla se limpia la
        // marca y el evento userUpdated lo lleva a su panel.
        if (debeFijarPassword(session.user.userMetadata)) {
          return RecuperarPasswordPage.fijar(
            repository: SupabasePasswordRepository(client),
            onSalir: client.auth.signOut,
          );
        }

        // Dueño con verificación en dos pasos: pide el código antes del panel.
        return MfaGate(
          repository: mfaRepository ?? SupabaseMfaRepository(client),
          onSalir: client.auth.signOut,
          child: BusinessHomePage(
            userId: session.user.id,
            email: session.user.email ?? '',
          ),
        );
      },
    );
  }
}
