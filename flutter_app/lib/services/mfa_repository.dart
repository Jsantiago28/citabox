import 'package:supabase_flutter/supabase_flutter.dart';

class MfaException implements Exception {
  const MfaException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Datos para registrar la app de autenticación.
class MfaEnrolamiento {
  const MfaEnrolamiento({required this.factorId, required this.secreto});

  final String factorId;
  final String secreto;
}

/// Verificación en dos pasos (TOTP) de la cuenta con sesión abierta.
abstract interface class MfaRepository {
  /// Id del factor TOTP verificado, o null si la cuenta no lo tiene activo.
  Future<String?> factorActivo();

  /// Factor que falta verificar en esta sesión (nivel aal1 con aal2
  /// disponible), o null si no hace falta pedir código.
  String? factorPendiente();

  /// Crea un factor nuevo (sin activar) y devuelve su código secreto.
  Future<MfaEnrolamiento> iniciarActivacion();

  /// Comprueba el código de 6 dígitos del factor indicado.
  Future<void> verificar({required String factorId, required String codigo});

  /// Quita el factor (la sesión ya debe estar en aal2).
  Future<void> desactivar(String factorId);
}

class SupabaseMfaRepository implements MfaRepository {
  const SupabaseMfaRepository(this._client);

  final SupabaseClient _client;

  GoTrueMFAApi get _mfa => _client.auth.mfa;

  @override
  Future<String?> factorActivo() async {
    try {
      final factores = await _mfa.listFactors();
      return factores.totp.isEmpty ? null : factores.totp.first.id;
    } on AuthException {
      throw const MfaException(
        'No se pudo consultar la seguridad de tu cuenta.',
      );
    }
  }

  @override
  String? factorPendiente() {
    final nivel = _mfa.getAuthenticatorAssuranceLevel();
    if (nivel.currentLevel != AuthenticatorAssuranceLevels.aal1 ||
        nivel.nextLevel != AuthenticatorAssuranceLevels.aal2) {
      return null;
    }
    final factores = _client.auth.currentUser?.factors ?? const <Factor>[];
    for (final factor in factores) {
      if (factor.factorType == FactorType.totp &&
          factor.status == FactorStatus.verified) {
        return factor.id;
      }
    }
    return null;
  }

  @override
  Future<MfaEnrolamiento> iniciarActivacion() async {
    try {
      // Restos de un intento anterior sin terminar estorbarían al crear otro.
      final factores = await _mfa.listFactors();
      for (final factor in factores.all) {
        if (factor.status == FactorStatus.unverified) {
          await _mfa.unenroll(factor.id);
        }
      }
      final respuesta = await _mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'Barbería PRO',
        friendlyName: 'App ${DateTime.now().millisecondsSinceEpoch}',
      );
      final totp = respuesta.totp;
      if (totp == null) {
        throw const MfaException('No se pudo preparar la verificación.');
      }
      return MfaEnrolamiento(factorId: respuesta.id, secreto: totp.secret);
    } on AuthException {
      throw const MfaException(
        'No se pudo preparar la verificación. Revisa que esté habilitada '
        'en tu proyecto e intenta de nuevo.',
      );
    }
  }

  @override
  Future<void> verificar({
    required String factorId,
    required String codigo,
  }) async {
    try {
      await _mfa.challengeAndVerify(factorId: factorId, code: codigo);
    } on AuthException catch (error) {
      final texto = '${error.code} ${error.message}'.toLowerCase();
      if (texto.contains('invalid') || texto.contains('code')) {
        throw const MfaException(
          'El código no es correcto. Revisa tu app e intenta con el nuevo.',
        );
      }
      throw const MfaException('No se pudo verificar el código.');
    }
  }

  @override
  Future<void> desactivar(String factorId) async {
    try {
      await _mfa.unenroll(factorId);
    } on AuthException {
      throw const MfaException('No se pudo desactivar. Intenta de nuevo.');
    }
  }
}

/// Repositorio con el cliente de Supabase, o null si aún no está iniciado
/// (pruebas sin backend).
MfaRepository? mfaRepositoryPredeterminado() {
  try {
    return SupabaseMfaRepository(Supabase.instance.client);
  } catch (_) {
    return null;
  }
}
