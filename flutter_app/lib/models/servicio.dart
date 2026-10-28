class Servicio {
  const Servicio({
    required this.id,
    required this.nombre,
    this.descripcion = '',
    this.precio = 0,
    this.duracionMinutos = 30,
    this.activo = true,
  });

  final String id;
  final String nombre;
  final String descripcion;
  final num precio;
  final int duracionMinutos;
  final bool activo;

  factory Servicio.fromMap(Map<String, dynamic> map) {
    return Servicio(
      id: map['id'].toString(),
      nombre: map['nombre']?.toString() ?? '',
      descripcion: map['descripcion']?.toString() ?? '',
      precio: num.tryParse(map['precio']?.toString() ?? '') ?? 0,
      duracionMinutos:
          int.tryParse(map['duracion_minutos']?.toString() ?? '') ?? 0,
      activo: map['activo'] == true,
    );
  }
}

/// 45 → '45 min' · 60 → '1 h' · 75 → '1 h 15 min'
String formatoDuracion(int minutos) {
  if (minutos < 60) return '$minutos min';
  final horas = minutos ~/ 60;
  final resto = minutos % 60;
  return resto == 0 ? '$horas h' : '$horas h $resto min';
}
