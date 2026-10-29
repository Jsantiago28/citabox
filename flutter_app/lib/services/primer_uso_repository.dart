import 'package:supabase_flutter/supabase_flutter.dart';

/// Estado de los pasos de "Configura tu negocio".
class PrimerUso {
  const PrimerUso({
    required this.slug,
    this.horario = false,
    this.servicio = false,
    this.barbero = false,
    this.logo = false,
  });

  final String slug;
  final bool horario;
  final bool servicio;
  final bool barbero;
  final bool logo;
}

abstract interface class PrimerUsoRepository {
  Future<PrimerUso> cargar(String negocioId);
}

class SupabasePrimerUsoRepository implements PrimerUsoRepository {
  const SupabasePrimerUsoRepository(this._client);

  final SupabaseClient _client;

  Future<bool> _hay(
    String tabla,
    String negocioId, {
    bool soloActivos = false,
  }) async {
    var consulta = _client.from(tabla).select('id').eq('negocio_id', negocioId);
    if (soloActivos) consulta = consulta.eq('activo', true);
    final filas = await consulta.limit(1);
    return filas.isNotEmpty;
  }

  @override
  Future<PrimerUso> cargar(String negocioId) async {
    final negocio = await _client
        .from('negocios')
        .select('slug, logo')
        .eq('id', negocioId)
        .single();
    final horarios = await _client
        .from('horarios_negocio')
        .select('negocio_id')
        .eq('negocio_id', negocioId)
        .limit(1);
    final servicio = await _hay('servicios', negocioId, soloActivos: true);
    final barbero = await _hay('empleados', negocioId, soloActivos: true);
    final logo = (negocio['logo'] as String?)?.trim() ?? '';
    return PrimerUso(
      slug: (negocio['slug'] as String?) ?? '',
      horario: horarios.isNotEmpty,
      servicio: servicio,
      barbero: barbero,
      logo: logo.isNotEmpty,
    );
  }
}
