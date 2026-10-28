import 'package:supabase_flutter/supabase_flutter.dart';

class PasswordException implements Exception {
  const PasswordException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Marca que la Edge Function `invitar-barbero` deja en los metadatos del
/// usuario invitado: entró sin contraseña y debe fijar una.
const debeFijarPasswordKey = 'debe_fijar_password';

bool debeFijarPassword(Map<String, dynamic>? metadata) =>
    metadata?[debeFijarPasswordKey] == true;

abstract interface class PasswordRepository {
  /// Envía al correo un código para restablecer la contraseña.
  Future<void> enviarCodigo(String email);

  /// Comprueba el código de recuperación y abre sesión.
  Future<void> verificarCodigo({required String email, required String codigo});

  /// Comprueba el código del correo de invitación (barbero) y abre sesión.
  Future<void> verificarInvitacion({
    required String email,
    required String codigo,
  });

  /// Cambia la contraseña de la cuenta con sesión abierta.
  Future<void> cambiarPassword(String password);
}

class SupabasePasswordRepository implements PasswordRepository {
  const SupabasePasswordRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> enviarCodigo(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } on AuthException catch (error) {
      final texto = '${error.code} ${error.message}'.toLowerCase();
      if (texto.contains('rate') || texto.contains('seconds')) {
        throw const PasswordException(
          'Espera un momento antes de pedir otro código.',
        );
      }
      throw const PasswordException(
        'No se pudo enviar el código. Intenta de nuevo.',
      );
    }
  }

  @override
  Future<void> verificarCodigo({
    required String email,
    required String codigo,
  }) => _verificar(OtpType.recovery, email, codigo);

  @override
  Future<void> verificarInvitacion({
    required String email,
    required String codigo,
  }) => _verificar(OtpType.invite, email, codigo);

  Future<void> _verificar(OtpType tipo, String email, String codigo) async {
    try {
      await _client.auth.verifyOTP(type: tipo, email: email, token: codigo);
    } on AuthException catch (error) {
      final texto = '${error.code} ${error.message}'.toLowerCase();
      if (texto.contains('expired') || texto.contains('invalid')) {
        throw const PasswordException(
          'El código no es válido o ya venció. Pide uno nuevo.',
        );
      }
      throw const PasswordException(
        'No se pudo verificar el código. Intenta de nuevo.',
      );
    }
  }

  @override
  Future<void> cambiarPassword(String password) async {
    try {
      await _client.auth.updateUser(
        UserAttributes(
          password: password,
          // Un invitado deja de necesitar la pantalla de fijar contraseña.
          data: {debeFijarPasswordKey: null},
        ),
      );
    } on AuthException catch (error) {
      final texto = '${error.code} ${error.message}'.toLowerCase();
      if (texto.contains('same') || texto.contains('different')) {
        throw const PasswordException(
          'La nueva contraseña debe ser distinta de la anterior.',
        );
      }
      if (texto.contains('weak') || texto.contains('password')) {
        throw const PasswordException(
          'La contraseña no cumple los requisitos de seguridad.',
        );
      }
      throw const PasswordException(
        'No se pudo guardar la contraseña. Intenta de nuevo.',
      );
    }
  }
}
