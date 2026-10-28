import 'package:supabase_flutter/supabase_flutter.dart';

/// '14:30', '9:05' o '14:30:00' → minutos desde medianoche; null si no es válida.
int? minutosDesdeHora(String hora) {
  final partes = hora.trim().split(':');
  if (partes.length < 2 || partes.length > 3) return null;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  if (partes[1].length != 2) return null;
  return h * 60 + m;
}

/// 870 → '14:30:00' (formato de columna `time` en Postgres).
String horaDesdeMinutos(int minutos) =>
    '${(minutos ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutos % 60).toString().padLeft(2, '0')}:00';

/// hora_fin = hora_inicio + duración del servicio.
///
/// Devuelve null si la hora no es válida o si la cita terminaría después de
/// medianoche (la base exige hora_fin > hora_inicio en el mismo día).
String? calcularHoraFin(String horaInicio, int duracionMinutos) {
  final inicio = minutosDesdeHora(horaInicio);
  if (inicio == null || duracionMinutos <= 0) return null;
  final fin = inicio + duracionMinutos;
  if (fin >= 24 * 60) return null;
  return horaDesdeMinutos(fin);
}

const mensajeSolapamiento = 'Ese barbero ya tiene una cita en ese horario.';
const mensajeEstadoNoPermitido = 'Ese cambio de estado no está permitido.';

/// Traduce los errores de Postgres que la agenda sabe explicar.
String mensajeErrorCita(
  Object error, {
  String porDefecto = 'No se pudo guardar la cita.',
}) {
  if (error is PostgrestException) {
    switch (error.code) {
      case '23P01': // exclusion_violation (005_citas_sin_solapamiento.sql)
        return mensajeSolapamiento;
      case '23514': // check_violation (006_horarios_y_reglas.sql)
        return mensajeEstadoNoPermitido;
    }
  }
  return porDefecto;
}
