// Refleja el enum estado_cita de 001_initial_schema.sql.
enum EstadoCita {
  pendiente('PENDIENTE', 'Pendiente'),
  confirmada('CONFIRMADA', 'Confirmada'),
  llego('LLEGO', 'Llegó'),
  completada('COMPLETADA', 'Completada'),
  noVino('NO_VINO', 'No vino'),
  cancelada('CANCELADA', 'Cancelada');

  const EstadoCita(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  static EstadoCita desde(String? valor) => EstadoCita.values.firstWhere(
    (estado) => estado.valor == valor,
    orElse: () => EstadoCita.pendiente,
  );

  /// El cliente se presentó: cuenta como visita y como venta.
  bool get atendida => this == llego || this == completada;
}

class Cita {
  const Cita({
    required this.id,
    required this.fecha,
    required this.horaInicio,
    required this.precio,
    required this.estado,
    this.clienteNombre = '',
    this.servicioNombre = '',
    this.empleadoNombre = '',
  });

  final String id;
  final String fecha;
  final String horaInicio;
  final num precio;
  final EstadoCita estado;
  final String clienteNombre;
  final String servicioNombre;
  final String empleadoNombre;

  factory Cita.fromMap(Map<String, dynamic> map) {
    String nombreDe(String relacion) =>
        (map[relacion] as Map<String, dynamic>?)?['nombre']?.toString() ?? '';

    return Cita(
      id: map['id'].toString(),
      fecha: map['fecha']?.toString() ?? '',
      horaInicio: map['hora_inicio']?.toString() ?? '',
      precio: num.tryParse(map['precio']?.toString() ?? '') ?? 0,
      estado: EstadoCita.desde(map['estado']?.toString()),
      clienteNombre: nombreDe('clientes'),
      servicioNombre: nombreDe('servicios'),
      empleadoNombre: nombreDe('empleados'),
    );
  }

  Cita conEstado(EstadoCita nuevo) => Cita(
    id: id,
    fecha: fecha,
    horaInicio: horaInicio,
    precio: precio,
    estado: nuevo,
    clienteNombre: clienteNombre,
    servicioNombre: servicioNombre,
    empleadoNombre: empleadoNombre,
  );
}
