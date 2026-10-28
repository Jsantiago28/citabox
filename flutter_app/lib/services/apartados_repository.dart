import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/apartado.dart';
import '../models/cita.dart';
import '../utils/formato.dart';
import 'sin_permiso.dart';

abstract interface class ApartadosRepository {
  /// Todos los apartados por validar y el historial reciente del negocio.
  /// Con [empleadoId] solo los de las citas de ese barbero.
  Future<List<Apartado>> listar({
    required String negocioId,
    String? empleadoId,
  });

  /// Cantidad de apartados PENDIENTE (para el aviso del panel).
  Future<int> contarPorValidar({required String negocioId, String? empleadoId});

  /// `negocios.apartado_monto`.
  Future<num> montoPorDefecto(String negocioId);

  /// Citas PENDIENTE desde [desde] que no tienen un apartado activo.
  Future<List<Cita>> citasSinApartado({
    required String negocioId,
    required DateTime desde,
    String? empleadoId,
  });

  /// Marca el apartado como PAGADO; el trigger confirma la cita.
  Future<void> validar({
    required String negocioId,
    required String apartadoId,
    required num monto,
    required MetodoPagoApartado metodo,
    String? referencia,
  });

  /// Marca el apartado como CANCELADO.
  Future<void> cancelar({
    required String negocioId,
    required String apartadoId,
  });

  /// Crea un apartado PENDIENTE para una cita que no tiene.
  Future<void> registrar({
    required String negocioId,
    required String citaId,
    required num monto,
  });
}

class SupabaseApartadosRepository implements ApartadosRepository {
  const SupabaseApartadosRepository(this._client);

  final SupabaseClient _client;

  /// Historial (pagados y cancelados) que se trae junto a los pendientes.
  static const _historial = 300;

  @override
  Future<List<Apartado>> listar({
    required String negocioId,
    String? empleadoId,
  }) async {
    PostgrestFilterBuilder<List<Map<String, dynamic>>> base() {
      var query = _client
          .from('apartados')
          .select(Apartado.columnas)
          .eq('negocio_id', negocioId);
      if (empleadoId != null) {
        query = query.eq('citas.empleado_id', empleadoId);
      }
      return query;
    }

    final pendientes = await base().eq(
      'estado',
      EstadoApartado.pendiente.valor,
    );
    final resto = await base()
        .neq('estado', EstadoApartado.pendiente.valor)
        .order('updated_at', ascending: false)
        .limit(_historial);

    return [
      ...pendientes.map(Apartado.fromMap),
      ...resto.map(Apartado.fromMap),
    ];
  }

  @override
  Future<int> contarPorValidar({
    required String negocioId,
    String? empleadoId,
  }) async {
    var query = _client
        .from('apartados')
        .select('id, citas!inner(empleado_id)')
        .eq('negocio_id', negocioId)
        .eq('estado', EstadoApartado.pendiente.valor);
    if (empleadoId != null) {
      query = query.eq('citas.empleado_id', empleadoId);
    }
    final respuesta = await query.count(CountOption.exact);
    return respuesta.count;
  }

  @override
  Future<num> montoPorDefecto(String negocioId) async {
    final row = await _client
        .from('negocios')
        .select('apartado_monto')
        .eq('id', negocioId)
        .maybeSingle();
    return num.tryParse(row?['apartado_monto']?.toString() ?? '') ?? 0;
  }

  @override
  Future<List<Cita>> citasSinApartado({
    required String negocioId,
    required DateTime desde,
    String? empleadoId,
  }) async {
    var query = _client
        .from('citas')
        .select(
          'id, fecha, hora_inicio, hora_fin, precio, estado, notas, '
          'cliente_id, servicio_id, empleado_id, '
          'clientes(nombre), servicios(nombre), empleados(nombre), '
          'apartados(estado)',
        )
        .eq('negocio_id', negocioId)
        .eq('estado', EstadoCita.pendiente.valor)
        .gte('fecha', formatoFechaIso(desde));
    if (empleadoId != null) query = query.eq('empleado_id', empleadoId);

    final rows = await query.order('fecha').order('hora_inicio').limit(200);

    bool tieneActivo(Map<String, dynamic> row) {
      final apartados = row['apartados'] as List<dynamic>? ?? const [];
      return apartados.any(
        (a) =>
            (a as Map<String, dynamic>)['estado'] !=
            EstadoApartado.cancelado.valor,
      );
    }

    return rows
        .where((row) => !tieneActivo(row))
        .map(Cita.fromMap)
        .toList(growable: false);
  }

  @override
  Future<void> validar({
    required String negocioId,
    required String apartadoId,
    required num monto,
    required MetodoPagoApartado metodo,
    String? referencia,
  }) async {
    final ref = referencia?.trim() ?? '';
    final filas = await _client
        .from('apartados')
        .update({
          'estado': EstadoApartado.pagado.valor,
          'monto': monto,
          'metodo_pago': metodo.valor,
          'referencia': ref.isEmpty ? null : ref,
        })
        .eq('negocio_id', negocioId)
        .eq('id', apartadoId)
        .eq('estado', EstadoApartado.pendiente.valor)
        .select('id');
    // RLS deja la actualización en 0 filas (sin error) si no es el dueño.
    exigirFilas(filas);
  }

  @override
  Future<void> cancelar({
    required String negocioId,
    required String apartadoId,
  }) async {
    final filas = await _client
        .from('apartados')
        .update({'estado': EstadoApartado.cancelado.valor})
        .eq('negocio_id', negocioId)
        .eq('id', apartadoId)
        .eq('estado', EstadoApartado.pendiente.valor)
        .select('id');
    exigirFilas(filas);
  }

  @override
  Future<void> registrar({
    required String negocioId,
    required String citaId,
    required num monto,
  }) async {
    await _client.from('apartados').insert({
      'negocio_id': negocioId,
      'cita_id': citaId,
      'monto': monto,
      'estado': EstadoApartado.pendiente.valor,
    });
  }
}
