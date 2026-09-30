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

/// Visitas y gasto acumulado, calculados desde las citas atendidas.
class ResumenCliente {
  const ResumenCliente({this.visitas = 0, this.gastado = 0});

  /// A partir de cuántas visitas se marca a un cliente como frecuente.
  static const visitasFrecuente = 10;

  final int visitas;
  final num gastado;

  bool get frecuente => visitas >= visitasFrecuente;
}
