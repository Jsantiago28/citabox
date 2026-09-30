// Datos del negocio que se envían a bootstrap_negocio_owner().
//
// Cuando Supabase exige confirmar el correo, signUp() no entrega sesión.
// Estos datos se guardan en el user_metadata de la cuenta (nunca la
// contraseña) para completar el registro al iniciar sesión desde
// cualquier dispositivo. La función SQL sigue validando todo en backend.
class RegistroNegocio {
  const RegistroNegocio({
    required this.negocioNombre,
    required this.slug,
    this.negocioTelefono = '',
    required this.ownerNombre,
    this.ownerTelefono = '',
  });

  static const metadataKey = 'registro_pendiente';

  final String negocioNombre;
  final String slug;
  final String negocioTelefono;
  final String ownerNombre;
  final String ownerTelefono;

  static RegistroNegocio? fromMetadata(Map<String, dynamic>? metadata) {
    final raw = metadata?[metadataKey];
    if (raw is! Map) return null;

    final negocioNombre = raw['negocio_nombre']?.toString() ?? '';
    final slug = raw['slug']?.toString() ?? '';
    final ownerNombre = raw['owner_nombre']?.toString() ?? '';
    if (negocioNombre.isEmpty || slug.isEmpty || ownerNombre.isEmpty) {
      return null;
    }

    return RegistroNegocio(
      negocioNombre: negocioNombre,
      slug: slug,
      negocioTelefono: raw['negocio_telefono']?.toString() ?? '',
      ownerNombre: ownerNombre,
      ownerTelefono: raw['owner_telefono']?.toString() ?? '',
    );
  }

  Map<String, Object?> toMetadata() => {
    metadataKey: {
      'negocio_nombre': negocioNombre,
      'slug': slug,
      'negocio_telefono': negocioTelefono,
      'owner_nombre': ownerNombre,
      'owner_telefono': ownerTelefono,
    },
  };
}
