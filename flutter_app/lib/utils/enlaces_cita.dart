// Enlaces para después de reservar: Google Calendar, archivo .ics y WhatsApp.

import '../models/reserva.dart';
import 'formato.dart';
import 'whatsapp.dart';

/// Diferencia con UTC (horas) de zonas sin horario de verano. Con ellas el
/// .ics lleva la hora exacta en UTC; con otras zonas usa hora "flotante"
/// (la del teléfono), que coincide si el cliente está en el mismo país.
const _desfaseZonas = {
  'America/Santo_Domingo': -4,
  'America/Puerto_Rico': -4,
  'America/Bogota': -5,
  'America/Lima': -5,
  'America/Panama': -5,
};

String _dos(int n) => n.toString().padLeft(2, '0');

/// DateTime(2026, 10, 30, 15) → '20261030T150000'
String _sello(DateTime f) =>
    '${f.year.toString().padLeft(4, '0')}${_dos(f.month)}${_dos(f.day)}'
    'T${_dos(f.hour)}${_dos(f.minute)}00';

// Se usa DateTime.utc como contenedor "sin zona" para evitar saltos de horario
// de verano del teléfono al sumar o restar horas.
DateTime _conHora(DateTime fecha, String hora) {
  final partes = hora.split(':');
  return DateTime.utc(
    fecha.year,
    fecha.month,
    fecha.day,
    int.tryParse(partes.first) ?? 0,
    partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0,
  );
}

DateTime _inicio(CitaPublica cita) => _conHora(cita.fecha, cita.horaInicio);

DateTime _fin(CitaPublica cita) {
  if (cita.horaFin.isNotEmpty) return _conHora(cita.fecha, cita.horaFin);
  return _inicio(cita).add(
    Duration(minutes: cita.duracionMinutos > 0 ? cita.duracionMinutos : 30),
  );
}

String tituloEventoCita(CitaPublica cita) =>
    '${cita.servicioNombre} en ${cita.negocio.nombre}';

String _detallesEvento(CitaPublica cita, String? enlaceMiCita) => [
  if (cita.barberoNombre.isNotEmpty) 'Barbero: ${cita.barberoNombre}',
  'Precio: ${formatoMoneda(cita.precio, cita.negocio.moneda)}',
  if (cita.negocio.telefono.isNotEmpty) 'Teléfono: ${cita.negocio.telefono}',
  if (enlaceMiCita != null && enlaceMiCita.isNotEmpty)
    'Ver, cambiar o cancelar: $enlaceMiCita',
].join('\n');

/// Enlace "Agregar a Google Calendar" con la hora del negocio (ctz).
String enlaceGoogleCalendar(CitaPublica cita, {String? enlaceMiCita}) {
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': tituloEventoCita(cita),
    'dates': '${_sello(_inicio(cita))}/${_sello(_fin(cita))}',
    'details': _detallesEvento(cita, enlaceMiCita),
    if (cita.negocio.direccion.isNotEmpty) 'location': cita.negocio.direccion,
    'ctz': cita.negocio.zonaHoraria,
  }).toString();
}

String _escaparIcs(String texto) => texto
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\n', r'\n');

/// Contenido del archivo .ics (Apple Calendar, Outlook…).
String contenidoIcs(CitaPublica cita, {String? enlaceMiCita, DateTime? ahora}) {
  final desfase = _desfaseZonas[cita.negocio.zonaHoraria];
  String fechaIcs(DateTime local) => desfase == null
      ? _sello(local)
      : '${_sello(local.subtract(Duration(hours: desfase)))}Z';
  final marca = (ahora ?? DateTime.now()).toUtc();

  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Barberia PRO//Reservas//ES',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:${cita.token}@barberiapro',
    'DTSTAMP:${_sello(marca)}Z',
    'DTSTART:${fechaIcs(_inicio(cita))}',
    'DTEND:${fechaIcs(_fin(cita))}',
    'SUMMARY:${_escaparIcs(tituloEventoCita(cita))}',
    'DESCRIPTION:${_escaparIcs(_detallesEvento(cita, enlaceMiCita))}',
    if (cita.negocio.direccion.isNotEmpty)
      'LOCATION:${_escaparIcs(cita.negocio.direccion)}',
    'BEGIN:VALARM',
    'TRIGGER:-PT2H',
    'ACTION:DISPLAY',
    'DESCRIPTION:${_escaparIcs(tituloEventoCita(cita))}',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

/// WhatsApp del negocio (helper común de `whatsapp.dart`); null si el
/// negocio no tiene un teléfono válido, para no mostrar el botón.
String? enlaceWhatsAppNegocio(String telefono, String mensaje) {
  if (telefonoWhatsApp(telefono).length < 7) return null;
  return enlaceWhatsApp(telefono, mensaje);
}

/// Mensaje para escribirle al negocio sobre una cita.
String mensajeWhatsAppCita(CitaPublica cita, {String? enlaceMiCita}) {
  final buffer = StringBuffer(
    'Hola, tengo una cita en ${cita.negocio.nombre}: ${cita.servicioNombre}'
    ' el ${formatoFechaLarga(cita.fecha).toLowerCase()}'
    ' a las ${formatoHora(cita.horaInicio)}',
  );
  if (cita.barberoNombre.isNotEmpty) {
    buffer.write(' con ${cita.barberoNombre}');
  }
  buffer.write('.');
  if (enlaceMiCita != null && enlaceMiCita.isNotEmpty) {
    buffer.write(' Mi cita: $enlaceMiCita');
  }
  return buffer.toString();
}
