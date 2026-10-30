/// Datos editables del negocio (tabla `negocios`).
class ConfiguracionNegocio {
  const ConfiguracionNegocio({
    required this.id,
    required this.nombre,
    required this.slug,
    this.telefono = '',
    this.direccion = '',
    this.logo = '',
    this.imagen = '',
    this.colorPrincipal = '',
    this.apartadoRequerido = true,
    this.apartadoMonto = 100,
    this.apartadoPolitica = '',
    this.apartadoInstrucciones = '',
    this.cancelacionHorasMinimas = 24,
    this.intervaloReservaMinutos = 15,
    this.recordatorioWhatsapp = false,
    this.recordatorioHoras = 24,
  });

  static const columnas =
      'id, nombre, slug, telefono, direccion, logo, imagen, color_principal, '
      'apartado_requerido, apartado_monto, apartado_politica, '
      'apartado_instrucciones, cancelacion_horas_minimas, '
      'intervalo_reserva_minutos, recordatorio_whatsapp, recordatorio_horas';

  final String id;
  final String nombre;
  final String slug;
  final String telefono;
  final String direccion;
  final String logo;
  final String imagen;
  final String colorPrincipal;
  final bool apartadoRequerido;
  final num apartadoMonto;
  final String apartadoPolitica;
  final String apartadoInstrucciones;
  final int cancelacionHorasMinimas;
  final int intervaloReservaMinutos;

  /// Recordatorio automático por WhatsApp [recordatorioHoras] antes de la cita.
  final bool recordatorioWhatsapp;
  final int recordatorioHoras;

  factory ConfiguracionNegocio.fromMap(Map<String, dynamic> map) {
    String texto(String clave) => map[clave]?.toString() ?? '';
    int entero(String clave, int defecto) =>
        int.tryParse(texto(clave)) ?? defecto;

    return ConfiguracionNegocio(
      id: texto('id'),
      nombre: texto('nombre'),
      slug: texto('slug'),
      telefono: texto('telefono'),
      direccion: texto('direccion'),
      logo: texto('logo'),
      imagen: texto('imagen'),
      colorPrincipal: texto('color_principal'),
      apartadoRequerido: map['apartado_requerido'] != false,
      apartadoMonto: num.tryParse(texto('apartado_monto')) ?? 0,
      apartadoPolitica: texto('apartado_politica'),
      apartadoInstrucciones: texto('apartado_instrucciones'),
      cancelacionHorasMinimas: entero('cancelacion_horas_minimas', 24),
      intervaloReservaMinutos: entero('intervalo_reserva_minutos', 15),
      recordatorioWhatsapp: map['recordatorio_whatsapp'] == true,
      recordatorioHoras: entero('recordatorio_horas', 24),
    );
  }
}

/// Recordatorios por WhatsApp enviados en el mes (`uso_whatsapp_mes`).
class UsoWhatsapp {
  const UsoWhatsapp({
    required this.enviados,
    required this.cupo,
    this.extra = 0,
    this.precioExtra = 0,
    this.montoExtra = 0,
    this.prueba = false,
  });

  final int enviados;

  /// Mensajes incluidos en el plan cada mes.
  final int cupo;

  /// Enviados por encima del cupo (se cobran aparte).
  final int extra;
  final num precioExtra;
  final num montoExtra;

  /// En la prueba gratis el cupo es un tope: no se envía más.
  final bool prueba;

  factory UsoWhatsapp.fromMap(Map<String, dynamic> map) {
    int entero(String clave) => (map[clave] as num?)?.toInt() ?? 0;
    return UsoWhatsapp(
      enviados: entero('enviados'),
      cupo: entero('cupo'),
      extra: entero('extra'),
      precioExtra: (map['precio_extra'] as num?) ?? 0,
      montoExtra: (map['monto_extra'] as num?) ?? 0,
      prueba: map['prueba'] == true,
    );
  }
}

/// Horario de apertura de un día (tabla `horarios_negocio`).
///
/// [diaSemana]: 0 = domingo … 6 = sábado. Las horas van en minutos desde
/// la medianoche. Un día sin horario se considera cerrado.
class HorarioDia {
  const HorarioDia({
    required this.diaSemana,
    required this.apertura,
    required this.cierre,
  });

  final int diaSemana;
  final int apertura;
  final int cierre;

  bool get valido => cierre > apertura;

  factory HorarioDia.fromMap(Map<String, dynamic> map) {
    return HorarioDia(
      diaSemana: int.parse(map['dia_semana'].toString()),
      apertura: minutosDesdeTexto(map['hora_apertura'].toString()) ?? 0,
      cierre: minutosDesdeTexto(map['hora_cierre'].toString()) ?? 0,
    );
  }

  Map<String, Object?> toMap(String negocioId) => {
    'negocio_id': negocioId,
    'dia_semana': diaSemana,
    'hora_apertura': '${textoDesdeMinutos(apertura)}:00',
    'hora_cierre': '${textoDesdeMinutos(cierre)}:00',
  };

  @override
  bool operator ==(Object other) =>
      other is HorarioDia &&
      other.diaSemana == diaSemana &&
      other.apertura == apertura &&
      other.cierre == cierre;

  @override
  int get hashCode => Object.hash(diaSemana, apertura, cierre);

  @override
  String toString() =>
      'HorarioDia($diaSemana, ${textoDesdeMinutos(apertura)}-'
      '${textoDesdeMinutos(cierre)})';
}

/// Nombres de los días según `dia_semana` (0 = domingo).
const nombresDiaSemana = [
  'Domingo',
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
];

/// '09:30' o '09:30:00' → 570. Devuelve null si el texto no es una hora.
int? minutosDesdeTexto(String texto) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$')
      .firstMatch(texto.trim());
  if (match == null) return null;
  final horas = int.parse(match.group(1)!);
  final minutos = int.parse(match.group(2)!);
  if (horas > 23 || minutos > 59) return null;
  return horas * 60 + minutos;
}

/// 570 → '09:30'.
String textoDesdeMinutos(int minutos) {
  final h = (minutos ~/ 60).toString().padLeft(2, '0');
  final m = (minutos % 60).toString().padLeft(2, '0');
  return '$h:$m';
}
