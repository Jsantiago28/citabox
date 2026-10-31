// Enlaces de WhatsApp (wa.me) con mensaje listo, sin API.

import 'formato.dart';

/// Solo los dígitos del teléfono; un número local de 10 dígitos (RD, EE. UU.)
/// lleva delante el código de país 1.
String telefonoWhatsApp(String telefono) {
  final digitos = telefono.replaceAll(RegExp(r'\D'), '');
  return digitos.length == 10 ? '1$digitos' : digitos;
}

/// `https://wa.me/<dígitos>?text=<mensaje codificado>`.
///
/// Si el teléfono no tiene dígitos, el enlace abre WhatsApp para elegir el
/// contacto (`https://wa.me/?text=...`).
String enlaceWhatsApp(String telefono, String mensaje) =>
    'https://wa.me/${telefonoWhatsApp(telefono)}'
    '?text=${Uri.encodeComponent(mensaje)}';

/// Mensaje de recordatorio de una cita.
///
/// [hora] en formato de columna `time` ('15:00:00').
String mensajeRecordatorio({
  required String cliente,
  required String negocio,
  required DateTime fecha,
  required String hora,
  required String servicio,
  String barbero = '',
}) {
  final dia = formatoFechaLarga(fecha);
  final diaMinuscula = dia.isEmpty
      ? dia
      : '${dia[0].toLowerCase()}${dia.substring(1)}';
  final conBarbero = barbero.trim().isEmpty ? '' : ' con ${barbero.trim()}';
  return 'Hola ${cliente.trim()}, te recordamos tu cita en ${negocio.trim()} '
      'el $diaMinuscula a las ${formatoHora(hora)} para ${servicio.trim()}'
      '$conBarbero. ¡Te esperamos!';
}

/// Mensaje para invitar a volver a un cliente que lleva tiempo sin venir.
///
/// [enlace] es el enlace público de reservas; si está vacío, no se incluye.
String mensajeVuelve({
  required String cliente,
  required String negocio,
  String enlace = '',
}) {
  final nombre = cliente.trim().split(RegExp(r'\s+')).first;
  final reserva = enlace.trim().isEmpty
      ? '¿Te apartamos un turno?'
      : 'Reserva cuando quieras aquí: ${enlace.trim()}';
  return 'Hola $nombre, ¡hace tiempo que no te vemos en ${negocio.trim()}! '
      '$reserva';
}
