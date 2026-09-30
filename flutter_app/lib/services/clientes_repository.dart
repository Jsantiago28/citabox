import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cliente.dart';

abstract interface class ClientesRepository {
  Future<List<Cliente>> listar(String negocioId);

  /// Resumen por cliente_id; los clientes sin visitas no aparecen.
  Future<Map<String, ResumenCliente>> resumen(String negocioId);

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
}

class SupabaseClientesRepository implements ClientesRepository {
  const SupabaseClientesRepository(this._client);

  final SupabaseClient _client;

  static const _pagina = 1000;

  @override
  Future<List<Cliente>> listar(String negocioId) async {
    final rows = await _client
        .from('clientes')
        .select('id, nombre, telefono, email, notas, activo')
        .eq('negocio_id', negocioId)
        .order('nombre');

    return rows.map((row) => Cliente.fromMap(row)).toList(growable: false);
  }

  @override
  Future<Map<String, ResumenCliente>> resumen(String negocioId) async {
    final visitas = <String, int>{};
    final gastado = <String, num>{};

    // PostgREST limita las filas por respuesta; se pagina para no
    // truncar los totales de negocios con mucho historial.
    for (var desde = 0; ; desde += _pagina) {
      final rows = await _client
          .from('citas')
          .select('cliente_id, precio')
          .eq('negocio_id', negocioId)
          .inFilter('estado', ['LLEGO', 'COMPLETADA'])
          .order('id')
          .range(desde, desde + _pagina - 1);

      for (final row in rows) {
        final clienteId = row['cliente_id'].toString();
        final precio = num.tryParse(row['precio']?.toString() ?? '') ?? 0;
        visitas[clienteId] = (visitas[clienteId] ?? 0) + 1;
        gastado[clienteId] = (gastado[clienteId] ?? 0) + precio;
      }
      if (rows.length < _pagina) break;
    }

    return {
      for (final clienteId in visitas.keys)
        clienteId: ResumenCliente(
          visitas: visitas[clienteId]!,
          gastado: gastado[clienteId]!,
        ),
    };
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

    await _client
        .from('clientes')
        .update(datos)
        .eq('negocio_id', negocioId)
        .eq('id', clienteId);
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String clienteId,
    required bool activo,
  }) async {
    await _client
        .from('clientes')
        .update({'activo': activo})
        .eq('negocio_id', negocioId)
        .eq('id', clienteId);
  }
}
