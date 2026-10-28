import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/formato.dart';
import 'reportes.dart';

abstract interface class ReportesRepository {
  /// Citas del negocio entre [periodo].desde y [periodo].hasta (inclusive),
  /// con sus apartados. Si se indica [empleadoId], solo las de ese empleado.
  Future<List<CitaReporte>> listarCitas({
    required String negocioId,
    required Periodo periodo,
    String? empleadoId,
  });
}

class SupabaseReportesRepository implements ReportesRepository {
  const SupabaseReportesRepository(this._client);

  final SupabaseClient _client;

  /// PostgREST limita las filas por respuesta; se pide por páginas.
  static const _pagina = 1000;

  @override
  Future<List<CitaReporte>> listarCitas({
    required String negocioId,
    required Periodo periodo,
    String? empleadoId,
  }) async {
    final citas = <CitaReporte>[];
    for (var desde = 0; ; desde += _pagina) {
      var query = _client
          .from('citas')
          .select(
            'id, fecha, precio, estado, cliente_id, empleado_id, servicio_id, '
            'clientes(nombre), servicios(nombre), empleados(nombre), '
            'apartados(monto, estado)',
          )
          .eq('negocio_id', negocioId)
          .gte('fecha', formatoFechaIso(periodo.desde))
          .lte('fecha', formatoFechaIso(periodo.hasta));
      if (empleadoId != null) query = query.eq('empleado_id', empleadoId);

      final rows = await query
          .order('fecha')
          .order('id')
          .range(desde, desde + _pagina - 1);
      citas.addAll(rows.map(CitaReporte.fromMap));
      if (rows.length < _pagina) break;
    }
    return citas;
  }
}
