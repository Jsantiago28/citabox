// Modelos de la reserva pública (RPC de 007_reserva_publica.sql).

import 'cita.dart';

String _texto(Object? valor) => valor?.toString() ?? '';

num _numero(Object? valor) =>
    valor is num ? valor : num.tryParse(_texto(valor)) ?? 0;

int _entero(Object? valor) => _numero(valor).toInt();

Map<String, dynamic> _mapa(Object? valor) =>
    valor is Map ? Map<String, dynamic>.from(valor) : const {};

List<Map<String, dynamic>> _lista(Object? valor) =>
    valor is List ? valor.map(_mapa).toList(growable: false) : const [];

/// '2026-09-18' → DateTime(2026, 9, 18) (fecha local, sin hora).
DateTime fechaDesdeIso(String iso) {
  final partes = iso.split('T').first.split('-');
  if (partes.length != 3) return DateTime(1970);
  return DateTime(
    int.tryParse(partes[0]) ?? 1970,
    int.tryParse(partes[1]) ?? 1,
    int.tryParse(partes[2]) ?? 1,
  );
}

class NegocioPublico {
  const NegocioPublico({
    required this.nombre,
    required this.slug,
    this.telefono = '',
    this.direccion = '',
    this.logo = '',
    this.imagen = '',
    this.moneda = 'DOP',
    this.zonaHoraria = 'America/Santo_Domingo',
    this.apartadoRequerido = false,
    this.apartadoMonto = 0,
    this.apartadoPolitica = '',
    this.apartadoInstrucciones = '',
    this.cancelacionHorasMinimas = 24,
  });

  final String nombre;
  final String slug;
  final String telefono;
  final String direccion;
  final String logo;
  final String imagen;
  final String moneda;
  final String zonaHoraria;
  final bool apartadoRequerido;
  final num apartadoMonto;
  final String apartadoPolitica;
  final String apartadoInstrucciones;
  final int cancelacionHorasMinimas;

  /// Igual que reserva_crear: hay apartado si se exige y el monto es > 0.
  bool get conApartado => apartadoRequerido && apartadoMonto > 0;

  factory NegocioPublico.fromMap(Map<String, dynamic> map) => NegocioPublico(
    nombre: _texto(map['nombre']),
    slug: _texto(map['slug']),
    telefono: _texto(map['telefono']),
    direccion: _texto(map['direccion']),
    logo: _texto(map['logo']),
    imagen: _texto(map['imagen']),
    moneda: map['moneda'] == null ? 'DOP' : _texto(map['moneda']),
    zonaHoraria: map['zona_horaria'] == null
        ? 'America/Santo_Domingo'
        : _texto(map['zona_horaria']),
    apartadoRequerido: map['apartado_requerido'] == true,
    apartadoMonto: _numero(map['apartado_monto']),
    apartadoPolitica: _texto(map['apartado_politica']),
    apartadoInstrucciones: _texto(map['apartado_instrucciones']),
    cancelacionHorasMinimas: map['cancelacion_horas_minimas'] == null
        ? 24
        : _entero(map['cancelacion_horas_minimas']),
  );
}

class ServicioPublico {
  const ServicioPublico({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.duracionMinutos,
    this.descripcion = '',
    this.icono,
    this.imagenUrl = '',
  });

  final String id;
  final String nombre;
  final String descripcion;
  final num precio;
  final int duracionMinutos;
  final String? icono;
  final String imagenUrl;

  factory ServicioPublico.fromMap(Map<String, dynamic> map) => ServicioPublico(
    id: _texto(map['id']),
    nombre: _texto(map['nombre']),
    descripcion: _texto(map['descripcion']),
    precio: _numero(map['precio']),
    duracionMinutos: _entero(map['duracion_minutos']),
    icono: map['icono']?.toString(),
    imagenUrl: _texto(map['imagen_url']),
  );
}

class BarberoPublico {
  const BarberoPublico({
    required this.id,
    required this.nombre,
    this.foto = '',
    this.servicioIds,
  });

  final String id;
  final String nombre;
  final String foto;

  /// null = hace todos los servicios.
  final List<String>? servicioIds;

  bool hace(String servicioId) =>
      servicioIds == null || servicioIds!.contains(servicioId);

  factory BarberoPublico.fromMap(Map<String, dynamic> map) => BarberoPublico(
    id: _texto(map['id']),
    nombre: _texto(map['nombre']),
    foto: _texto(map['foto']),
    servicioIds: map['servicio_ids'] is List
        ? (map['servicio_ids'] as List).map(_texto).toList(growable: false)
        : null,
  );
}

class HorarioDia {
  const HorarioDia({
    required this.diaSemana,
    required this.apertura,
    required this.cierre,
  });

  /// 0 = domingo … 6 = sábado.
  final int diaSemana;
  final String apertura;
  final String cierre;

  factory HorarioDia.fromMap(Map<String, dynamic> map) => HorarioDia(
    diaSemana: _entero(map['dia_semana']),
    apertura: _texto(map['hora_apertura']),
    cierre: _texto(map['hora_cierre']),
  );
}

class CatalogoReserva {
  const CatalogoReserva({
    required this.negocio,
    required this.hoy,
    required this.fechaMaxima,
    this.servicios = const [],
    this.barberos = const [],
    this.horarios = const [],
  });

  final NegocioPublico negocio;
  final DateTime hoy;
  final DateTime fechaMaxima;
  final List<ServicioPublico> servicios;
  final List<BarberoPublico> barberos;
  final List<HorarioDia> horarios;

  List<BarberoPublico> barberosPara(String servicioId) =>
      barberos.where((b) => b.hace(servicioId)).toList(growable: false);

  /// El negocio abre ese día de la semana (sin fila = cerrado).
  bool abre(DateTime fecha) =>
      horarios.any((h) => h.diaSemana == fecha.weekday % 7);

  /// Días entre hoy y la fecha máxima (inclusive).
  List<DateTime> get dias => [
    for (
      var d = hoy;
      !d.isAfter(fechaMaxima);
      d = DateTime(d.year, d.month, d.day + 1)
    )
      d,
  ];

  factory CatalogoReserva.fromMap(Map<String, dynamic> map) => CatalogoReserva(
    negocio: NegocioPublico.fromMap(_mapa(map['negocio'])),
    hoy: fechaDesdeIso(_texto(map['hoy'])),
    fechaMaxima: fechaDesdeIso(_texto(map['fecha_maxima'])),
    servicios: _lista(map['servicios'])
        .map(ServicioPublico.fromMap)
        .toList(growable: false),
    barberos: _lista(map['empleados'])
        .map(BarberoPublico.fromMap)
        .toList(growable: false),
    horarios: _lista(map['horarios'])
        .map(HorarioDia.fromMap)
        .toList(growable: false),
  );
}

class HoraDisponible {
  const HoraDisponible({required this.horaInicio, required this.empleadoId});

  /// 'HH:MM'
  final String horaInicio;
  final String empleadoId;

  factory HoraDisponible.fromMap(Map<String, dynamic> map) => HoraDisponible(
    horaInicio: _texto(map['hora_inicio']),
    empleadoId: _texto(map['empleado_id']),
  );
}

enum EstadoApartado {
  pendiente('PENDIENTE'),
  pagado('PAGADO'),
  cancelado('CANCELADO');

  const EstadoApartado(this.valor);

  final String valor;

  static EstadoApartado desde(String? valor) => EstadoApartado.values
      .firstWhere((e) => e.valor == valor, orElse: () => pendiente);
}

class ApartadoPublico {
  const ApartadoPublico({
    required this.monto,
    this.estado = EstadoApartado.pendiente,
    this.referencia = '',
    this.instrucciones = '',
    this.politica = '',
  });

  final num monto;
  final EstadoApartado estado;
  final String referencia;
  final String instrucciones;
  final String politica;

  /// Ya informó la transferencia y espera que el negocio la valide.
  bool get enRevision =>
      estado == EstadoApartado.pendiente && referencia.isNotEmpty;

  static ApartadoPublico? fromMap(Object? valor) {
    if (valor is! Map) return null;
    final map = _mapa(valor);
    return ApartadoPublico(
      monto: _numero(map['monto']),
      estado: EstadoApartado.desde(map['estado']?.toString()),
      referencia: _texto(map['referencia']),
      instrucciones: _texto(map['instrucciones']),
      politica: _texto(map['politica']),
    );
  }
}

/// "Mi cita": lo que devuelve reserva_consultar (y cancelar, reprogramar,
/// reportar_pago).
class CitaPublica {
  const CitaPublica({
    required this.token,
    required this.estado,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.precio,
    required this.servicioId,
    required this.servicioNombre,
    required this.barberoId,
    required this.barberoNombre,
    required this.negocio,
    this.duracionMinutos = 0,
    this.apartado,
    this.limiteCambios,
    this.puedeCancelar = false,
    this.puedeReprogramar = false,
  });

  final String token;
  final EstadoCita estado;
  final DateTime fecha;

  /// 'HH:MM'
  final String horaInicio;
  final String horaFin;
  final num precio;
  final String servicioId;
  final String servicioNombre;
  final int duracionMinutos;
  final String barberoId;
  final String barberoNombre;
  final NegocioPublico negocio;
  final ApartadoPublico? apartado;

  /// Fecha y hora (del negocio) hasta la que se puede cancelar o cambiar.
  final DateTime? limiteCambios;
  final bool puedeCancelar;
  final bool puedeReprogramar;

  bool get activa =>
      estado == EstadoCita.pendiente || estado == EstadoCita.confirmada;

  factory CitaPublica.fromMap(Map<String, dynamic> map) {
    final servicio = _mapa(map['servicio']);
    final barbero = _mapa(map['barbero']);
    return CitaPublica(
      token: _texto(map['token_publico']),
      estado: EstadoCita.desde(map['estado']?.toString()),
      fecha: fechaDesdeIso(_texto(map['fecha'])),
      horaInicio: _texto(map['hora_inicio']),
      horaFin: _texto(map['hora_fin']),
      precio: _numero(map['precio']),
      servicioId: _texto(servicio['id']),
      servicioNombre: _texto(servicio['nombre']),
      duracionMinutos: _entero(servicio['duracion_minutos']),
      barberoId: _texto(barbero['id']),
      barberoNombre: _texto(barbero['nombre']),
      negocio: NegocioPublico.fromMap(_mapa(map['negocio'])),
      apartado: ApartadoPublico.fromMap(map['apartado']),
      limiteCambios: DateTime.tryParse(_texto(map['limite_cambios'])),
      puedeCancelar: map['puede_cancelar'] == true,
      puedeReprogramar: map['puede_reprogramar'] == true,
    );
  }

  /// Arma "Mi cita" con la respuesta de reserva_crear y lo que ya se
  /// conoce del catálogo (reserva_crear no repite servicio ni negocio).
  factory CitaPublica.desdeReserva({
    required Map<String, dynamic> respuesta,
    required CatalogoReserva catalogo,
    required ServicioPublico servicio,
  }) {
    final empleadoId = _texto(respuesta['empleado_id']);
    final barbero = catalogo.barberos
        .where((b) => b.id == empleadoId)
        .firstOrNull;
    final apartado = ApartadoPublico.fromMap(respuesta['apartado']);
    return CitaPublica(
      token: _texto(respuesta['token_publico']),
      estado: EstadoCita.desde(respuesta['estado']?.toString()),
      fecha: fechaDesdeIso(_texto(respuesta['fecha'])),
      horaInicio: _texto(respuesta['hora_inicio']),
      horaFin: _texto(respuesta['hora_fin']),
      precio: _numero(respuesta['precio']),
      servicioId: servicio.id,
      servicioNombre: servicio.nombre,
      duracionMinutos: servicio.duracionMinutos,
      barberoId: empleadoId,
      barberoNombre: barbero?.nombre ?? '',
      negocio: catalogo.negocio,
      apartado: apartado,
      puedeCancelar: true,
      puedeReprogramar: true,
    );
  }
}
