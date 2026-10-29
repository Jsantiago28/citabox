import 'package:supabase_flutter/supabase_flutter.dart';

/// Días de gracia después del vencimiento (igual que en la base de datos).
const diasDeGracia = 7;

/// Suscripción del negocio (cobro manual por transferencia).
class Suscripcion {
  const Suscripcion({
    required this.plan,
    required this.estado,
    this.pruebaHasta,
    this.pagadoHasta,
  });

  final String plan;

  /// PRUEBA, ACTIVA, VENCIDA o SUSPENDIDA.
  final String estado;
  final DateTime? pruebaHasta;
  final DateTime? pagadoHasta;

  factory Suscripcion.fromMap(Map<String, dynamic> map) => Suscripcion(
    plan: map['plan']?.toString() ?? 'prueba',
    estado: map['estado']?.toString() ?? 'PRUEBA',
    pruebaHasta: _fecha(map['prueba_hasta']),
    pagadoHasta: _fecha(map['pagado_hasta']),
  );
}

DateTime? _fecha(Object? valor) {
  final texto = valor?.toString();
  if (texto == null || texto.length < 10) return null;
  final fecha = DateTime.tryParse(texto.substring(0, 10));
  return fecha == null ? null : DateTime(fecha.year, fecha.month, fecha.day);
}

/// Aviso que ve el dueño según el estado de su suscripción.
class AvisoSuscripcion {
  const AvisoSuscripcion(this.texto, {required this.urgente});

  final String texto;

  /// Rojo (servicio pausado o por pausarse) en vez de informativo.
  final bool urgente;
}

/// Qué aviso mostrar hoy, o null si no hay nada que decir.
AvisoSuscripcion? avisoSuscripcion(Suscripcion s, DateTime ahora) {
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  const pausado =
      'El servicio de tu barbería está pausado. '
      'Contacta a Barbería PRO para pagar y reactivarlo.';

  if (s.estado == 'SUSPENDIDA' || s.estado == 'VENCIDA') {
    return const AvisoSuscripcion(pausado, urgente: true);
  }

  final limite = s.estado == 'ACTIVA' ? s.pagadoHasta : s.pruebaHasta;
  if (limite == null) return const AvisoSuscripcion(pausado, urgente: true);
  final dias = limite.difference(hoy).inDays;

  if (dias < -diasDeGracia) {
    return const AvisoSuscripcion(pausado, urgente: true);
  }
  if (dias < 0) {
    final quedan = diasDeGracia + dias;
    return AvisoSuscripcion(
      'Tu ${s.estado == 'ACTIVA' ? 'suscripción' : 'prueba'} venció. '
      'Paga en los próximos $quedan ${quedan == 1 ? 'día' : 'días'} '
      'o el servicio se pausará. Contacta a Barbería PRO.',
      urgente: true,
    );
  }
  if (s.estado == 'PRUEBA') {
    return AvisoSuscripcion(
      dias == 0
          ? 'Hoy termina tu prueba gratis.'
          : 'Te quedan $dias ${dias == 1 ? 'día' : 'días'} de prueba.',
      urgente: dias <= 5,
    );
  }
  if (dias <= 5) {
    return AvisoSuscripcion(
      dias == 0
          ? 'Tu suscripción vence hoy.'
          : 'Tu suscripción vence en $dias ${dias == 1 ? 'día' : 'días'}.',
      urgente: true,
    );
  }
  return null;
}

abstract interface class SuscripcionRepository {
  /// Suscripción del negocio, o null si no se pudo determinar.
  Future<Suscripcion?> obtener(String negocioId);
}

abstract interface class SoporteRepository {
  Future<void> enviar({
    required String negocioId,
    required String mensaje,
    required Map<String, Object?> contexto,
  });
}

class SupabaseSuscripcionRepository implements SuscripcionRepository {
  const SupabaseSuscripcionRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Suscripcion?> obtener(String negocioId) async {
    final fila = await _client
        .from('suscripciones')
        .select('plan, estado, prueba_hasta, pagado_hasta')
        .eq('negocio_id', negocioId)
        .maybeSingle();
    return fila == null ? null : Suscripcion.fromMap(fila);
  }
}

class SupabaseSoporteRepository implements SoporteRepository {
  const SupabaseSoporteRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> enviar({
    required String negocioId,
    required String mensaje,
    required Map<String, Object?> contexto,
  }) async {
    await _client.from('soporte').insert({
      'negocio_id': negocioId,
      'usuario_id': _client.auth.currentUser?.id,
      'mensaje': mensaje,
      'contexto': contexto,
    });
  }
}

/// Fila del panel de administrador.
class NegocioAdmin {
  const NegocioAdmin({
    required this.id,
    required this.nombre,
    required this.slug,
    required this.plan,
    required this.estado,
    this.duenoCorreo,
    this.pruebaHasta,
    this.pagadoHasta,
    this.barberos = 0,
    this.citas30d = 0,
  });

  final String id;
  final String nombre;
  final String slug;
  final String? duenoCorreo;
  final String plan;
  final String estado;
  final DateTime? pruebaHasta;
  final DateTime? pagadoHasta;
  final int barberos;
  final int citas30d;

  factory NegocioAdmin.fromMap(Map<String, dynamic> map) => NegocioAdmin(
    id: map['negocio_id'].toString(),
    nombre: map['nombre']?.toString() ?? '',
    slug: map['slug']?.toString() ?? '',
    duenoCorreo: map['dueno_correo']?.toString(),
    plan: map['plan']?.toString() ?? 'prueba',
    estado: map['estado']?.toString() ?? 'PRUEBA',
    pruebaHasta: _fecha(map['prueba_hasta']),
    pagadoHasta: _fecha(map['pagado_hasta']),
    barberos: (map['barberos'] as num?)?.toInt() ?? 0,
    citas30d: (map['citas_30d'] as num?)?.toInt() ?? 0,
  );
}

/// Mensaje de soporte visto por el administrador.
class MensajeSoporte {
  const MensajeSoporte({
    required this.negocio,
    required this.mensaje,
    required this.creado,
    this.contexto,
  });

  final String negocio;
  final String mensaje;
  final DateTime? creado;
  final Map<String, dynamic>? contexto;

  factory MensajeSoporte.fromMap(Map<String, dynamic> map) => MensajeSoporte(
    negocio: map['negocio']?.toString() ?? '',
    mensaje: map['mensaje']?.toString() ?? '',
    creado: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    contexto: map['contexto'] is Map
        ? Map<String, dynamic>.from(map['contexto'] as Map)
        : null,
  );
}

abstract interface class AdminRepository {
  Future<bool> esAdmin();
  Future<List<NegocioAdmin>> listarNegocios();
  Future<void> activar({
    required String negocioId,
    required String plan,
    required DateTime hasta,
  });
  Future<void> suspender({required String negocioId, String? motivo});
  Future<List<MensajeSoporte>> listarSoporte();
}

class SupabaseAdminRepository implements AdminRepository {
  const SupabaseAdminRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> esAdmin() async =>
      (await _client.rpc('es_admin_plataforma')) == true;

  @override
  Future<List<NegocioAdmin>> listarNegocios() async {
    final filas = await _client.rpc('admin_listar_negocios') as List<dynamic>;
    return [
      for (final fila in filas)
        NegocioAdmin.fromMap(Map<String, dynamic>.from(fila as Map)),
    ];
  }

  @override
  Future<void> activar({
    required String negocioId,
    required String plan,
    required DateTime hasta,
  }) async {
    await _client.rpc(
      'admin_activar',
      params: {
        'p_negocio': negocioId,
        'p_plan': plan,
        'p_hasta': hasta.toIso8601String().substring(0, 10),
      },
    );
  }

  @override
  Future<void> suspender({required String negocioId, String? motivo}) async {
    await _client.rpc(
      'admin_suspender',
      params: {'p_negocio': negocioId, 'p_motivo': motivo},
    );
  }

  @override
  Future<List<MensajeSoporte>> listarSoporte() async {
    final filas = await _client.rpc('admin_listar_soporte') as List<dynamic>;
    return [
      for (final fila in filas)
        MensajeSoporte.fromMap(Map<String, dynamic>.from(fila as Map)),
    ];
  }
}
