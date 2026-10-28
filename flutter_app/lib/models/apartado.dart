import 'cita.dart';

// Refleja el enum estado_apartado de 001_initial_schema.sql.
enum EstadoApartado {
  pendiente('PENDIENTE', 'Por validar'),
  pagado('PAGADO', 'Pagado'),
  cancelado('CANCELADO', 'Cancelado');

  const EstadoApartado(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  static EstadoApartado desde(String? valor) =>
      EstadoApartado.values.firstWhere(
        (estado) => estado.valor == valor,
        orElse: () => EstadoApartado.pendiente,
      );
}

/// Métodos con los que el dueño registra un apartado recibido.
enum MetodoPago {
  transferencia('TRANSFERENCIA', 'Transferencia'),
  efectivo('EFECTIVO', 'Efectivo'),
  tarjeta('TARJETA', 'Tarjeta');

  const MetodoPago(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  static MetodoPago? desde(String? valor) {
    for (final metodo in MetodoPago.values) {
      if (metodo.valor == valor) return metodo;
    }
    return null;
  }
}

/// Apartado con los datos de su cita (cliente, servicio, barbero y hora).
class Apartado {
  const Apartado({
    required this.id,
    required this.citaId,
    required this.monto,
    required this.estado,
    this.metodoPago = '',
    this.referencia = '',
    this.fechaPago = '',
    this.creado = '',
    this.fecha = '',
    this.horaInicio = '',
    this.estadoCita = EstadoCita.pendiente,
    this.empleadoId = '',
    this.clienteNombre = '',
    this.clienteTelefono = '',
    this.servicioNombre = '',
    this.empleadoNombre = '',
  });

  /// Columnas para `from('apartados').select(...)`.
  static const columnas =
      'id, cita_id, monto, estado, metodo_pago, referencia, fecha_pago, '
      'created_at, citas!inner(fecha, hora_inicio, estado, empleado_id, '
      'clientes(nombre, telefono), servicios(nombre), empleados(nombre))';

  final String id;
  final String citaId;
  final num monto;
  final EstadoApartado estado;
  final String metodoPago;
  final String referencia;
  final String fechaPago;
  final String creado;
  final String fecha;
  final String horaInicio;
  final EstadoCita estadoCita;
  final String empleadoId;
  final String clienteNombre;
  final String clienteTelefono;
  final String servicioNombre;
  final String empleadoNombre;

  bool get tieneReferencia => referencia.trim().isNotEmpty;

  /// Fecha y hora de la cita, para ordenar.
  String get momentoCita => '$fecha $horaInicio';

  factory Apartado.fromMap(Map<String, dynamic> map) {
    final cita = map['citas'] as Map<String, dynamic>? ?? const {};
    String texto(Map<String, dynamic> origen, String columna) =>
        origen[columna]?.toString() ?? '';
    String deRelacion(String relacion, String columna) =>
        (cita[relacion] as Map<String, dynamic>?)?[columna]?.toString() ?? '';

    return Apartado(
      id: texto(map, 'id'),
      citaId: texto(map, 'cita_id'),
      monto: num.tryParse(texto(map, 'monto')) ?? 0,
      estado: EstadoApartado.desde(map['estado']?.toString()),
      metodoPago: texto(map, 'metodo_pago'),
      referencia: texto(map, 'referencia'),
      fechaPago: texto(map, 'fecha_pago'),
      creado: texto(map, 'created_at'),
      fecha: texto(cita, 'fecha'),
      horaInicio: texto(cita, 'hora_inicio'),
      estadoCita: EstadoCita.desde(cita['estado']?.toString()),
      empleadoId: texto(cita, 'empleado_id'),
      clienteNombre: deRelacion('clientes', 'nombre'),
      clienteTelefono: deRelacion('clientes', 'telefono'),
      servicioNombre: deRelacion('servicios', 'nombre'),
      empleadoNombre: deRelacion('empleados', 'nombre'),
    );
  }
}
