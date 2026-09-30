import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/registro_negocio.dart';

class RegistroException implements Exception {
  const RegistroException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class RegistroRepository {
  /// Devuelve null si no se pudo comprobar; el backend decide al final.
  Future<bool?> slugDisponible(String slug);

  /// Crea la cuenta Auth. Devuelve true si Supabase entregó sesión
  /// inmediata y false si hay que confirmar el correo primero.
  Future<bool> crearCuenta({
    required String email,
    required String password,
    required RegistroNegocio datos,
  });

  /// Crea negocio + perfil OWNER para la cuenta autenticada.
  Future<void> crearNegocio(RegistroNegocio datos);
}

class SupabaseRegistroRepository implements RegistroRepository {
  const SupabaseRegistroRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<bool?> slugDisponible(String slug) async {
    try {
      final disponible = await _client.rpc(
        'negocio_slug_disponible',
        params: {'p_slug': slug},
      );
      return disponible is bool ? disponible : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> crearCuenta({
    required String email,
    required String password,
    required RegistroNegocio datos,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: datos.toMetadata(),
      );
      return response.session != null;
    } on AuthException catch (error) {
      final texto = '${error.code} ${error.message}'.toLowerCase();
      if (texto.contains('already') || texto.contains('registered')) {
        throw const RegistroException('Ya existe una cuenta con ese correo.');
      }
      if (texto.contains('weak') || texto.contains('password')) {
        throw const RegistroException(
          'La contraseña no cumple los requisitos de seguridad.',
        );
      }
      throw const RegistroException(
        'No se pudo crear la cuenta. Intenta de nuevo.',
      );
    }
  }

  @override
  Future<void> crearNegocio(RegistroNegocio datos) async {
    try {
      await _client.rpc(
        'bootstrap_negocio_owner',
        params: {
          'p_negocio_nombre': datos.negocioNombre,
          'p_negocio_slug': datos.slug,
          'p_negocio_telefono': datos.negocioTelefono.isEmpty
              ? null
              : datos.negocioTelefono,
          'p_owner_nombre': datos.ownerNombre,
          'p_owner_telefono': datos.ownerTelefono.isEmpty
              ? null
              : datos.ownerTelefono,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == '23505' ||
          error.message.toLowerCase().contains('slug')) {
        throw const RegistroException('Ese slug ya está en uso. Elige otro.');
      }
      throw const RegistroException(
        'No se pudo crear el negocio. Intenta de nuevo.',
      );
    }

    // Limpieza opcional: el perfil ya existe y la función no permite
    // un segundo bootstrap, así que un fallo aquí no es crítico.
    try {
      await _client.auth.updateUser(
        UserAttributes(data: {RegistroNegocio.metadataKey: null}),
      );
    } catch (_) {}
  }
}
