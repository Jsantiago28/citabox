import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/servicio.dart';
import 'sin_permiso.dart';

abstract interface class ServiciosRepository {
  Future<List<Servicio>> listar(String negocioId);

  Future<void> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? servicioId,
  });

  Future<void> cambiarEstado({
    required String negocioId,
    required String servicioId,
    required bool activo,
  });

  /// Crea de una vez los servicios elegidos del catálogo sugerido.
  Future<void> crearVarios({
    required String negocioId,
    required List<Map<String, Object?>> servicios,
  });
}

class SupabaseServiciosRepository implements ServiciosRepository {
  const SupabaseServiciosRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Servicio>> listar(String negocioId) async {
    final rows = await _client
        .from('servicios')
        .select(
          'id, nombre, descripcion, precio, duracion_minutos, activo, icono',
        )
        .eq('negocio_id', negocioId)
        .order('nombre');

    return rows.map((row) => Servicio.fromMap(row)).toList(growable: false);
  }

  @override
  Future<void> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? servicioId,
  }) async {
    if (servicioId == null) {
      await _client.from('servicios').insert({
        ...datos,
        'negocio_id': negocioId,
      });
      return;
    }

    final filas = await _client
        .from('servicios')
        .update(datos)
        .eq('negocio_id', negocioId)
        .eq('id', servicioId)
        .select('id');
    exigirFilas(filas);
  }

  @override
  Future<void> crearVarios({
    required String negocioId,
    required List<Map<String, Object?>> servicios,
  }) async {
    if (servicios.isEmpty) return;
    await _client.from('servicios').insert([
      for (final datos in servicios) {...datos, 'negocio_id': negocioId},
    ]);
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String servicioId,
    required bool activo,
  }) async {
    final filas = await _client
        .from('servicios')
        .update({'activo': activo})
        .eq('negocio_id', negocioId)
        .eq('id', servicioId)
        .select('id');
    exigirFilas(filas);
  }
}
