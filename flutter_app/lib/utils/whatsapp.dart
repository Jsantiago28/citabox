/// Enlace `https://wa.me/<número>?text=<mensaje>`.
///
/// Usa solo los dígitos del teléfono; si quedan 10 (número local de RD o
/// EE. UU.) antepone el código de país 1. Devuelve null sin número.
Uri? enlaceWhatsApp(String telefono, String mensaje) {
  var digitos = telefono.replaceAll(RegExp(r'\D'), '');
  if (digitos.isEmpty) return null;
  if (digitos.length == 10) digitos = '1$digitos';
  return Uri.parse(
    'https://wa.me/$digitos?text=${Uri.encodeComponent(mensaje)}',
  );
}
