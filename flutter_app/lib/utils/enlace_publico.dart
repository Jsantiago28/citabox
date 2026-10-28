// Enlace público de reservas de un negocio: <origen>/#/reservar/<slug>.

/// Ruta (con hash) de la página pública de reservas.
String rutaReserva(String slug) => '/#/reservar/$slug';

/// Arma el enlace público de reservas.
///
/// En web se pasa `Uri.base` como [base] para usar el origen actual
/// (respetando la carpeta donde esté publicada la app). Sin [base], o si
/// la base no es http(s), devuelve solo la ruta `/#/reservar/<slug>`.
String enlaceReserva(String slug, {Uri? base}) {
  final ruta = rutaReserva(slug);
  if (base == null || !(base.scheme == 'http' || base.scheme == 'https')) {
    return ruta;
  }

  // Carpeta de la app: se quita el archivo final (p. ej. index.html).
  final path = base.path;
  final carpeta = path.isEmpty ? '' : path.substring(0, path.lastIndexOf('/'));
  return '${base.origin}$carpeta$ruta';
}
