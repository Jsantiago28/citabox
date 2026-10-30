import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/empleado.dart';
import '../utils/formato.dart';
import 'sin_permiso.dart';

/// Error de la invitación con un mensaje listo para mostrar.
class InvitacionException implements Exception {
  const InvitacionException(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

abstract interface class EmpleadosRepository {
  Future<List<Empleado>> listar(String negocioId);

  Future<void> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? empleadoId,
  });

  Future<void> cambiarEstado({
    required String negocioId,
    required String empleadoId,
    required bool activo,
  });

  /// Servicios que hace el empleado. Vacío = hace todos.
  Future<Set<String>> serviciosAsignados({
    required String negocioId,
    required String empleadoId,
  });

  /// Reemplaza los servicios del empleado. Vacío = hace todos.
  Future<void> guardarServicios({
    required String negocioId,
    required String empleadoId,
    required Set<String> servicioIds,
  });

  /// Horario propio del empleado. Vacío = usa el horario del negocio.
  Future<List<HorarioDia>> horario({
    required String negocioId,
    required String empleadoId,
  });

  /// Reemplaza el horario del empleado. Vacío = usa el horario del negocio.
  Future<void> guardarHorario({
    required String negocioId,
    required String empleadoId,
    required List<HorarioDia> dias,
  });

  /// Días libres que aún no han terminado, del más próximo al más lejano.
  Future<List<BloqueoEmpleado>> bloqueos({
    required String negocioId,
    required String empleadoId,
  });

  Future<void> agregarBloqueo({
    required String negocioId,
    required String empleadoId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    String? motivo,
  });

  Future<void> eliminarBloqueo({
    required String negocioId,
    required String bloqueoId,
  });

  /// Envía la invitación a la app. Lanza [InvitacionException] si falla.
  Future<void> invitar({required String empleadoId, required String email});
}

class SupabaseEmpleadosRepository implements EmpleadosRepository {
  const SupabaseEmpleadosRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Empleado>> listar(String negocioId) async {
    final rows = await _client
        .from('empleados')
        .select('id, nombre, telefono, activo, perfil_id, comision_pct')
        .eq('negocio_id', negocioId)
        .order('nombre');

    return rows.map((row) => Empleado.fromMap(row)).toList(growable: false);
  }

  @override
  Future<void> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? empleadoId,
  }) async {
    if (empleadoId == null) {
      await _client.from('empleados').insert({
        ...datos,
        'negocio_id': negocioId,
      });
      return;
    }

    final filas = await _client
        .from('empleados')
        .update(datos)
        .eq('negocio_id', negocioId)
        .eq('id', empleadoId)
        .select('id');
    exigirFilas(filas);
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String empleadoId,
    required bool activo,
  }) async {
    final filas = await _client
        .from('empleados')
        .update({'activo': activo})
        .eq('negocio_id', negocioId)
        .eq('id', empleadoId)
        .select('id');
    exigirFilas(filas);
  }

  @override
  Future<Set<String>> serviciosAsignados({
    required String negocioId,
    required String empleadoId,
  }) async {
    final rows = await _client
        .from('empleado_servicios')
        .select('servicio_id')
        .eq('negocio_id', negocioId)
        .eq('empleado_id', empleadoId);

    return {for (final row in rows) row['servicio_id'].toString()};
  }

  @override
  Future<void> guardarServicios({
    required String negocioId,
    required String empleadoId,
    required Set<String> servicioIds,
  }) async {
    // Los borrados de abajo pueden afectar 0 filas sin que sea un error
    // (no había nada que quitar), así que no se exigen filas.
    // Primero se agregan los nuevos y luego se quitan los demás: si algo
    // falla a mitad, el empleado nunca queda con menos servicios de los
    // elegidos (y sin filas significa "todos").
    if (servicioIds.isNotEmpty) {
      await _client
          .from('empleado_servicios')
          .upsert(
            [
              for (final servicioId in servicioIds)
                {
                  'negocio_id': negocioId,
                  'empleado_id': empleadoId,
                  'servicio_id': servicioId,
                },
            ],
            onConflict: 'empleado_id,servicio_id',
            ignoreDuplicates: true,
          );
    }

    var borrar = _client
        .from('empleado_servicios')
        .delete()
        .eq('negocio_id', negocioId)
        .eq('empleado_id', empleadoId);
    if (servicioIds.isNotEmpty) {
      borrar = borrar.not('servicio_id', 'in', servicioIds.toList());
    }
    await borrar;
  }

  @override
  Future<List<HorarioDia>> horario({
    required String negocioId,
    required String empleadoId,
  }) async {
    final rows = await _client
        .from('horarios_empleado')
        .select('dia_semana, hora_inicio, hora_fin')
        .eq('negocio_id', negocioId)
        .eq('empleado_id', empleadoId)
        .order('dia_semana');

    return rows.map((row) => HorarioDia.fromMap(row)).toList(growable: false);
  }

  @override
  Future<void> guardarHorario({
    required String negocioId,
    required String empleadoId,
    required List<HorarioDia> dias,
  }) async {
    if (dias.isNotEmpty) {
      await _client.from('horarios_empleado').upsert([
        for (final dia in dias)
          {
            'negocio_id': negocioId,
            'empleado_id': empleadoId,
            'dia_semana': dia.diaSemana,
            'hora_inicio': dia.horaInicio,
            'hora_fin': dia.horaFin,
          },
      ], onConflict: 'empleado_id,dia_semana');
    }

    var borrar = _client
        .from('horarios_empleado')
        .delete()
        .eq('negocio_id', negocioId)
        .eq('empleado_id', empleadoId);
    if (dias.isNotEmpty) {
      borrar = borrar.not('dia_semana', 'in', [
        for (final dia in dias) dia.diaSemana,
      ]);
    }
    await borrar;
  }

  @override
  Future<List<BloqueoEmpleado>> bloqueos({
    required String negocioId,
    required String empleadoId,
  }) async {
    final rows = await _client
        .from('bloqueos_empleado')
        .select('id, fecha_inicio, fecha_fin, motivo')
        .eq('negocio_id', negocioId)
        .eq('empleado_id', empleadoId)
        .gte('fecha_fin', formatoFechaIso(DateTime.now()))
        .order('fecha_inicio');

    return rows
        .map((row) => BloqueoEmpleado.fromMap(row))
        .toList(growable: false);
  }

  @override
  Future<void> agregarBloqueo({
    required String negocioId,
    required String empleadoId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    String? motivo,
  }) async {
    await _client.from('bloqueos_empleado').insert({
      'negocio_id': negocioId,
      'empleado_id': empleadoId,
      'fecha_inicio': formatoFechaIso(fechaInicio),
      'fecha_fin': formatoFechaIso(fechaFin),
      'motivo': motivo,
    });
  }

  @override
  Future<void> eliminarBloqueo({
    required String negocioId,
    required String bloqueoId,
  }) async {
    final filas = await _client
        .from('bloqueos_empleado')
        .delete()
        .eq('negocio_id', negocioId)
        .eq('id', bloqueoId)
        .select('id');
    exigirFilas(filas);
  }

  @override
  Future<void> invitar({
    required String empleadoId,
    required String email,
  }) async {
    const generico = 'No se pudo enviar la invitación.';
    try {
      final respuesta = await _client.functions.invoke(
        'invitar-barbero',
        body: {'empleado_id': empleadoId, 'email': email},
      );
      final data = respuesta.data;
      if (respuesta.status == 200 && data is Map && data['ok'] == true) {
        return;
      }
      throw InvitacionException(_mensajeError(data) ?? generico);
    } on FunctionException catch (error) {
      throw InvitacionException(_mensajeError(error.details) ?? generico);
    }
  }

  static String? _mensajeError(Object? data) {
    if (data is Map && data['error'] is String) {
      final mensaje = (data['error'] as String).trim();
      if (mensaje.isNotEmpty) return mensaje;
    }
    return null;
  }
}
