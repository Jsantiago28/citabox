import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cita.dart';
import '../utils/formato.dart';

abstract interface class CitasRepository {
  Future<List<Cita>> listarDelDia({
    required String negocioId,
    required DateTime fecha,
    String? empleadoId,
  });

  Future<void> cambiarEstado({
    required String negocioId,
    required String citaId,
    required EstadoCita estado,
  });

  /// Empleado vinculado al perfil (para la vista "Mi agenda").
  Future<String?> empleadoDelPerfil({
    required String negocioId,
    required String perfilId,
  });
}

class SupabaseCitasRepository implements CitasRepository {
  const SupabaseCitasRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Cita>> listarDelDia({
    required String negocioId,
    required DateTime fecha,
    String? empleadoId,
  }) async {
    var query = _client
        .from('citas')
        .select(
          'id, fecha, hora_inicio, precio, estado, '
          'clientes(nombre), servicios(nombre), empleados(nombre)',
        )
        .eq('negocio_id', negocioId)
        .eq('fecha', formatoFechaIso(fecha));
    if (empleadoId != null) query = query.eq('empleado_id', empleadoId);

    final rows = await query.order('hora_inicio');
    return rows.map(Cita.fromMap).toList(growable: false);
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String citaId,
    required EstadoCita estado,
  }) async {
    await _client
        .from('citas')
        .update({'estado': estado.valor})
        .eq('negocio_id', negocioId)
        .eq('id', citaId);
  }

  @override
  Future<String?> empleadoDelPerfil({
    required String negocioId,
    required String perfilId,
  }) async {
    final row = await _client
        .from('empleados')
        .select('id')
        .eq('negocio_id', negocioId)
        .eq('perfil_id', perfilId)
        .maybeSingle();
    return row?['id']?.toString();
  }
}
