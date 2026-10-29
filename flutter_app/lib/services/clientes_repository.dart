import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cita.dart';
import '../models/cliente.dart';
import 'paginacion.dart';
import 'sin_permiso.dart';

abstract interface class ClientesRepository {
  Future<List<Cliente>> listar(String negocioId);

  /// Resumen por cliente_id; los clientes sin visitas ni faltas no aparecen.
  Future<Map<String, ResumenCliente>> resumen(String negocioId);

  /// Todas las citas del cliente (cualquier estado), más recientes primero,
  /// con el nombre del servicio y del barbero.
  Future<List<Cita>> historial({
    required String negocioId,
    required String clienteId,
  });

  Future<void> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? clienteId,
  });

  Future<void> cambiarEstado({
    required String negocioId,
    required String clienteId,
    required bool activo,
  });

  /// Derecho de cancelación (Ley 172-13): borra los datos personales del
  /// cliente y conserva sus citas para los reportes. Solo el dueño.
  Future<void> anonimizar(String clienteId);
}

class SupabaseClientesRepository implements ClientesRepository {
  const SupabaseClientesRepository(this._client);

  final SupabaseClient _client;

  static const _pagina = 1000;

  @override
  Future<List<Cliente>> listar(String negocioId) async {
    final rows = await leerTodasLasPaginas(
      (desde, hasta) => _client
          .from('clientes')
          .select('id, nombre, telefono, email, notas, activo')
          .eq('negocio_id', negocioId)
          .order('nombre')
          .order('id')
          .range(desde, hasta),
      tamano: _pagina,
    );

    return rows.map((row) => Cliente.fromMap(row)).toList(growable: false);
  }

  @override
  Future<Map<String, ResumenCliente>> resumen(String negocioId) async {
    final visitas = <String, int>{};
    final gastado = <String, num>{};
    final faltas = <String, int>{};

    // PostgREST limita las filas por respuesta; se pagina para no
    // truncar los totales de negocios con mucho historial.
    for (var desde = 0; ; desde += _pagina) {
      final rows = await _client
          .from('citas')
          .select('cliente_id, precio, estado')
          .eq('negocio_id', negocioId)
          .inFilter('estado', ['LLEGO', 'COMPLETADA', 'NO_VINO'])
          .order('id')
          .range(desde, desde + _pagina - 1);

      for (final row in rows) {
        final clienteId = row['cliente_id'].toString();
        if (row['estado'] == 'NO_VINO') {
          faltas[clienteId] = (faltas[clienteId] ?? 0) + 1;
          continue;
        }
        final precio = num.tryParse(row['precio']?.toString() ?? '') ?? 0;
        visitas[clienteId] = (visitas[clienteId] ?? 0) + 1;
        gastado[clienteId] = (gastado[clienteId] ?? 0) + precio;
      }
      if (rows.length < _pagina) break;
    }

    return {
      for (final clienteId in {...visitas.keys, ...faltas.keys})
        clienteId: ResumenCliente(
          visitas: visitas[clienteId] ?? 0,
          gastado: gastado[clienteId] ?? 0,
          faltas: faltas[clienteId] ?? 0,
        ),
    };
  }

  @override
  Future<List<Cita>> historial({
    required String negocioId,
    required String clienteId,
  }) async {
    final citas = <Cita>[];
    for (var desde = 0; ; desde += _pagina) {
      final rows = await _client
          .from('citas')
          .select(
            'id, fecha, hora_inicio, hora_fin, precio, estado, notas, '
            'cliente_id, servicio_id, empleado_id, '
            'servicios(nombre), empleados(nombre)',
          )
          .eq('negocio_id', negocioId)
          .eq('cliente_id', clienteId)
          .order('fecha', ascending: false)
          .order('hora_inicio', ascending: false)
          .order('id')
          .range(desde, desde + _pagina - 1);

      citas.addAll(rows.map(Cita.fromMap));
      if (rows.length < _pagina) break;
    }
    return citas;
  }

  @override
  Future<void> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? clienteId,
  }) async {
    if (clienteId == null) {
      await _client.from('clientes').insert({
        ...datos,
        'negocio_id': negocioId,
      });
      return;
    }

    final filas = await _client
        .from('clientes')
        .update(datos)
        .eq('negocio_id', negocioId)
        .eq('id', clienteId)
        .select('id');
    exigirFilas(filas);
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String clienteId,
    required bool activo,
  }) async {
    final filas = await _client
        .from('clientes')
        .update({'activo': activo})
        .eq('negocio_id', negocioId)
        .eq('id', clienteId)
        .select('id');
    exigirFilas(filas);
  }

  @override
  Future<void> anonimizar(String clienteId) async {
    await _client.rpc(
      'anonimizar_cliente',
      params: {'p_cliente_id': clienteId},
    );
  }
}
