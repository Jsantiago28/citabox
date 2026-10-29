import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/configuracion_negocio.dart';
import '../utils/fotos.dart';
import 'sin_permiso.dart';

/// Configuración del negocio. Solo el OWNER puede modificarla (RLS).
abstract interface class ConfiguracionRepository {
  Future<ConfiguracionNegocio> cargar(String negocioId);

  /// Horarios de los días abiertos; los días sin fila están cerrados.
  Future<List<HorarioDia>> horarios(String negocioId);

  /// Actualiza columnas de `negocios` (perfil o reglas de reserva).
  Future<void> guardarNegocio({
    required String negocioId,
    required Map<String, Object?> datos,
  });

  /// Sube el logo o la portada ([campo] = 'logo' | 'imagen'), lo guarda en el
  /// negocio y devuelve su dirección.
  Future<String> subirImagen({
    required String negocioId,
    required String campo,
    required Uint8List bytes,
    required String tipo,
  });

  /// Deja exactamente [abiertos] como horario: upsert de esos días y
  /// borrado de los demás (quedan cerrados).
  Future<void> guardarHorarios({
    required String negocioId,
    required List<HorarioDia> abiertos,
  });
}

class SupabaseConfiguracionRepository implements ConfiguracionRepository {
  const SupabaseConfiguracionRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ConfiguracionNegocio> cargar(String negocioId) async {
    final row = await _client
        .from('negocios')
        .select(ConfiguracionNegocio.columnas)
        .eq('id', negocioId)
        .single();
    return ConfiguracionNegocio.fromMap(row);
  }

  @override
  Future<List<HorarioDia>> horarios(String negocioId) async {
    final rows = await _client
        .from('horarios_negocio')
        .select('dia_semana, hora_apertura, hora_cierre')
        .eq('negocio_id', negocioId)
        .order('dia_semana');
    return rows.map(HorarioDia.fromMap).toList(growable: false);
  }

  @override
  Future<String> subirImagen({
    required String negocioId,
    required String campo,
    required Uint8List bytes,
    required String tipo,
  }) async {
    assert(campo == 'logo' || campo == 'imagen');
    final url = await subirFotoDelNegocio(
      _client,
      negocioId: negocioId,
      nombre: 'negocio-$campo',
      bytes: bytes,
      tipo: tipo,
    );
    await guardarNegocio(negocioId: negocioId, datos: {campo: url});
    return url;
  }

  @override
  Future<void> guardarNegocio({
    required String negocioId,
    required Map<String, Object?> datos,
  }) async {
    final filas = await _client
        .from('negocios')
        .update(datos)
        .eq('id', negocioId)
        .select('id');
    exigirFilas(filas);
  }

  @override
  Future<void> guardarHorarios({
    required String negocioId,
    required List<HorarioDia> abiertos,
  }) async {
    if (abiertos.isNotEmpty) {
      await _client.from('horarios_negocio').upsert([
        for (final dia in abiertos) dia.toMap(negocioId),
      ], onConflict: 'negocio_id,dia_semana');
    }

    final cerrados = [
      for (var dia = 0; dia < 7; dia++)
        if (!abiertos.any((h) => h.diaSemana == dia)) dia,
    ];
    // Borrar un día que ya estaba cerrado afecta 0 filas: no es un error.
    if (cerrados.isNotEmpty) {
      await _client
          .from('horarios_negocio')
          .delete()
          .eq('negocio_id', negocioId)
          .inFilter('dia_semana', cerrados);
    }
  }
}
