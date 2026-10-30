import 'package:supabase_flutter/supabase_flutter.dart';

import 'historial.dart';

/// Historial de cambios (tabla `auditoria`). Solo el OWNER la lee (RLS).
abstract interface class HistorialRepository {
  static const tamanoPagina = 50;

  /// Registros del más reciente al más antiguo. [pagina] empieza en 0.
  Future<PaginaHistorial> listar(
    String negocioId, {
    int pagina = 0,
    String? tabla,
    String? accion,
    DateTime? desde,
    DateTime? hasta,
  });
}

class SupabaseHistorialRepository implements HistorialRepository {
  const SupabaseHistorialRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<PaginaHistorial> listar(
    String negocioId, {
    int pagina = 0,
    String? tabla,
    String? accion,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    const tamano = HistorialRepository.tamanoPagina;
    var consulta = _client
        .from('auditoria')
        .select('id, tabla, fila_id, accion, antes, despues, usuario_id, fecha')
        .eq('negocio_id', negocioId);
    if (tabla != null) consulta = consulta.eq('tabla', tabla);
    if (accion != null) consulta = consulta.eq('accion', accion);
    if (desde != null) {
      final inicio = DateTime(desde.year, desde.month, desde.day);
      consulta = consulta.gte('fecha', inicio.toUtc().toIso8601String());
    }
    if (hasta != null) {
      final fin = DateTime(hasta.year, hasta.month, hasta.day + 1);
      consulta = consulta.lt('fecha', fin.toUtc().toIso8601String());
    }

    // Se pide una fila de más para saber si hay otra página.
    final filas = await consulta
        .order('fecha', ascending: false)
        .order('id', ascending: false)
        .range(pagina * tamano, pagina * tamano + tamano);
    final hayMas = filas.length > tamano;
    final visibles = filas.take(tamano).toList();

    final usuarios = {
      for (final f in visibles)
        if (f['usuario_id'] != null) f['usuario_id'] as String,
    };
    final nombres = <String, String>{};
    if (usuarios.isNotEmpty) {
      final perfiles = await _client
          .from('perfiles')
          .select('id, nombre')
          .eq('negocio_id', negocioId)
          .inFilter('id', usuarios.toList());
      for (final p in perfiles) {
        nombres[p['id'] as String] = p['nombre'] as String;
      }
    }

    final empleados = <String, String>{};
    if (visibles.any((f) => f['tabla'] == 'citas')) {
      final rows = await _client
          .from('empleados')
          .select('id, nombre')
          .eq('negocio_id', negocioId);
      for (final e in rows) {
        empleados[e['id'] as String] = e['nombre'] as String;
      }
    }

    return PaginaHistorial(
      registros: [
        for (final f in visibles)
          RegistroAuditoria.fromMap(f, usuarioNombre: nombres[f['usuario_id']]),
      ],
      hayMas: hayMas,
      empleados: empleados,
    );
  }
}

/// Repositorio con el cliente de Supabase, o null si aún no está iniciado.
HistorialRepository? historialRepositoryPredeterminado() {
  try {
    return SupabaseHistorialRepository(Supabase.instance.client);
  } catch (_) {
    return null;
  }
}
