// Aviso al crear o editar una cita fuera del horario del negocio o de la
// persona que atiende. Mismas reglas que la reserva en línea (007):
// - El negocio cierra los días sin fila en horarios_negocio.
// - Una persona con horario propio no trabaja los días que no aparecen; su
//   horario se recorta al del negocio. Sin horario propio, usa el del
//   negocio.
// - Un bloqueo (día libre, vacaciones) cubre de fecha_inicio a fecha_fin.
// En la agenda solo se avisa: el dueño puede guardar igual.

import 'citas_reglas.dart';
import 'formato.dart';

/// Rango del día en minutos desde la medianoche.
typedef Rango = ({int desde, int hasta});

/// Días libres de una persona (fechas inclusivas, sin hora).
typedef Bloqueo = ({DateTime desde, DateTime hasta, String motivo});

const _dias = [
  'domingos',
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábados',
];

String _hora(int minutos) => formatoHora(horaDesdeMinutos(minutos));

String _rango(Rango r) => '${_hora(r.desde)} – ${_hora(r.hasta)}';

/// Texto del aviso, o null si la cita cae dentro del horario.
///
/// [negocio] y [empleado] van por `dia_semana` (0 = domingo … 6 = sábado);
/// [empleado] vacío significa que la persona usa el horario del negocio.
/// Sin ningún horario del negocio cargado no se avisa nada (el negocio aún
/// no lo configuró).
String? avisoFueraDeHorario({
  required DateTime fecha,
  required int inicio,
  required int fin,
  required Map<int, Rango> negocio,
  Map<int, Rango> empleado = const {},
  List<Bloqueo> bloqueos = const [],
  String persona = '',
}) {
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  final quien = persona.trim().isEmpty ? 'Esa persona' : persona.trim();

  for (final b in bloqueos) {
    if (!dia.isBefore(b.desde) && !dia.isAfter(b.hasta)) {
      final motivo = b.motivo.trim().isEmpty ? '' : ' (${b.motivo.trim()})';
      return '$quien tiene ese día libre$motivo.';
    }
  }

  if (negocio.isEmpty) return null;
  final semana = dia.weekday % 7;
  final abierto = negocio[semana];
  if (abierto == null) {
    return 'El negocio está cerrado los ${_dias[semana]}.';
  }
  if (inicio < abierto.desde || fin > abierto.hasta) {
    return 'Fuera del horario del negocio (${_rango(abierto)}).';
  }

  if (empleado.isNotEmpty) {
    final propio = empleado[semana];
    if (propio == null) return '$quien no trabaja los ${_dias[semana]}.';
    final turno = (
      desde: propio.desde > abierto.desde ? propio.desde : abierto.desde,
      hasta: propio.hasta < abierto.hasta ? propio.hasta : abierto.hasta,
    );
    if (inicio < turno.desde || fin > turno.hasta) {
      return 'Fuera del horario de $quien (${_rango(turno)}).';
    }
  }
  return null;
}
