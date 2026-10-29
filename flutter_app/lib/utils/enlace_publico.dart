// Enlaces públicos (sin cuenta):
//   reservas de un negocio → <origen>/#/reservar/<slug>
//   "Mi cita"              → <origen>/#/cita/<token>

/// Ruta (con hash) de la página pública de reservas.
String rutaReserva(String slug) => '/#/reservar/$slug';

/// Ruta (con hash) de "Mi cita".
String rutaCita(String token) => '/#/cita/$token';

/// Arma el enlace público de reservas.
///
/// En web se pasa `Uri.base` como [base] para usar el origen actual
/// (respetando la carpeta donde esté publicada la app). Sin [base], o si
/// la base no es http(s), devuelve solo la ruta `/#/reservar/<slug>`.
String enlaceReserva(String slug, {Uri? base}) =>
    _conOrigen(rutaReserva(slug), base);

/// Arma el enlace de "Mi cita" (mismas reglas que [enlaceReserva]).
String enlaceCita(String token, {Uri? base}) =>
    _conOrigen(rutaCita(token), base);

String _conOrigen(String ruta, Uri? base) {
  if (base == null || !(base.scheme == 'http' || base.scheme == 'https')) {
    return ruta;
  }

  // Carpeta de la app: se quita el archivo final (p. ej. index.html).
  final path = base.path;
  final carpeta = path.isEmpty ? '' : path.substring(0, path.lastIndexOf('/'));
  return '${base.origin}$carpeta$ruta';
}

/// Página pública a la que apunta una ruta.
sealed class RutaPublica {
  const RutaPublica();

  /// Interpreta `/reservar/<slug>`, `#/cita/<token>`, `reservar/<slug>?x=1`…
  /// Devuelve null si no es una ruta pública (va al flujo con sesión).
  static RutaPublica? desde(String? ruta) {
    if (ruta == null) return null;
    var limpia = ruta.trim();
    if (limpia.startsWith('#')) limpia = limpia.substring(1);
    final corte = limpia.indexOf(RegExp(r'[?#]'));
    if (corte >= 0) limpia = limpia.substring(0, corte);

    final partes = limpia
        .split('/')
        .where((parte) => parte.isNotEmpty)
        .toList(growable: false);
    if (partes.length == 1) {
      return switch (partes[0]) {
        'terminos' => const RutaLegal(RutaLegal.terminos),
        'privacidad' => const RutaLegal(RutaLegal.privacidad),
        _ => null,
      };
    }
    if (partes.length != 2) return null;

    final String valor;
    try {
      valor = Uri.decodeComponent(partes[1]).trim();
    } catch (_) {
      return null; // '%' mal codificado
    }
    if (valor.isEmpty) return null;

    return switch (partes[0]) {
      'reservar' => RutaReserva(valor.toLowerCase()),
      'cita' => RutaCita(valor),
      _ => null,
    };
  }
}

class RutaReserva extends RutaPublica {
  const RutaReserva(this.slug);

  final String slug;
}

class RutaCita extends RutaPublica {
  const RutaCita(this.token);

  final String token;
}

/// Página legal sin datos de negocio: `#/terminos` o `#/privacidad`.
class RutaLegal extends RutaPublica {
  const RutaLegal(this.pagina);

  static const terminos = 'terminos';
  static const privacidad = 'privacidad';

  final String pagina;
}
