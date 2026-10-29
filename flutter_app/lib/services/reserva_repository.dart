import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reserva.dart';
import '../utils/formato.dart';

/// Error de la reserva pública con un mensaje listo para mostrar.
class ReservaError implements Exception {
  const ReservaError(this.mensaje, {this.horaNoDisponible = false});

  final String mensaje;

  /// 23P01: la hora ya no está libre; hay que recargar las horas.
  final bool horaNoDisponible;

  @override
  String toString() => mensaje;
}

const mensajeSinConexion =
    'No pudimos conectar. Revisa tu internet e intenta de nuevo.';
const mensajeHoraTomada = 'Esa hora ya no está disponible. Elige otra.';

/// Funciones públicas de 007_reserva_publica.sql (sin sesión).
abstract interface class ReservaRepository {
  Future<CatalogoReserva> catalogo(String slug);

  /// [token]: al reprogramar, excluye la propia cita (011).
  Future<List<HoraDisponible>> horasDisponibles({
    required String slug,
    required String servicioId,
    required DateTime fecha,
    String? empleadoId,
    String? token,
  });

  /// Devuelve la respuesta cruda de reserva_crear.
  Future<Map<String, dynamic>> crear({
    required String slug,
    required String servicioId,
    String? empleadoId,
    required DateTime fecha,
    required String horaInicio,
    required String nombre,
    required String telefono,
    String? email,
    String? notas,
    bool aceptaPrivacidad = false,
  });

  Future<CitaPublica> consultar(String token);

  Future<CitaPublica> cancelar(String token);

  Future<CitaPublica> reprogramar({
    required String token,
    required DateTime fecha,
    required String horaInicio,
  });

  Future<CitaPublica> reportarPago({
    required String token,
    required String referencia,
  });
}

/// Traduce errores de Postgres/PostgREST a [ReservaError].
ReservaError errorDeReserva(Object error) {
  if (error is ReservaError) return error;
  if (error is PostgrestException) {
    switch (error.code) {
      case '23P01':
        return ReservaError(
          error.message.isEmpty ? mensajeHoraTomada : error.message,
          horaNoDisponible: true,
        );
      case 'P0001':
        return ReservaError(error.message);
      case '22P02': // uuid mal formado (enlace cortado o editado)
        return const ReservaError(
          'No encontramos esta cita. Revisa el enlace.',
        );
    }
  }
  return const ReservaError(mensajeSinConexion);
}

class SupabaseReservaRepository implements ReservaRepository {
  const SupabaseReservaRepository(this._client);

  final SupabaseClient _client;

  Future<Object?> _rpc(String funcion, Map<String, Object?> params) async {
    try {
      return await _client.rpc(funcion, params: params);
    } catch (error) {
      throw errorDeReserva(error);
    }
  }

  Map<String, dynamic> _mapa(Object? valor) =>
      valor is Map ? Map<String, dynamic>.from(valor) : <String, dynamic>{};

  @override
  Future<CatalogoReserva> catalogo(String slug) async =>
      CatalogoReserva.fromMap(
        _mapa(await _rpc('reserva_catalogo', {'p_slug': slug})),
      );

  @override
  Future<List<HoraDisponible>> horasDisponibles({
    required String slug,
    required String servicioId,
    required DateTime fecha,
    String? empleadoId,
    String? token,
  }) async {
    final params = <String, Object?>{
      'p_slug': slug,
      'p_servicio_id': servicioId,
      'p_fecha': formatoFechaIso(fecha),
      'p_empleado_id': empleadoId,
    };

    Object? filas;
    if (token == null) {
      filas = await _rpc('reserva_horas_disponibles', params);
    } else {
      try {
        filas = await _client.rpc(
          'reserva_horas_disponibles',
          params: {...params, 'p_token': token},
        );
      } on PostgrestException catch (error) {
        // Base sin 011: la función todavía no tiene p_token (PGRST202).
        // Se piden las horas sin excluir la propia cita.
        if (error.code != 'PGRST202') throw errorDeReserva(error);
        filas = await _rpc('reserva_horas_disponibles', params);
      } catch (error) {
        throw errorDeReserva(error);
      }
    }

    return filas is List
        ? filas.map((f) => HoraDisponible.fromMap(_mapa(f))).toList()
        : const [];
  }

  @override
  Future<Map<String, dynamic>> crear({
    required String slug,
    required String servicioId,
    String? empleadoId,
    required DateTime fecha,
    required String horaInicio,
    required String nombre,
    required String telefono,
    String? email,
    String? notas,
    bool aceptaPrivacidad = false,
  }) async => _mapa(
    await _rpc('reserva_crear', {
      'p_slug': slug,
      'p_servicio_id': servicioId,
      'p_empleado_id': empleadoId,
      'p_fecha': formatoFechaIso(fecha),
      'p_hora_inicio': horaInicio,
      'p_cliente_nombre': nombre,
      'p_cliente_telefono': telefono,
      'p_cliente_email': email,
      'p_notas': notas,
      'p_acepta_privacidad': aceptaPrivacidad,
    }),
  );

  @override
  Future<CitaPublica> consultar(String token) async => CitaPublica.fromMap(
    _mapa(await _rpc('reserva_consultar', {'p_token': token})),
  );

  @override
  Future<CitaPublica> cancelar(String token) async => CitaPublica.fromMap(
    _mapa(await _rpc('reserva_cancelar', {'p_token': token})),
  );

  @override
  Future<CitaPublica> reprogramar({
    required String token,
    required DateTime fecha,
    required String horaInicio,
  }) async => CitaPublica.fromMap(
    _mapa(
      await _rpc('reserva_reprogramar', {
        'p_token': token,
        'p_fecha': formatoFechaIso(fecha),
        'p_hora_inicio': horaInicio,
      }),
    ),
  );

  @override
  Future<CitaPublica> reportarPago({
    required String token,
    required String referencia,
  }) async => CitaPublica.fromMap(
    _mapa(
      await _rpc('reserva_reportar_pago', {
        'p_token': token,
        'p_referencia': referencia,
      }),
    ),
  );
}
