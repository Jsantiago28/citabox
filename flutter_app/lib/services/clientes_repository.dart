import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cliente.dart';

abstract interface class ClientesRepository {
  Future<List<Cliente>> listar(String negocioId);

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
