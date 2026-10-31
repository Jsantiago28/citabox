class Cliente {
  const Cliente({
    required this.id,
    required this.nombre,
    this.telefono = '',
    this.email = '',
    this.notas = '',
    this.activo = true,
  });

  final String id;
  final String nombre;
  final String telefono;
  final String email;
  final String notas;
  final bool activo;

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      id: map['id'].toString(),
      nombre: map['nombre']?.toString() ?? '',
      telefono: map['telefono']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      notas: map['notas']?.toString() ?? '',
      activo: map['activo'] == true,
    );
  }
}

/// Visitas y gasto acumulado (citas atendidas) y faltas (citas NO_VINO).
class ResumenCliente {
  const ResumenCliente({
    this.visitas = 0,
    this.gastado = 0,
    this.faltas = 0,
    this.ultimaVisita,
    this.tieneProxima = false,
  });

  /// Días sin venir para considerar que un cliente "no vuelve".
  static const diasNoVuelve = 45;

  /// A partir de cuántas visitas se marca a un cliente como frecuente.
  static const visitasFrecuente = 10;

  /// A partir de cuántas faltas se avisa que conviene pedir apartado.
  static const faltasAviso = 2;

  final int visitas;
  final num gastado;
  final int faltas;

  bool get frecuente => visitas >= visitasFrecuente;

  bool get conFaltas => faltas >= faltasAviso;

  /// Fecha de la última cita atendida (sin hora).
  final DateTime? ultimaVisita;

  /// Tiene una cita pendiente o confirmada de hoy en adelante.
  final bool tieneProxima;

  /// Días desde la última visita, o null si nunca vino.
  int? diasSinVenir(DateTime hoy) {
    final ultima = ultimaVisita;
    if (ultima == null) return null;
    return DateTime(hoy.year, hoy.month, hoy.day).difference(ultima).inDays;
  }

  /// Vino alguna vez, lleva [diasNoVuelve] días o más sin venir y no tiene
  /// otra cita reservada.
  bool noVuelve(DateTime hoy) =>
      !tieneProxima && (diasSinVenir(hoy) ?? 0) >= diasNoVuelve;
}
