// Cálculo puro de la ficha del cliente (sin Flutter ni Supabase).
//
// Reglas (las mismas que el resumen de la lista y los reportes):
// - Visita: cita LLEGO o COMPLETADA. El gasto suma `citas.precio` de las
//   visitas (la propina va aparte, 008_cobro_de_citas.sql).
// - Ticket promedio: gasto / visitas.
// - Faltas (no-shows): citas NO_VINO. Con [ResumenCliente.faltasAviso] o
//   más se avisa que conviene pedir apartado.
// - Próxima cita: la PENDIENTE o CONFIRMADA más cercana desde ahora.
// - Favoritos: el servicio y el barbero más repetidos entre las visitas;
//   si empatan, gana el de la visita más reciente.

import '../models/cita.dart';
import '../models/cliente.dart';
import '../utils/formato.dart';

class FichaCliente {
  const FichaCliente({
    this.visitas = 0,
    this.gastoTotal = 0,
    this.faltas = 0,
    this.cancelaciones = 0,
    this.ultimaVisita,
    this.proximaCita,
    this.servicioFavorito,
    this.barberoFavorito,
  });

  final int visitas;
  final num gastoTotal;
  final int faltas;
  final int cancelaciones;
  final Cita? ultimaVisita;
  final Cita? proximaCita;
  final String? servicioFavorito;
  final String? barberoFavorito;

  num get ticketPromedio =>
      visitas == 0 ? 0 : (gastoTotal * 100 / visitas).round() / 100;

  bool get frecuente => visitas >= ResumenCliente.visitasFrecuente;

  bool get conFaltas => faltas >= ResumenCliente.faltasAviso;
}

/// Calcula los indicadores de la ficha a partir de todas las citas del
/// cliente (en cualquier orden). [ahora] decide qué cita es "próxima".
FichaCliente calcularFichaCliente(List<Cita> citas, {required DateTime ahora}) {
  final momentoActual =
      '${formatoFechaIso(ahora)} '
      '${ahora.hour.toString().padLeft(2, '0')}:'
      '${ahora.minute.toString().padLeft(2, '0')}';

  var visitas = 0;
  var centavos = 0;
  var faltas = 0;
  var cancelaciones = 0;
  Cita? ultima;
  Cita? proxima;
  final servicios = _Conteo();
  final barberos = _Conteo();

  // De la más antigua a la más reciente, para que el desempate de
  // favoritos quede a favor de la visita más reciente.
  final ordenadas = List<Cita>.of(citas)
    ..sort((a, b) => _momento(a).compareTo(_momento(b)));

  for (final cita in ordenadas) {
    switch (cita.estado) {
      case EstadoCita.llego || EstadoCita.completada:
        visitas++;
        centavos += (cita.precio * 100).round();
        ultima = cita;
        servicios.sumar(cita.servicioId, cita.servicioNombre);
        barberos.sumar(cita.empleadoId, cita.empleadoNombre);
      case EstadoCita.noVino:
        faltas++;
      case EstadoCita.cancelada:
        cancelaciones++;
      case EstadoCita.pendiente || EstadoCita.confirmada:
        if (proxima == null && _momento(cita).compareTo(momentoActual) >= 0) {
          proxima = cita;
        }
    }
  }

  return FichaCliente(
    visitas: visitas,
    gastoTotal: centavos / 100,
    faltas: faltas,
    cancelaciones: cancelaciones,
    ultimaVisita: ultima,
    proximaCita: proxima,
    servicioFavorito: servicios.favorito,
    barberoFavorito: barberos.favorito,
  );
}

/// Historial para mostrar: más recientes primero.
List<Cita> ordenarHistorial(List<Cita> citas) =>
    List<Cita>.of(citas)..sort((a, b) => _momento(b).compareTo(_momento(a)));

String _momento(Cita cita) => '${cita.fecha} ${cita.horaInicio}';

class _Conteo {
  final _veces = <String, int>{};
  final _nombres = <String, String>{};
  final _ultimo = <String, int>{};
  var _orden = 0;

  void sumar(String id, String nombre) {
    final clave = id.isNotEmpty ? id : nombre;
    if (clave.isEmpty) return;
    _veces[clave] = (_veces[clave] ?? 0) + 1;
    if (nombre.isNotEmpty) _nombres[clave] = nombre;
    _ultimo[clave] = _orden++;
  }

  String? get favorito {
    String? mejor;
    for (final clave in _veces.keys) {
      if (mejor == null ||
          _veces[clave]! > _veces[mejor]! ||
          (_veces[clave] == _veces[mejor] &&
              _ultimo[clave]! > _ultimo[mejor]!)) {
        mejor = clave;
      }
    }
    return mejor == null ? null : (_nombres[mejor] ?? mejor);
  }
}
