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

  /// Cambios de estado que acepta la base (006_horarios_y_reglas.sql).
  bool puedePasarA(EstadoCita nuevo) {
    if (nuevo == this) return true;
    return switch (this) {
      pendiente => nuevo != pendiente,
      confirmada => nuevo != confirmada,
      llego => nuevo == pendiente || nuevo == confirmada || nuevo == completada,
      noVino => nuevo == pendiente || nuevo == confirmada,
      completada => nuevo == llego,
      cancelada => false,
    };
  }

  /// Estado al que vuelve el botón "deshacer" de la agenda, si existe.
  EstadoCita? get deshacer => switch (this) {
    llego || noVino => pendiente,
    completada => llego,
    _ => null,
  };
}

class Cita {
  const Cita({
    required this.id,
    required this.fecha,
    required this.horaInicio,
    required this.precio,
    required this.estado,
    this.horaFin = '',
    this.clienteId = '',
    this.servicioId = '',
    this.empleadoId = '',
    this.notas = '',
    this.clienteNombre = '',
    this.servicioNombre = '',
    this.empleadoNombre = '',
  });

  final String id;
  final String fecha;
  final String horaInicio;

  /// Vacía si la consulta no la trajo.
  final String horaFin;
  final num precio;
  final EstadoCita estado;
  final String clienteId;
  final String servicioId;
  final String empleadoId;
  final String notas;
  final String clienteNombre;
  final String servicioNombre;
  final String empleadoNombre;

  factory Cita.fromMap(Map<String, dynamic> map) {
    String nombreDe(String relacion) =>
        (map[relacion] as Map<String, dynamic>?)?['nombre']?.toString() ?? '';
    String texto(String columna) => map[columna]?.toString() ?? '';

    return Cita(
      id: map['id'].toString(),
      fecha: texto('fecha'),
      horaInicio: texto('hora_inicio'),
      horaFin: texto('hora_fin'),
      precio: num.tryParse(texto('precio')) ?? 0,
      estado: EstadoCita.desde(map['estado']?.toString()),
      clienteId: texto('cliente_id'),
      servicioId: texto('servicio_id'),
      empleadoId: texto('empleado_id'),
      notas: texto('notas'),
      clienteNombre: nombreDe('clientes'),
      servicioNombre: nombreDe('servicios'),
      empleadoNombre: nombreDe('empleados'),
    );
  }

  Cita copyWith({EstadoCita? estado, num? precio}) => Cita(
    id: id,
    fecha: fecha,
    horaInicio: horaInicio,
    horaFin: horaFin,
    precio: precio ?? this.precio,
    estado: estado ?? this.estado,
    clienteId: clienteId,
    servicioId: servicioId,
    empleadoId: empleadoId,
    notas: notas,
    clienteNombre: clienteNombre,
    servicioNombre: servicioNombre,
    empleadoNombre: empleadoNombre,
  );

  Cita conEstado(EstadoCita nuevo) => copyWith(estado: nuevo);
}
