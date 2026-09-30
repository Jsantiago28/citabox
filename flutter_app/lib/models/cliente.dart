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
