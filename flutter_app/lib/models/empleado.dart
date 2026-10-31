class Empleado {
  const Empleado({
    required this.id,
    required this.nombre,
    this.telefono = '',
    this.activo = true,
    this.perfilId,
    this.comisionPct = 0,
    this.foto = '',
  });

  final String id;
  final String nombre;
  final String telefono;
  final bool activo;

  /// Cuenta de la app ligada a la ficha; null si aún no tiene cuenta.
  final String? perfilId;

  /// Comisión del barbero en porcentaje (0 a 100).
  final num comisionPct;

  /// Dirección pública de la foto (Storage); vacía si no tiene.
  final String foto;

  bool get tieneCuenta => perfilId != null && perfilId!.isNotEmpty;

  factory Empleado.fromMap(Map<String, dynamic> map) {
    return Empleado(
      id: map['id'].toString(),
      nombre: map['nombre']?.toString() ?? '',
      telefono: map['telefono']?.toString() ?? '',
      activo: map['activo'] == true,
      perfilId: map['perfil_id']?.toString(),
      comisionPct: num.tryParse(map['comision_pct']?.toString() ?? '') ?? 0,
      foto: map['foto']?.toString() ?? '',
    );
  }
}

/// Días en el orden de la base: 0 = domingo … 6 = sábado.
const nombresDias = [
  'Domingo',
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
];

/// Orden en que se muestran los días: lunes primero.
const ordenDias = [1, 2, 3, 4, 5, 6, 0];

/// Un rango de trabajo para un día de la semana. Horas en formato 'HH:MM'.
class HorarioDia {
  const HorarioDia({
    required this.diaSemana,
    required this.horaInicio,
    required this.horaFin,
  });

  final int diaSemana;
  final String horaInicio;
  final String horaFin;

  factory HorarioDia.fromMap(Map<String, dynamic> map) {
    return HorarioDia(
      diaSemana: int.parse(map['dia_semana'].toString()),
      horaInicio: _horaCorta(map['hora_inicio']),
      horaFin: _horaCorta(map['hora_fin']),
    );
  }
}

/// Día libre o vacaciones: de [fechaInicio] a [fechaFin], ambos incluidos.
class BloqueoEmpleado {
  const BloqueoEmpleado({
    required this.id,
    required this.fechaInicio,
    required this.fechaFin,
    this.motivo = '',
  });

  final String id;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String motivo;

  factory BloqueoEmpleado.fromMap(Map<String, dynamic> map) {
    return BloqueoEmpleado(
      id: map['id'].toString(),
      fechaInicio: DateTime.parse(map['fecha_inicio'].toString()),
      fechaFin: DateTime.parse(map['fecha_fin'].toString()),
      motivo: map['motivo']?.toString() ?? '',
    );
  }
}

/// '09:00:00' → '09:00'
String _horaCorta(Object? valor) {
  final texto = valor?.toString() ?? '';
  return texto.length >= 5 ? texto.substring(0, 5) : texto;
}
